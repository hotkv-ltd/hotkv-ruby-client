# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class URLTest < HotKVUnitTest
  def test_plain_hotkv_scheme
    opts = HotKV::URL.parse("hotkv://localhost:6379")
    assert_equal "localhost", opts[:host]
    assert_equal 6379, opts[:port]
    assert_equal false, opts[:ssl]
  end

  def test_port_defaults_to_the_server_default_when_omitted
    assert_equal 6379, HotKV::URL.parse("hotkv://localhost")[:port]
    assert_equal 6379, HotKV::URL.parse("hotkvs://example.com")[:port]
  end

  def test_tls_scheme
    opts = HotKV::URL.parse("hotkvs://localhost:6379")
    assert_equal true, opts[:ssl]
  end

  def test_redis_scheme_accepted_for_drop_in_migration
    opts = HotKV::URL.parse("redis://localhost:6379")
    assert_equal "localhost", opts[:host]
    assert_equal 6379, opts[:port]
    assert_equal false, opts[:ssl]

    opts = HotKV::URL.parse("rediss://localhost:6379")
    assert_equal true, opts[:ssl]
  end

  def test_default_host_when_omitted
    opts = HotKV::URL.parse("hotkv://:6379")
    assert_equal "127.0.0.1", opts[:host]
  end

  def test_username_and_password
    opts = HotKV::URL.parse("hotkv://alice:s3cret@localhost:6379")
    assert_equal "alice", opts[:username]
    assert_equal "s3cret", opts[:password]
  end

  def test_password_only_userinfo
    opts = HotKV::URL.parse("hotkv://:s3cret@localhost:6379")
    assert_nil opts[:username]
    assert_equal "s3cret", opts[:password]
  end

  def test_username_only_userinfo_has_no_password
    opts = HotKV::URL.parse("hotkv://alice@localhost:6379")
    assert_equal "alice", opts[:username]
    assert_nil opts[:password]
  end

  def test_percent_encoded_userinfo_is_decoded
    opts = HotKV::URL.parse("hotkv://al%40ice:p%40ss@localhost:6379")
    assert_equal "al@ice", opts[:username]
    assert_equal "p@ss", opts[:password]
  end

  def test_db_index_from_path
    opts = HotKV::URL.parse("hotkv://localhost:6379/3")
    assert_equal 3, opts[:db]
  end

  def test_no_db_when_path_empty
    opts = HotKV::URL.parse("hotkv://localhost:6379")
    refute opts.key?(:db)
  end

  def test_unix_socket_scheme
    opts = HotKV::URL.parse("hotkv+unix:///tmp/hotkv.sock")
    assert_equal "/tmp/hotkv.sock", opts[:path]
    refute opts.key?(:host)
  end

  def test_query_options
    opts = HotKV::URL.parse("hotkv://localhost:6379?client_name=svc1&connect_timeout=2.5&db=7")
    assert_equal "svc1", opts[:client_name]
    assert_in_delta 2.5, opts[:connect_timeout], 0.0001
    assert_equal 7, opts[:db] # query db overrides (there was no path db here)
  end

  def test_insecure_skip_verify_query_flag
    opts = HotKV::URL.parse("hotkvs://localhost:6379?insecure_skip_verify=true")
    assert_equal true, opts[:insecure_skip_verify]
  end

  def test_rejects_unsupported_scheme
    assert_raises(HotKV::Error::ArgumentError) { HotKV::URL.parse("http://localhost:6379") }
  end

  def test_rejects_non_string
    assert_raises(HotKV::Error::ArgumentError) { HotKV::URL.parse(nil) }
  end

  def test_client_new_merges_url_and_explicit_options_with_explicit_winning
    client = HotKV::Client.new(url: "hotkv://alice:pw1@localhost:6379", password: "pw2")
    options = client.instance_variable_get(:@options)
    assert_equal "alice", options[:username]
    assert_equal "pw2", options[:password]
  ensure
    client&.close
  end
end
