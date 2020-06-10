module Rover
  class Vector
    TYPE_CAST_MAPPING = {
      bool: Numo::Bit,
      float32: Numo::SFloat,
      float: Numo::DFloat,
      int8: Numo::Int8,
      int16: Numo::Int16,
      int32: Numo::Int32,
      int: Numo::Int64,
      object: Numo::RObject
    }

    def initialize(data, type: nil)
      numo_type = self.numo_type(type) if type

      data = data.to_numo if data.is_a?(Vector)

      if data.is_a?(Numo::NArray)
        if type
          if type =~ /int/ && (data.is_a?(Numo::SFloat) || data.is_a?(Numo::DFloat) || data.is_a?(Numo::RObject))
            missing = data.isnan.any? || data.isinf.any?
            missing |= data.to_a.any?(&:nil?) if data.is_a?(Numo::RObject)
            raise "Cannot convert missing or infinite values to int" if missing
          end

          if data.is_a?(Numo::RObject) && type =~ /float/
            data = data.to_a.map { |v| v.nil? ? Float::NAN : v.to_f }
          elsif data.is_a?(Numo::RObject) && type =~ /int/
            data = data.to_a.map(&:to_i)
          end

          data = numo_type.cast(data)
        end
      else
        data = data.to_a

        if type
          # TODO more safety checks
          data = numo_type.cast(data)
        else
          data =
            if data.all? { |v| v.is_a?(Integer) }
              Numo::Int64.cast(data)
            elsif data.all? { |v| v.is_a?(Numeric) || v.nil? }
              Numo::DFloat.cast(data.map { |v| v || Float::NAN })
            elsif data.all? { |v| v == true || v == false }
              Numo::Bit.cast(data)
            else
              Numo::RObject.cast(data)
            end
          end
      end

      @data = data

      raise ArgumentError, "Bad size: #{@data.shape}" unless @data.ndim == 1
    end

    def type
      type = TYPE_CAST_MAPPING.find { |_, v| @data.is_a?(v) }
      if type
        type[0]
      else
        raise "Unknown type"
      end
    end

    def to(type)
      Vector.new(self, type: type)
    end

    def to_numo
      @data
    end

    def to_a
      a = @data.to_a
      a.map! { |v| !v.zero? } if @data.is_a?(Numo::Bit)
      a
    end

    def size
      @data.size
    end
    alias_method :length, :size
    alias_method :count, :size

    def uniq
      Vector.new(@data.to_a.uniq)
    end

    def missing
      bit =
        if @data.is_a?(Numo::RObject)
          Numo::Bit.cast(@data.map(&:nil?))
        elsif @data.respond_to?(:isnan)
          @data.isnan
        else
          Numo::Bit.new(size).fill(0)
        end

      Vector.new(bit)
    end

    # keep same number of rows as original
    # to make it easy to add to original data frame
    def diff
      diff = @data.cast_to(Numo::DFloat).diff
      Vector.new(diff.insert(0, Float::NAN))
    end

    def [](v)
      if v.is_a?(Vector)
        Vector.new(v.to_numo.mask(@data))
      else
        @data[v]
      end
    end

    def []=(k, v)
      k = k.to_numo if k.is_a?(Vector)
      @data[k] = v
    end

    %w(+ - * / % ** &).each do |op|
      define_method(op) do |other|
        other = other.to_numo if other.is_a?(Vector)
        # TODO better logic
        if @data.is_a?(Numo::RObject)
          map { |v| v.send(op, other) }
        else
          Vector.new(@data.send(op, other))
        end
      end
    end

    {
      "==" => "eq",
      "!=" => "ne",
      ">" => "gt",
      ">=" => "ge",
      "<" => "lt",
      "<=" => "le"
    }.each do |op, meth|
      define_method(op) do |other|
        other = other.to_numo if other.is_a?(Vector)
        v =
          if other.is_a?(Numo::RObject)
            @data.to_a.zip(other).map { |v, ov| v == ov }
          elsif other.is_a?(Numeric) || other.is_a?(Numo::NArray)
            @data.send(meth, other)
          else
            @data.map { |v| v.send(op, other) }
          end
        Vector.new(Numo::Bit.cast(v))
      end
    end

    def in?(values)
      ret = Numo::Bit.new(size).fill(false)
      values.each do |v|
        comp =
          if v.is_a?(Numeric) || v.is_a?(Numo::NArray)
            @data.eq(v)
          else
            Numo::Bit.cast(@data.map { |d| d == v })
          end
        ret |= comp
      end
      Vector.new(ret)
    end

    def !
      if @data.is_a?(Numo::Bit)
        Vector.new(@data.eq(0))
      else
        raise "Not implemented yet"
      end
    end

    def -@
      self * -1
    end

    def clamp!(min, max)
      @data = @data.clip(min, max)
      self
    end

    def clamp(min, max)
      dup.clamp!(min, max)
    end

    def map(&block)
      mapped = @data.map(&block)
      mapped = mapped.to_a if mapped.is_a?(Numo::RObject) # re-evaluate cast
      Vector.new(mapped)
    end

    def tally
      result = Hash.new(0)
      @data.each do |v|
        result[v] += 1
      end
      result.default = nil
      result
    end

    def sort
      Vector.new(@data.respond_to?(:sort) ? @data.sort : @data.to_a.sort)
    end

    def abs
      Vector.new(@data.abs)
    end

    def each(&block)
      @data.each(&block)
    end

    def each_with_index(&block)
      @data.each_with_index(&block)
    end

    def max
      @data.max
    end

    def min
      @data.min
    end

    def mean
      # currently only floats have mean in Numo
      # https://github.com/ruby-numo/numo-narray/issues/79
      @data.cast_to(Numo::DFloat).mean
    end

    def median
      # need to cast to get correct result
      # https://github.com/ruby-numo/numo-narray/issues/165
      @data.cast_to(Numo::DFloat).median
    end

    def percentile(q)
      @data.percentile(q)
    end

    def sum
      @data.sum
    end

    # uses Bessel's correction for now since that's all Numo supports
    def std
      @data.cast_to(Numo::DFloat).stddev
    end

    # uses Bessel's correction for now since that's all Numo supports
    def var
      @data.cast_to(Numo::DFloat).var
    end

    def all?(&block)
      @data.to_a.all?(&block)
    end

    def any?(&block)
      @data.to_a.any?(&block)
    end

    def first(n = 1)
      if n >= size
        Vector.new(@data)
      else
        Vector.new(@data[0...n])
      end
    end

    def last(n = 1)
      Vector.new(@data[-n..-1])
    end

    def take(n)
      raise ArgumentError, "attempt to take negative size" if n < 0
      first(n)
    end

    def crosstab(other)
      index = uniq.sort
      index_pos = index.to_a.map.with_index.to_h
      df = DataFrame.new({"_" => index})
      other.uniq.sort.each do |k|
        df[k] = 0
      end
      to_a.zip(other.to_a) do |v1, v2|
        df[v2][index_pos[v1]] += 1
      end
      df
    end

    def head(n = 5)
      n += size if n < 0
      first(n)
    end

    def tail(n = 5)
      n += size if n < 0
      last(n)
    end

    def one_hot(drop: false, prefix: nil)
      raise ArgumentError, "All elements must be strings" unless all? { |vi| vi.is_a?(String) }

      new_vectors = {}
      # maybe sort values first
      values = uniq.to_a
      values.shift if drop
      values.each do |v2|
        # TODO use types
        new_vectors["#{prefix}#{v2}"] = (self == v2).to_numo.cast_to(Numo::Int64)
      end
      DataFrame.new(new_vectors)
    end

    # TODO add type and size?
    def inspect
      elements = first(5).to_a.map(&:inspect)
      elements << "..." if size > 5
      "#<Rover::Vector [#{elements.join(", ")}]>"
    end
    alias_method :to_s, :inspect # alias like hash

    # for IRuby
    def to_html
      require "iruby"
      IRuby::HTML.table(to_a)
    end

    private

    def numo_type(type)
      numo_type = TYPE_CAST_MAPPING[type]
      raise ArgumentError, "Invalid type: #{type}" unless numo_type
      numo_type
    end
  end
end
