# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class ErrorsTest < HotKVUnitTest
  def test_known_prefixes_map_to_typed_subclasses
    {
      "WRONGTYPE Operation against a key holding the wrong kind of value" => HotKV::Error::WrongTypeError,
      "NOAUTH Authentication required." => HotKV::Error::NoAuthError,
      "WRONGPASS invalid username-password pair" => HotKV::Error::WrongPassError,
      "NOLICENSE enterprise feature 'prompt-cache' requires a valid license" => HotKV::Error::NotLicensedError,
      "READONLY You can't write against a read only replica." => HotKV::Error::ReadOnlyError,
      "EXECABORT Transaction discarded because of a previous error." => HotKV::Error::ExecAbortError,
      "NOSCRIPT No matching script." => HotKV::Error::NoScriptError,
      "CLUSTERDOWN The cluster is down." => HotKV::Error::ClusterDownError,
      "TRYAGAIN try again" => HotKV::Error::TryAgainError,
      "CROSSSLOT Keys don't hash to the same slot" => HotKV::Error::CrossSlotError,
      "ERR wrong number of arguments for 'set' command" => HotKV::Error::CommandError,
      "SOMETHINGUNKNOWN never seen before" => HotKV::Error::CommandError
    }.each do |message, klass|
      err = HotKV::Error::ServerError.from_message(message)
      assert_instance_of klass, err, "expected #{message.inspect} to map to #{klass}"
      assert_kind_of HotKV::Error::ServerError, err
      assert_kind_of HotKV::Error::Base, err
    end
  end

  def test_moved_error_parses_slot_host_port
    err = HotKV::Error::ServerError.from_message("MOVED 3999 127.0.0.1:6401")
    assert_instance_of HotKV::Error::MovedError, err
    assert_kind_of HotKV::Error::ClusterRedirectError, err
    assert_equal 3999, err.slot
    assert_equal "127.0.0.1", err.host
    assert_equal 6401, err.port
  end

  def test_ask_error_parses_slot_host_port
    err = HotKV::Error::ServerError.from_message("ASK 3999 127.0.0.1:6401")
    assert_instance_of HotKV::Error::AskError, err
    assert_equal 3999, err.slot
    assert_equal "127.0.0.1", err.host
    assert_equal 6401, err.port
  end

  def test_not_licensed_error_is_distinct_from_other_server_errors
    not_licensed = HotKV::Error::ServerError.from_message("NOLICENSE enterprise feature 'llm-stats' requires a valid license")
    generic = HotKV::Error::ServerError.from_message("ERR wrong number of arguments")
    assert_kind_of HotKV::Error::NotLicensedError, not_licensed
    refute_kind_of HotKV::Error::NotLicensedError, generic
  end

  def test_server_error_message_is_the_full_server_text
    err = HotKV::Error::ServerError.from_message("ERR custom message here")
    assert_equal "ERR custom message here", err.message
    assert_equal "ERR custom message here", err.server_message
    assert_equal "ERR", err.code
  end
end
