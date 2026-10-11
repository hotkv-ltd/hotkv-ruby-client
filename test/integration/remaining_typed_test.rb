# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

# Live checks for typed methods the family tests above do not reach:
# database-wide commands run only inside a scratch database (13/14/15),
# never the default database a server may be using.
class RemainingTypedIntegrationTest < HotKVIntegrationTest
  def scratch(db)
    HotKV::Client.new(url: ENV["HOTKV_TEST_URL"], db: db, pool_size: 1, **client_options)
  end

  def test_lpush_blmove_brpop_bitfield_ro
    src, dst, bits = track(uniq("lp"), uniq("lp"), uniq("bits"))
    assert_equal 3, @client.lpush(src, %w[a b c])
    assert_equal %w[c b a], @client.lrange(src, 0, -1)
    assert_equal "a", @client.blmove(src, dst, "RIGHT", "LEFT", timeout: 1)
    assert_equal [src, "b"], @client.brpop(src, timeout: 1)
    assert_equal [src, "c"], @client.brpop(src, timeout: 1)
    assert_nil @client.brpop(src, timeout: 0.05)
    @client.bitfield(bits, "SET", "u8", 0, 200)
    assert_equal [200], @client.bitfield_ro(bits, "GET", "u8", 0)
  end

  def test_object_introspection_lastsave_client_list
    k = track(uniq("obj"))
    @client.set(k, "v")
    assert_kind_of Integer, @client.object_refcount(k)
    assert_kind_of Integer, @client.object_idletime(k)
    begin
      assert_kind_of Integer, @client.object_freq(k)
    rescue HotKV::Error::ServerError => e
      assert_match(/LFU|frequency|maxmemory-policy/i, e.message) # FREQ needs an LFU eviction policy
    end
    assert_kind_of Integer, @client.lastsave
    assert_includes @client.client_list, "id="
    assert_equal true, @client.config_resetstat
  end

  def test_hpexpiretime_and_move
    k = track(uniq("hpexp"))
    @client.hset(k, { "f" => "1" })
    @client.hpexpire(k, 100_000, "f")
    stamp = @client.hpexpiretime(k, "f").first
    assert_in_delta (Time.now.to_f * 1000) + 100_000, stamp, 10_000

    other = scratch(13)
    m = uniq("move")
    @client.set(m, "x")
    track(m)
    assert_equal true, @client.move(m, 13)
    assert_nil @client.get(m)
    assert_equal "x", other.get(m)
    other.del(m)
  ensure
    other&.close
  end

  def test_flushdb_and_swapdb_in_scratch_databases
    a = scratch(14)
    b = scratch(15)
    a.flushdb
    b.flushdb
    a.set("only-in-a", "1")
    b.set("only-in-b", "2")
    assert_equal true, a.swapdb(14, 15)
    assert_equal "1", b.get("only-in-a")
    assert_equal "2", a.get("only-in-b")
    assert_equal true, a.flushdb(async: true)
    assert_equal 0, a.dbsize
    assert_equal 1, b.dbsize
  ensure
    a&.flushdb
    b&.flushdb
    a&.close
    b&.close
  end

  def test_licensed_list_methods
    skip_unless_licensed do
      budget = "rbbud#{Process.pid}#{rand(100_000)}"
      limiter = "rbrl#{Process.pid}#{rand(100_000)}"
      prompt = "rbprompt#{Process.pid}#{rand(100_000)}"
      begin
        assert_equal true, @client.llmbudget.set(budget, 1000, 1.0e-05, 60)
        assert_includes @client.llmbudget.list, budget
        assert_equal true, @client.ratelimit.create(limiter, 10, 1000)
        assert_includes @client.ratelimit.list, limiter
        @client.prompt.put(prompt, "v1 content")
        latest = @client.prompt.latest(prompt)
        assert_equal "v1 content", latest[:content]
        assert_nil @client.prompt.latest("rbnoprompt#{prompt}")
      ensure
        @client.llmbudget.drop(budget)
        @client.ratelimit.drop(limiter)
        @client.prompt.drop(prompt)
      end
    end
  end

  def test_encryption_verify_reports_a_missing_file
    skip_unless_licensed do
      begin
        assert_equal false, @client.encryption.verify("/nonexistent/rb-#{Process.pid}")
      rescue HotKV::Error::ServerError => e
        assert_match(/file|open|exist|read/i, e.message)
      end
    end
  end
end
