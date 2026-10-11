# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  # A plain Ruby String subclass that remembers the three letter format tag
  # ("txt" or "mkd") a RESP3 verbatim string (`=`) reply carried. Behaves as
  # an ordinary String everywhere; only +format+ is extra.
  class VerbatimString < String
    attr_reader :format

    def initialize(content, format)
      super(content)
      @format = format
    end
  end

  # Low level RESP2/RESP3 request encoder and reply decoder. Every reply
  # type in the protocol is handled: simple string, error, integer, bulk
  # string, array, null, boolean, double, big number, blob error, verbatim
  # string, map, set, attribute and push. Operates on any object that
  # responds to #gets(separator) and #read(length) the way IO and StringIO
  # do, so it needs no live socket to be unit tested.
  module RESP
    CRLF = "\r\n".b
    private_constant :CRLF

    module_function

    # Encodes +args+ (Strings, Symbols, Integers, Floats, ...) as one RESP
    # array of bulk strings, the wire form every RESP server
    # expects a client request in, regardless of RESP2 or RESP3.
    def encode_command(args)
      out = String.new(+"*#{args.length}\r\n", encoding: Encoding::BINARY)
      args.each do |a|
        s = to_wire_string(a)
        out << "$" << s.bytesize.to_s << CRLF << s << CRLF
      end
      out
    end

    # Strings go out byte for byte. Integers use their decimal text. Every
    # other number (Float, BigDecimal, Rational) is written by Wire.float:
    # plain decimal, never an exponent such as "1.0e-05", which the server's
    # stricter numeric parsers refuse.
    def to_wire_string(arg)
      case arg
      when String then arg.b
      when Integer then arg.to_s.b
      when Numeric then Wire.float(arg).b
      else arg.to_s.b
      end
    end

    # Reads exactly one reply from +io+.
    #
    # +raise_on_error+ governs only the value this call itself returns: when
    # true (the default) a top level error reply is raised as a
    # HotKV::Error::ServerError subclass; when false it is returned as that
    # exception instance instead. Either way, an error found while decoding
    # an element nested inside an array/map/set/push is always returned
    # inline as the exception instance (never raised), so one failed command
    # inside a MULTI/EXEC or pipeline reply never discards the rest of it.
    def read_reply(io, raise_on_error: true)
      value = read_value(io)
      raise value if raise_on_error && value.is_a?(Error::ServerError)

      value
    end

    def read_value(io)
      line = read_line(io)
      type = line.getbyte(0)
      raise Error::ProtocolError, "malformed RESP reply: empty line where a type byte was expected" if type.nil?

      body = line.byteslice(1..-1)
      begin
        decode(type, body, io)
      rescue ArgumentError, RangeError => e
        raise Error::ProtocolError, "malformed RESP reply near #{line.inspect}: #{e.message}"
      end
    end

    def decode(type, body, io)
      case type
      when 43 then body                                    # '+' simple string
      when 45 then Error::ServerError.from_message(body)    # '-' error
      when 58 then Integer(body)                            # ':' integer
      when 36 then read_bulk(io, body)                      # '$' bulk string
      when 42 then read_array(io, body)                     # '*' array
      when 95 then nil                                      # '_' null
      when 35 then body == "t"                              # '#' boolean
      when 44 then read_double(body)                        # ',' double
      when 40 then Integer(body)                            # '(' big number
      when 33 then Error::ServerError.from_message(read_bulk(io, body)) # '!' blob error
      when 61 then read_verbatim(io, body)                  # '=' verbatim string
      when 37 then read_map(io, body)                       # '%' map
      when 126 then read_multi(io, body)                    # '~' set
      when 62 then read_multi(io, body)                     # '>' push
      when 124 then read_attribute(io, body)                # '|' attribute (transparent)
      else
        raise Error::ProtocolError, "unknown RESP type byte #{type.chr.inspect}"
      end
    end

    def read_line(io)
      line = io.gets(CRLF)
      raise Error::ConnectionError, "connection closed by server" if line.nil?
      raise Error::ConnectionError, "connection closed by server (truncated reply line)" unless line.chomp!(CRLF)

      line
    end

    def read_exact(io, n)
      return "".b if n.zero?

      data = io.read(n)
      raise Error::ConnectionError, "connection closed by server (expected #{n} bytes)" if data.nil? || data.bytesize != n

      data
    end

    def read_bulk(io, len_str)
      len = Integer(len_str)
      return nil if len.negative?

      data = read_exact(io, len)
      terminator = read_exact(io, 2)
      raise Error::ProtocolError, "malformed bulk string terminator" unless terminator == CRLF

      data
    end

    def read_verbatim(io, len_str)
      payload = read_bulk(io, len_str)
      return nil if payload.nil?

      VerbatimString.new(payload.byteslice(4..-1) || "".b, payload.byteslice(0, 3))
    end

    def read_double(body)
      case body
      when "inf" then Float::INFINITY
      when "-inf" then -Float::INFINITY
      when "nan" then Float::NAN
      else Float(body)
      end
    end

    def read_array(io, len_str)
      len = Integer(len_str)
      return nil if len.negative? # RESP2 null array

      Array.new(len) { read_value(io) }
    end

    def read_multi(io, len_str)
      Array.new(Integer(len_str)) { read_value(io) }
    end

    def read_map(io, len_str)
      count = Integer(len_str)
      h = {}
      count.times { h[read_value(io)] = read_value(io) }
      h
    end

    def read_attribute(io, len_str)
      count = Integer(len_str)
      count.times do
        read_value(io)
        read_value(io)
      end
      read_value(io) # the attribute precedes and annotates the value that follows it
    end
  end
end
