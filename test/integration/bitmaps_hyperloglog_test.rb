# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class BitmapsHyperLogLogIntegrationTest < HotKVIntegrationTest
  def test_setbit_getbit_bitcount_bitpos
    k = track(uniq("bit"))
    assert_equal 0, @client.setbit(k, 7, 1)
    assert_equal 1, @client.getbit(k, 7)
    assert_equal 1, @client.bitcount(k)
    assert_equal 1, @client.bitcount(k, 0, 0)
    assert_equal 7, @client.bitpos(k, 1)
  end

  def test_bitcount_bitpos_bit_mode
    k = track(uniq("bit"))
    @client.set(k, "\xff\x00\xff".b)
    assert_equal 16, @client.bitcount(k)
    assert_equal 0, @client.bitcount(k, 8, 15, bit_mode: true)
    assert_equal 8, @client.bitcount(k, 0, 15, bit_mode: true)
    assert_equal 8, @client.bitpos(k, 0, 0, -1, bit_mode: true)
  end

  def test_bitop
    k1, k2, dest = track(uniq("bit"), uniq("bit"), uniq("bit"))
    @client.set(k1, "\xff\x00".b)
    @client.set(k2, "\x0f\xff".b)
    @client.bitop("AND", dest, k1, k2)
    assert_equal "\x0f\x00".b, @client.get(dest)
  end

  def test_bitfield
    k = track(uniq("bit"))
    result = @client.bitfield(k, "SET", "u8", 0, 255, "GET", "u8", 0)
    assert_equal [0, 255], result
    incr = @client.bitfield(k, "INCRBY", "u8", 0, 10, "OVERFLOW", "SAT", "INCRBY", "u8", 0, 10)
    assert_equal 2, incr.length
  end

  def test_pfadd_pfcount_pfmerge
    k1, k2, dest = track(uniq("hll"), uniq("hll"), uniq("hll"))
    assert_equal true, @client.pfadd(k1, "a", "b", "c")
    assert_equal true, @client.pfadd(k2, "c", "d", "e")
    assert_operator @client.pfcount(k1), :>=, 2
    assert_operator @client.pfcount(k1, k2), :>=, 4
    assert_equal true, @client.pfmerge(dest, k1, k2)
    assert_operator @client.pfcount(dest), :>=, 4
  end
end
