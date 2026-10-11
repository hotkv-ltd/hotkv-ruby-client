# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"
require "stringio"

class RESPTest < HotKVUnitTest
  def io_for(bytes)
    StringIO.new(bytes.b)
  end

  # -- encoding --

  def test_encode_command_basic
    assert_equal "*2\r\n$3\r\nGET\r\n$1\r\nk\r\n", HotKV::RESP.encode_command(["GET", "k"])
  end

  def test_encode_command_coerces_non_strings
    encoded = HotKV::RESP.encode_command(["SET", :k, 42, 3.5, nil])
    assert_equal "*5\r\n$3\r\nSET\r\n$1\r\nk\r\n$2\r\n42\r\n$3\r\n3.5\r\n$0\r\n\r\n", encoded
  end

  def test_encode_command_is_binary_safe
    binary = (0..255).map(&:chr).join.b
    encoded = HotKV::RESP.encode_command(["SET", "k", binary])
    value = HotKV::RESP.read_reply(io_for(encoded.sub(/\A\*3\r\n\$3\r\nSET\r\n\$1\r\nk\r\n/, "")))
    assert_equal binary, value
  end

  # -- simple string, error, integer --

  def test_empty_line_is_a_protocol_error_not_a_crash
    assert_raises(HotKV::Error::ProtocolError) { HotKV::RESP.read_reply(io_for("\r\n")) }
  end

  def test_simple_string
    assert_equal "OK", HotKV::RESP.read_reply(io_for("+OK\r\n"))
  end

  def test_error_raises_by_default
    err = assert_raises(HotKV::Error::WrongTypeError) do
      HotKV::RESP.read_reply(io_for("-WRONGTYPE Operation against a key holding the wrong kind of value\r\n"))
    end
    assert_equal "WRONGTYPE", err.code
  end

  def test_error_returned_inline_when_raise_on_error_false
    value = HotKV::RESP.read_reply(io_for("-ERR boom\r\n"), raise_on_error: false)
    assert_instance_of HotKV::Error::CommandError, value
    assert_equal "ERR", value.code
  end

  def test_error_nested_in_array_is_never_raised
    bytes = "*2\r\n+OK\r\n-ERR nope\r\n"
    value = HotKV::RESP.read_reply(io_for(bytes))
    assert_equal "OK", value[0]
    assert_instance_of HotKV::Error::CommandError, value[1]
  end

  def test_integer
    assert_equal 12_345, HotKV::RESP.read_reply(io_for(":12345\r\n"))
    assert_equal(-1, HotKV::RESP.read_reply(io_for(":-1\r\n")))
  end

  # -- bulk string, array --

  def test_bulk_string
    assert_equal "hello", HotKV::RESP.read_reply(io_for("$5\r\nhello\r\n"))
  end

  def test_bulk_string_nil
    assert_nil HotKV::RESP.read_reply(io_for("$-1\r\n"))
  end

  def test_bulk_string_empty
    assert_equal "", HotKV::RESP.read_reply(io_for("$0\r\n\r\n"))
  end

  def test_array
    assert_equal %w[a b c], HotKV::RESP.read_reply(io_for("*3\r\n$1\r\na\r\n$1\r\nb\r\n$1\r\nc\r\n"))
  end

  def test_array_nil
    assert_nil HotKV::RESP.read_reply(io_for("*-1\r\n"))
  end

  def test_array_nested
    bytes = "*2\r\n*2\r\n$1\r\na\r\n:1\r\n*2\r\n$1\r\nb\r\n:2\r\n"
    assert_equal [["a", 1], ["b", 2]], HotKV::RESP.read_reply(io_for(bytes))
  end

  # -- RESP3 types --

  def test_null
    assert_nil HotKV::RESP.read_reply(io_for("_\r\n"))
  end

  def test_boolean
    assert_equal true, HotKV::RESP.read_reply(io_for("#t\r\n"))
    assert_equal false, HotKV::RESP.read_reply(io_for("#f\r\n"))
  end

  def test_double
    assert_in_delta 3.14, HotKV::RESP.read_reply(io_for(",3.14\r\n")), 0.0001
    assert_equal Float::INFINITY, HotKV::RESP.read_reply(io_for(",inf\r\n"))
    assert_equal(-Float::INFINITY, HotKV::RESP.read_reply(io_for(",-inf\r\n")))
    assert HotKV::RESP.read_reply(io_for(",nan\r\n")).nan?
  end

  def test_big_number
    assert_equal 1234, HotKV::RESP.read_reply(io_for("(1234\r\n"))
    huge = "123456789012345678901234567890"
    assert_equal huge.to_i, HotKV::RESP.read_reply(io_for("(#{huge}\r\n"))
    assert_equal(-42, HotKV::RESP.read_reply(io_for("(-42\r\n")))
  end

  def test_blob_error
    message = "NOLICENSE feature not enabled"
    err = assert_raises(HotKV::Error::NotLicensedError) do
      HotKV::RESP.read_reply(io_for("!#{message.bytesize}\r\n#{message}\r\n"))
    end
    assert_equal "NOLICENSE", err.code
  end

  def test_verbatim_string
    value = HotKV::RESP.read_reply(io_for("=9\r\ntxt:hello\r\n"))
    assert_equal "hello", value
    assert_instance_of HotKV::VerbatimString, value
    assert_equal "txt", value.format
  end

  def test_map_decodes_to_hash
    bytes = "%2\r\n$1\r\na\r\n:1\r\n$1\r\nb\r\n:2\r\n"
    assert_equal({ "a" => 1, "b" => 2 }, HotKV::RESP.read_reply(io_for(bytes)))
  end

  def test_set_decodes_to_array
    bytes = "~2\r\n$1\r\nx\r\n$1\r\ny\r\n"
    assert_equal %w[x y], HotKV::RESP.read_reply(io_for(bytes))
  end

  def test_push_decodes_to_array
    bytes = ">3\r\n$7\r\nmessage\r\n$2\r\nch\r\n$5\r\nhello\r\n"
    assert_equal %w[message ch hello], HotKV::RESP.read_reply(io_for(bytes))
  end

  def test_attribute_is_skipped_transparently
    # |1\r\n key/value pair \r\n then the real reply, an integer.
    bytes = "|1\r\n$8\r\nkeyspace\r\n$2\r\nhi\r\n:42\r\n"
    assert_equal 42, HotKV::RESP.read_reply(io_for(bytes))
  end

  # -- error handling for malformed input --

  def test_unknown_type_byte_raises_protocol_error
    assert_raises(HotKV::Error::ProtocolError) { HotKV::RESP.read_reply(io_for("^oops\r\n")) }
  end

  def test_truncated_reply_raises_connection_error
    assert_raises(HotKV::Error::ConnectionError) { HotKV::RESP.read_reply(io_for("$5\r\nhel")) }
  end

  def test_empty_stream_raises_connection_error
    assert_raises(HotKV::Error::ConnectionError) { HotKV::RESP.read_reply(io_for("")) }
  end

  # -- streaming / partial delivery over a real pipe --

  def test_read_reply_assembles_correctly_across_slow_partial_writes
    reader, writer = IO.pipe
    payload = "hello world " * 2000
    reply_bytes = "$#{payload.bytesize}\r\n#{payload}\r\n".b

    writer_thread = Thread.new do
      reply_bytes.each_byte.each_slice(97) do |chunk|
        writer.write(chunk.pack("C*"))
        sleep 0.001
      end
      writer.close
    end

    value = HotKV::RESP.read_reply(reader)
    writer_thread.join
    assert_equal payload, value
  ensure
    reader.close
  end
end
