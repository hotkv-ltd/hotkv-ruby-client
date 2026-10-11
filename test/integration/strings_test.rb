# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class StringsIntegrationTest < HotKVIntegrationTest
  def test_get_set_roundtrip_and_missing_key
    k = track(uniq("str"))
    assert_nil @client.get(k)
    assert_equal "OK", @client.set(k, "v1")
    assert_equal "v1", @client.get(k)
  end

  def test_set_nx_xx
    k = track(uniq("str"))
    assert_equal "OK", @client.set(k, "v1", nx: true)
    assert_nil @client.set(k, "v2", nx: true)
    assert_equal "v1", @client.get(k)
    assert_equal "OK", @client.set(k, "v3", xx: true)
    assert_equal "v3", @client.get(k)
    missing = track(uniq("str"))
    assert_nil @client.set(missing, "v", xx: true)
  end

  def test_set_get_option_returns_previous_value
    k = track(uniq("str"))
    assert_nil @client.set(k, "first", get: true)
    assert_equal "first", @client.set(k, "second", get: true)
    assert_equal "second", @client.get(k)
  end

  def test_set_ex_px_and_ttl
    k = track(uniq("str"))
    @client.set(k, "v", ex: 100)
    assert_operator @client.ttl(k), :>, 0
    @client.set(k, "v2", px: 100_000)
    assert_operator @client.pttl(k), :>, 0
  end

  def test_set_exat_pxat
    k = track(uniq("str"))
    @client.set(k, "v", exat: Time.now.to_i + 100)
    assert_operator @client.ttl(k), :>, 0
    @client.set(k, "v2", pxat: (Time.now.to_i + 100) * 1000)
    assert_operator @client.ttl(k), :>, 0
  end

  def test_set_keepttl_preserves_existing_ttl_and_plain_set_clears_it
    k = track(uniq("str"))
    @client.set(k, "v1", ex: 100)
    @client.set(k, "v2", keepttl: true)
    assert_operator @client.ttl(k), :>, 0
    @client.set(k, "v3")
    assert_equal(-1, @client.ttl(k))
  end

  def test_setnx_setex_psetex
    k = track(uniq("str"))
    assert_equal true, @client.setnx(k, "v1")
    assert_equal false, @client.setnx(k, "v2")

    k2 = track(uniq("str"))
    @client.setex(k2, 100, "v")
    assert_operator @client.ttl(k2), :>, 0

    k3 = track(uniq("str"))
    @client.psetex(k3, 100_000, "v")
    assert_operator @client.pttl(k3), :>, 0
  end

  def test_getset_getdel_getex
    k = track(uniq("str"))
    @client.set(k, "v1")
    assert_equal "v1", @client.getset(k, "v2")
    assert_equal "v2", @client.get(k)
    assert_equal "v2", @client.getdel(k)
    assert_nil @client.get(k)

    k2 = track(uniq("str"))
    @client.set(k2, "v")
    @client.getex(k2, ex: 100)
    assert_operator @client.ttl(k2), :>, 0
    @client.getex(k2, persist: true)
    assert_equal(-1, @client.ttl(k2))
  end

  def test_append_strlen
    k = track(uniq("str"))
    assert_equal 5, @client.append(k, "hello")
    assert_equal 11, @client.append(k, " world")
    assert_equal 11, @client.strlen(k)
  end

  def test_incr_decr_family
    k = track(uniq("cnt"))
    @client.set(k, "10")
    assert_equal 11, @client.incr(k)
    assert_equal 10, @client.decr(k)
    assert_equal 15, @client.incrby(k, 5)
    assert_equal 10, @client.decrby(k, 5)
    assert_in_delta 10.5, @client.incrbyfloat(k, 0.5), 0.0001
  end

  def test_mget_mset_msetnx
    k1, k2, k3 = track(uniq("m1"), uniq("m2"), uniq("m3"))
    assert_equal true, @client.mset({ k1 => "a", k2 => "b" })
    assert_equal %w[a b], @client.mget(k1, k2)
    assert_equal false, @client.msetnx({ k1 => "x", k3 => "y" })
    assert_nil @client.get(k3)
    assert_equal true, @client.msetnx({ k3 => "y" })
    assert_equal "y", @client.get(k3)
  end

  def test_getrange_setrange
    k = track(uniq("str"))
    @client.set(k, "Hello World")
    assert_equal "Hello", @client.getrange(k, 0, 4)
    @client.setrange(k, 6, "Ruby!")
    assert_equal "Hello Ruby!", @client.get(k)
  end
end
