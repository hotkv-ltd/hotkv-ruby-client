# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  # Formatting of numeric command arguments, in one place.
  #
  # Ruby's Float#to_s switches to exponent form for small and large values
  # ("1.0e-05", "1.0e+16"). Several server parsers refuse that form: the
  # fixed point USD parser behind LLMBUDGET.SET and LLMSTATS.PRICE SET accepts
  # plain digits only, with no exponent. Every Float, BigDecimal or Rational a
  # caller hands to a command is therefore written by #float: plain decimal,
  # the shortest digits that round trip, never an exponent, never locale
  # dependent (no String#% or Kernel#format involved).
  module Wire
    module_function

    FLOAT_PARTS = /\A(-?)(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?\z/.freeze
    private_constant :FLOAT_PARTS

    # Plain decimal text for +value+ (Integer, Float, BigDecimal, Rational).
    # Infinity becomes "inf"/"-inf" (what the server's score parsers accept);
    # NaN raises HotKV::Error::ArgumentError.
    def float(value)
      case value
      when Integer then value.to_s
      when Float then float_text(value)
      when Rational then float_text(value.to_f)
      when Numeric
        raise Error::ArgumentError, "cannot format #{value.class} as a number" if value.respond_to?(:real?) && !value.real?

        decimal_text(value)
      else
        raise Error::ArgumentError, "expected a number, got #{value.inspect}"
      end
    end

    # Parses a float out of a server reply. Numbers pass through; Strings
    # follow strtod, which is what the server prints with: "inf", "+inf",
    # "-inf", "infinity" and "nan" (any case) as well as ordinary decimals and
    # exponent forms. Kernel#Float alone refuses "inf", which a RESP2 reply
    # gives for an infinite sorted set score.
    def parse_float(value)
      return value.to_f if value.is_a?(Numeric)
      raise TypeError, "can't convert #{value.class} into Float" unless value.is_a?(String)

      case value.downcase
      when "inf", "+inf", "infinity", "+infinity" then Float::INFINITY
      when "-inf", "-infinity" then -Float::INFINITY
      when "nan", "+nan", "-nan" then Float::NAN
      else Float(value)
      end
    end

    # Returns +value+ unchanged after refusing NaN and +/-Infinity, for the
    # arguments where the server accepts finite numbers only (INCRBYFLOAT,
    # coordinates, similarity thresholds, vector components, ...). Non numeric
    # values (Strings, nil) are passed through for the server to judge.
    def finite(value)
      if value.is_a?(Numeric) && !value.is_a?(Integer) && !value.is_a?(Rational)
        raise Error::ArgumentError, "expected a finite number, got #{value}" if value.nan? || value.infinite?
      end
      value
    end

    # Applies #finite to every component of +vector+ and returns an Array.
    def finite_vector(vector)
      Array(vector).map { |component| finite(component) }
    end

    # Comma joined plain decimal components, the form RAG.INGEST VECTORS and
    # RAG.SEARCH VECTOR take.
    def csv_vector(vector)
      Array(vector).map { |component| float(finite(component)) }.join(",")
    end

    # A US dollar amount in the fixed point form the server's money parser
    # takes: digits, an optional dot and at most 6 decimals (micro dollars),
    # no sign, no exponent, never ".5" or "5.". Numbers are rounded to the
    # nearest micro dollar; negative, NaN and infinite values raise, and so
    # does a non zero amount too small to survive the rounding (it would
    # otherwise silently become 0, which means "no limit" to LLMBUDGET.SET).
    # Strings pass through untouched for the server to validate.
    def usd(value)
      return value if value.is_a?(String)
      raise Error::ArgumentError, "expected a USD amount, got #{value.inspect}" unless value.is_a?(Numeric)

      text = float(value)
      raise Error::ArgumentError, "USD amount must be finite, got #{value}" if text.end_with?("inf")
      raise Error::ArgumentError, "USD amount must not be negative, got #{value}" if text.start_with?("-") && text != "-0"

      micros = (Rational(text) * 1_000_000).round
      raise Error::ArgumentError, "USD amount #{text} is below one micro dollar" if micros.zero? && Rational(text) != 0

      whole, frac = micros.divmod(1_000_000)
      return whole.to_s if frac.zero?

      "#{whole}.#{frac.to_s.rjust(6, '0').sub(/0+\z/, '')}"
    end

    def float_text(value)
      raise Error::ArgumentError, "NaN is not a valid number" if value.nan?
      return(value.positive? ? "inf" : "-inf") if value.infinite?

      expand(value.to_s)
    end
    private_class_method :float_text

    # BigDecimal goes through its own decimal string (BigDecimal#to_s("F"))
    # so it is exact and needs no require of the bigdecimal library; any other
    # Numeric goes through Float.
    def decimal_text(value)
      if value.class.name == "BigDecimal"
        return float_text(value.to_f) if value.nan? || value.infinite?

        return expand(value.to_s("F"))
      end
      float_text(Float(value))
    end
    private_class_method :decimal_text

    # Rewrites "1.0e-05", "-2.5E+3", "0.1e-4", "123.456", "1e22" as plain
    # decimal text with no exponent and no needless trailing zeros.
    def expand(text)
      m = FLOAT_PARTS.match(text) or raise Error::ArgumentError, "cannot format #{text.inspect} as a decimal"
      sign, int, frac, exp = m.captures
      digits = int + (frac || "")
      point = int.length + exp.to_i # digits[0, point] is the integer part
      if point <= 0
        int_part = "0"
        frac_part = ("0" * -point) + digits
      elsif point >= digits.length
        int_part = digits + ("0" * (point - digits.length))
        frac_part = ""
      else
        int_part = digits[0, point]
        frac_part = digits[point..]
      end
      int_part = int_part.sub(/\A0+(?=\d)/, "")
      frac_part = frac_part.sub(/0+\z/, "")
      out = frac_part.empty? ? int_part : "#{int_part}.#{frac_part}"
      sign == "-" && out != "0" ? "-#{out}" : out
    end
    private_class_method :expand
  end
end
