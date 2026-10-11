# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class SetsIntegrationTest < HotKVIntegrationTest
  def test_sadd_smembers_scard_srem
    k = track(uniq("set"))
    assert_equal 3, @client.sadd(k, "a", "b", "c")
    assert_equal 1, @client.sadd(k, "a", "d") # only "d" is new
    assert_equal %w[a b c d].sort, @client.smembers(k).sort
    assert_equal 4, @client.scard(k)
    assert_equal 1, @client.srem(k, "d")
  end

  def test_sismember_smismember
    k = track(uniq("set"))
    @client.sadd(k, "a", "b")
    assert_equal true, @client.sismember(k, "a")
    assert_equal false, @client.sismember(k, "z")
    assert_equal [true, false], @client.smismember(k, "a", "z")
  end

  def test_spop_srandmember
    k = track(uniq("set"))
    @client.sadd(k, "a", "b", "c")
    popped = @client.spop(k)
    assert_includes %w[a b c], popped
    assert_equal 2, @client.scard(k)
    remaining = @client.srandmember(k, 5)
    assert_equal 2, remaining.length
  end

  def test_sinter_sunion_sdiff_and_store_variants
    k1, k2, dest = track(uniq("set"), uniq("set"), uniq("set"))
    @client.sadd(k1, "a", "b", "c")
    @client.sadd(k2, "b", "c", "d")
    assert_equal %w[b c].sort, @client.sinter(k1, k2).sort
    assert_equal %w[a b c d].sort, @client.sunion(k1, k2).sort
    assert_equal ["a"], @client.sdiff(k1, k2)

    assert_equal 2, @client.sinterstore(dest, k1, k2)
    assert_equal %w[b c].sort, @client.smembers(dest).sort
    assert_equal 4, @client.sunionstore(dest, k1, k2)
    assert_equal 1, @client.sdiffstore(dest, k1, k2)
  end

  def test_sintercard
    k1, k2 = track(uniq("set"), uniq("set"))
    @client.sadd(k1, "a", "b", "c")
    @client.sadd(k2, "b", "c", "d")
    assert_equal 2, @client.sintercard([k1, k2])
    assert_equal 1, @client.sintercard([k1, k2], limit: 1)
  end

  def test_smove
    src, dst = track(uniq("set"), uniq("set"))
    @client.sadd(src, "a", "b")
    assert_equal true, @client.smove(src, dst, "a")
    assert_equal %w[b], @client.smembers(src)
    assert_equal %w[a], @client.smembers(dst)
  end
end
