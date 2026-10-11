# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class ServerScriptingScanIntegrationTest < HotKVIntegrationTest
  def test_ping_echo_time
    assert_equal "PONG", @client.ping
    assert_equal "hi", @client.ping("hi")
    assert_equal "hi", @client.echo("hi")
    unix_s, _micros = @client.time
    assert_in_delta Time.now.to_i, unix_s, 5
  end

  def test_dbsize_and_config_get_set
    before = @client.dbsize
    k = track(uniq("dbsize"))
    @client.set(k, "v")
    assert_operator @client.dbsize, :>, before - 1

    cfg = @client.config_get("maxmemory")
    assert cfg.is_a?(Hash)
    assert_equal true, @client.config_set("maxmemory", cfg.values.first.to_s)
  end

  def test_client_setname_getname_id_info
    @client.client_setname("hotkv-ruby-test")
    assert_equal "hotkv-ruby-test", @client.client_getname
    assert_kind_of Integer, @client.client_id
    assert_includes @client.client_info, "id="
  end

  def test_eval_and_evalsha_with_noscript_fallback
    k = track(uniq("eval"))
    result = @client.eval_script("return redis.call('SET', KEYS[1], ARGV[1])", keys: [k], args: ["v1"])
    assert_equal "OK", result
    assert_equal "v1", @client.get(k)

    sha = @client.script_load("return ARGV[1]")
    assert_equal "hello", @client.evalsha(sha, args: ["hello"])

    # Unknown sha with a script fallback transparently EVALs instead.
    fallback_script = "return 'fallback-ok'"
    result2 = @client.evalsha("0000000000000000000000000000000000000000", script: fallback_script)
    assert_equal "fallback-ok", result2
  end

  def test_script_exists_and_flush
    sha = @client.script_load("return 1")
    assert_equal [true], @client.script_exists(sha)
    assert_equal true, @client.script_flush
    assert_equal [false], @client.script_exists(sha)
  end

  def test_scan_family_iterators
    prefix = uniq("scan")
    keys = (1..5).map { |i| "#{prefix}:#{i}" }
    track(*keys)
    keys.each { |k| @client.set(k, "v") }
    found = @client.scan_each(match: "#{prefix}:*").to_a
    assert_equal keys.sort, found.sort

    hkey = track(uniq("scanhash"))
    @client.hset(hkey, { "f1" => "v1", "f2" => "v2" })
    hfound = {}
    @client.hscan_each(hkey) { |f, v| hfound[f] = v }
    assert_equal({ "f1" => "v1", "f2" => "v2" }, hfound)

    skey = track(uniq("scanset"))
    @client.sadd(skey, "a", "b", "c")
    sfound = @client.sscan_each(skey).to_a
    assert_equal %w[a b c].sort, sfound.sort

    zkey = track(uniq("scanzset"))
    @client.zadd(zkey, 1, "a", 2, "b")
    zfound = {}
    @client.zscan_each(zkey) { |m, s| zfound[m] = s }
    assert_equal({ "a" => 1.0, "b" => 2.0 }, zfound)
  end

  def test_scan_one_shot_cursor
    k = track(uniq("scan1"))
    @client.set(k, "v")
    cursor, first_page = @client.scan("0", match: k)
    assert_kind_of String, cursor
    assert_kind_of Array, first_page

    # SCAN does not guarantee a match appears on the very first page, so
    # drive the cursor to completion by hand to prove the one shot API
    # composes into a full scan.
    all_keys = first_page.dup
    until cursor == "0"
      cursor, page = @client.scan(cursor, match: k)
      all_keys.concat(page)
    end
    assert_includes all_keys, k
  end
end
