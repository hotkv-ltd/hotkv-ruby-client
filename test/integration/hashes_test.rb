# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class HashesIntegrationTest < HotKVIntegrationTest
  def test_hset_hget_hmget_hgetall_hdel
    k = track(uniq("hash"))
    assert_equal 2, @client.hset(k, { "f1" => "v1", "f2" => "v2" })
    assert_equal "v1", @client.hget(k, "f1")
    assert_equal %w[v1 v2], @client.hmget(k, "f1", "f2")
    assert_equal({ "f1" => "v1", "f2" => "v2" }, @client.hgetall(k))
    assert_equal 1, @client.hdel(k, "f1")
  end

  def test_hsetnx_hexists_hlen_hkeys_hvals_hstrlen
    k = track(uniq("hash"))
    assert_equal true, @client.hsetnx(k, "f1", "v1")
    assert_equal false, @client.hsetnx(k, "f1", "v2")
    assert_equal true, @client.hexists(k, "f1")
    assert_equal false, @client.hexists(k, "nope")
    assert_equal 1, @client.hlen(k)
    assert_equal ["f1"], @client.hkeys(k)
    assert_equal ["v1"], @client.hvals(k)
    assert_equal 2, @client.hstrlen(k, "f1")
  end

  def test_hincrby_hincrbyfloat
    k = track(uniq("hash"))
    @client.hset(k, { "cnt" => "10" })
    assert_equal 15, @client.hincrby(k, "cnt", 5)
    assert_in_delta 15.5, @client.hincrbyfloat(k, "cnt", 0.5), 0.0001
  end

  def test_hrandfield
    k = track(uniq("hash"))
    @client.hset(k, { "f1" => "v1", "f2" => "v2" })
    field = @client.hrandfield(k)
    assert_includes %w[f1 f2], field
    pairs = @client.hrandfield(k, 2, withvalues: true)
    assert_equal 2, pairs.length
    assert_kind_of Array, pairs.first
  end

  def test_hash_field_ttl_family
    k = track(uniq("hash"))
    @client.hset(k, { "f1" => "v1", "f2" => "v2" })
    assert_equal [1], @client.hexpire(k, 100, "f1")
    assert_operator @client.httl(k, "f1").first, :>, 0
    assert_equal [-1], @client.httl(k, "f2")
    assert_operator @client.hexpiretime(k, "f1").first, :>, Time.now.to_i
    assert_equal [1], @client.hpersist(k, "f1")
    assert_equal [-1], @client.httl(k, "f1")
  end

  def test_hpexpire_hexpireat_hpexpireat
    k = track(uniq("hash"))
    @client.hset(k, { "f1" => "v1" })
    assert_equal [1], @client.hpexpire(k, 100_000, "f1")
    assert_operator @client.hpttl(k, "f1").first, :>, 0
    assert_equal [1], @client.hexpireat(k, Time.now.to_i + 100, "f1")
    assert_equal [1], @client.hpexpireat(k, (Time.now.to_i + 100) * 1000, "f1")
  end
end
