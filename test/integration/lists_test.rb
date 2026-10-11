# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class ListsIntegrationTest < HotKVIntegrationTest
  def test_push_pop_len_range
    k = track(uniq("list"))
    assert_equal 3, @client.rpush(k, "a", "b", "c")
    assert_equal 3, @client.llen(k)
    assert_equal %w[a b c], @client.lrange(k, 0, -1)
    assert_equal "a", @client.lpop(k)
    assert_equal "c", @client.rpop(k)
    assert_equal ["b"], @client.lrange(k, 0, -1)
  end

  def test_lpop_rpop_with_count
    k = track(uniq("list"))
    @client.rpush(k, "a", "b", "c", "d")
    assert_equal %w[a b], @client.lpop(k, 2)
    assert_equal %w[d c], @client.rpop(k, 2)
    missing = track(uniq("list"))
    assert_nil @client.lpop(missing, 2)
  end

  def test_lpushx_rpushx_on_missing_key
    k = track(uniq("list"))
    assert_equal 0, @client.lpushx(k, "a")
    assert_equal 0, @client.rpushx(k, "a")
    assert_equal false, @client.exists(k) == 1
  end

  def test_lindex_lset_linsert_lrem_ltrim
    k = track(uniq("list"))
    @client.rpush(k, "a", "b", "c")
    assert_equal "b", @client.lindex(k, 1)
    assert_equal true, @client.lset(k, 1, "B")
    assert_equal "B", @client.lindex(k, 1)
    @client.linsert(k, "BEFORE", "B", "A.5")
    assert_equal %w[a A.5 B c], @client.lrange(k, 0, -1)
    @client.rpush(k, "c")
    assert_equal 1, @client.lrem(k, 1, "c")
    @client.ltrim(k, 0, 1)
    assert_equal %w[a A.5], @client.lrange(k, 0, -1)
  end

  def test_rpoplpush_and_lmove
    src, dst = track(uniq("list"), uniq("list"))
    @client.rpush(src, "a", "b", "c")
    assert_equal "c", @client.rpoplpush(src, dst)
    assert_equal "b", @client.lmove(src, dst, "RIGHT", "LEFT")
    assert_equal %w[b c], @client.lrange(dst, 0, -1)
  end

  def test_lpos
    k = track(uniq("list"))
    @client.rpush(k, "a", "b", "c", "b")
    assert_equal 1, @client.lpos(k, "b")
    assert_equal 3, @client.lpos(k, "b", rank: 2)
  end

  def test_lmpop
    k1, k2 = track(uniq("list"), uniq("list"))
    @client.rpush(k2, "x", "y")
    result = @client.lmpop([k1, k2], "LEFT")
    assert_equal [k2, ["x"]], result
  end
end
