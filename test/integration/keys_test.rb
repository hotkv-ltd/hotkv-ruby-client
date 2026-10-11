# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class KeysIntegrationTest < HotKVIntegrationTest
  def test_del_unlink_exists_touch
    k1, k2 = track(uniq("k1"), uniq("k2"))
    @client.mset({ k1 => "a", k2 => "b" })
    assert_equal 2, @client.exists(k1, k2)
    assert_equal 2, @client.touch(k1, k2)
    assert_equal 1, @client.del(k1)
    assert_equal 1, @client.unlink(k2)
    assert_equal 0, @client.exists(k1, k2)
  end

  def test_type
    k = track(uniq("k"))
    @client.set(k, "v")
    assert_equal "string", @client.type(k)
  end

  def test_expire_family_with_flags
    k = track(uniq("k"))
    @client.set(k, "v")
    assert_equal true, @client.expire(k, 100)
    assert_equal false, @client.expire(k, 200, nx: true) # already has a ttl
    assert_equal true, @client.expire(k, 200, xx: true)
    assert_equal true, @client.expire(k, 300, gt: true)
    assert_equal false, @client.expire(k, 50, gt: true)
    assert_equal true, @client.expire(k, 50, lt: true)
    assert_operator @client.ttl(k), :>, 0
  end

  def test_pexpire_expireat_pexpireat
    k = track(uniq("k"))
    @client.set(k, "v")
    assert_equal true, @client.pexpire(k, 100_000)
    assert_operator @client.pttl(k), :>, 0
    assert_equal true, @client.expireat(k, Time.now.to_i + 100)
    assert_operator @client.ttl(k), :>, 0
    assert_equal true, @client.pexpireat(k, (Time.now.to_i + 100) * 1000)
    assert_operator @client.pttl(k), :>, 0
  end

  def test_ttl_pttl_missing_and_no_expiry
    missing = track(uniq("k"))
    assert_equal(-2, @client.ttl(missing))
    k = track(uniq("k"))
    @client.set(k, "v")
    assert_equal(-1, @client.ttl(k))
  end

  def test_expiretime_pexpiretime
    k = track(uniq("k"))
    @client.set(k, "v", ex: 1000)
    assert_operator @client.expiretime(k), :>, Time.now.to_i
    assert_operator @client.pexpiretime(k), :>, Time.now.to_i * 1000
  end

  def test_persist
    k = track(uniq("k"))
    @client.set(k, "v", ex: 100)
    assert_equal true, @client.persist(k)
    assert_equal(-1, @client.ttl(k))
  end

  def test_rename_renamenx
    k1, k2, k3 = track(uniq("k1"), uniq("k2"), uniq("k3"))
    @client.set(k1, "v1")
    @client.set(k3, "v3")
    assert_equal true, @client.rename(k1, k2)
    assert_equal "v1", @client.get(k2)
    assert_equal false, @client.renamenx(k3, k2)
    k4 = track(uniq("k4"))
    assert_equal true, @client.renamenx(k3, k4)
  end

  def test_keys_and_randomkey
    prefix = uniq("glob")
    k1, k2 = track("#{prefix}:1", "#{prefix}:2")
    @client.mset({ k1 => "a", k2 => "b" })
    assert_equal [k1, k2].sort, @client.keys("#{prefix}:*").sort
    refute_nil @client.randomkey
  end

  def test_dump_restore
    k = track(uniq("k"))
    dest = track(uniq("k"))
    @client.set(k, "hello")
    dump = @client.dump(k)
    refute_nil dump
    assert_equal true, @client.restore(dest, 0, dump)
    assert_equal "hello", @client.get(dest)
  end

  def test_copy
    k = track(uniq("k"))
    dest = track(uniq("k"))
    @client.set(k, "v")
    assert_equal true, @client.copy(k, dest)
    assert_equal "v", @client.get(dest)
    assert_equal false, @client.copy(k, dest)
    assert_equal true, @client.copy(k, dest, replace: true)
  end

  def test_object_encoding
    k = track(uniq("k"))
    @client.set(k, "v")
    refute_nil @client.object_encoding(k)
  end
end
