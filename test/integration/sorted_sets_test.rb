# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class SortedSetsIntegrationTest < HotKVIntegrationTest
  def seed(key)
    @client.zadd(key, 1, "a", 2, "b", 3, "c", 4, "d")
  end

  def test_zadd_basic_and_hash_form
    k = track(uniq("zset"))
    assert_equal 4, seed(k)
    k2 = track(uniq("zset"))
    assert_equal 2, @client.zadd(k2, { "x" => 1, "y" => 2 })
    assert_equal [["x", 1.0], ["y", 2.0]], @client.zrange(k2, 0, -1, with_scores: true)
  end

  def test_zadd_nx_xx_gt_lt_ch
    k = track(uniq("zset"))
    seed(k)
    assert_equal 0, @client.zadd(k, 99, "a", nx: true) # exists, NX blocks
    assert_equal 1.0, @client.zscore(k, "a")
    assert_equal 0, @client.zadd(k, 5, "e", xx: true) # missing, XX blocks
    assert_nil @client.zscore(k, "e")
    assert_equal 0, @client.zadd(k, 0, "a", gt: true) # lower score, GT blocks
    assert_equal 1.0, @client.zscore(k, "a")
    assert_equal 1, @client.zadd(k, 10, "a", gt: true, ch: true)
    assert_equal 10.0, @client.zscore(k, "a")
  end

  def test_zadd_incr
    k = track(uniq("zset"))
    seed(k)
    assert_in_delta 3.5, @client.zadd(k, 2.5, "a", incr: true), 0.0001
  end

  def test_zrem_zscore_zmscore_zcard_zcount
    k = track(uniq("zset"))
    seed(k)
    assert_equal 1, @client.zrem(k, "a")
    assert_nil @client.zscore(k, "a")
    assert_equal [2.0, 3.0, nil], @client.zmscore(k, "b", "c", "nope")
    assert_equal 3, @client.zcard(k)
    assert_equal 2, @client.zcount(k, 2, 3)
  end

  def test_zincrby
    k = track(uniq("zset"))
    seed(k)
    assert_in_delta 3.5, @client.zincrby(k, 1.5, "b"), 0.0001
  end

  def test_zrange_plain_rev_byscore_bylex_limit
    k = track(uniq("zset"))
    seed(k)
    assert_equal %w[a b c d], @client.zrange(k, 0, -1)
    assert_equal %w[d c b a], @client.zrange(k, 0, -1, rev: true)
    assert_equal %w[b c], @client.zrange(k, "2", "3", byscore: true)
    assert_equal %w[c b], @client.zrange(k, "3", "2", byscore: true, rev: true)
    assert_equal %w[b c], @client.zrange(k, "-inf", "+inf", byscore: true, limit: [1, 2])

    klex = track(uniq("zset"))
    @client.zadd(klex, 0, "a", 0, "b", 0, "c", 0, "d")
    assert_equal %w[b c], @client.zrange(klex, "[b", "[c", bylex: true)
  end

  def test_zrange_withscores_pairs_are_floats
    k = track(uniq("zset"))
    seed(k)
    assert_equal [%w[a], [1.0]].transpose, @client.zrange(k, 0, 0, with_scores: true)
  end

  def test_zrangestore_by_rank
    k, dest = track(uniq("zset"), uniq("zset"))
    seed(k)
    assert_equal 2, @client.zrangestore(dest, k, 1, 2)
    assert_equal %w[b c], @client.zrange(dest, 0, -1)
  end

  def test_zrangestore_byscore
    k, dest = track(uniq("zset"), uniq("zset"))
    seed(k)
    stored = @client.zrangestore(dest, k, "2", "3", byscore: true)
    assert_equal 2, stored
    assert_equal %w[b c], @client.zrange(dest, 0, -1)
  end

  def test_zrangestore_bylex
    klex, dest = track(uniq("zsetlex"), uniq("zset"))
    @client.zadd(klex, 0, "a", 0, "b", 0, "c")
    stored = @client.zrangestore(dest, klex, "-", "+", bylex: true)
    assert_equal 3, stored
    assert_equal %w[a b c], @client.zrange(dest, 0, -1)
  end

  def test_legacy_range_variants
    k = track(uniq("zset"))
    seed(k)
    assert_equal %w[d c b a], @client.zrevrange(k, 0, -1)
    assert_equal %w[b c], @client.zrangebyscore(k, 2, 3)
    assert_equal %w[c b], @client.zrevrangebyscore(k, 3, 2)

    klex = track(uniq("zset"))
    @client.zadd(klex, 0, "a", 0, "b", 0, "c")
    assert_equal %w[a b c], @client.zrangebylex(klex, "-", "+")
    assert_equal %w[c b a], @client.zrevrangebylex(klex, "+", "-")
    assert_equal 3, @client.zlexcount(klex, "-", "+")
  end

  def test_zrank_zrevrank_with_and_without_score
    k = track(uniq("zset"))
    seed(k)
    assert_equal 0, @client.zrank(k, "a")
    assert_equal [0, 1.0], @client.zrank(k, "a", with_score: true)
    assert_equal 3, @client.zrevrank(k, "a")
    assert_equal [3, 1.0], @client.zrevrank(k, "a", with_score: true)
    assert_nil @client.zrank(k, "nope")
    assert_nil @client.zrank(k, "nope", with_score: true)
  end

  def test_zpopmin_zpopmax_with_and_without_count
    k = track(uniq("zset"))
    seed(k)
    assert_equal ["a", 1.0], @client.zpopmin(k)
    assert_equal ["d", 4.0], @client.zpopmax(k)
    assert_equal [["b", 2.0], ["c", 3.0]], @client.zpopmin(k, 5)
    empty = track(uniq("zset"))
    assert_nil @client.zpopmin(empty)
    assert_equal [], @client.zpopmin(empty, 5)
  end

  def test_zrandmember
    k = track(uniq("zset"))
    seed(k)
    assert_includes %w[a b c d], @client.zrandmember(k)
    withscores = @client.zrandmember(k, 2, withscores: true)
    assert_equal 2, withscores.length
    assert_kind_of Float, withscores.first[1]
  end

  def test_zremrangebyrank_byscore_bylex
    k = track(uniq("zset"))
    seed(k)
    assert_equal 1, @client.zremrangebyrank(k, 0, 0)
    assert_equal %w[b c d], @client.zrange(k, 0, -1)
    assert_equal 1, @client.zremrangebyscore(k, 2, 2)
    assert_equal %w[c d], @client.zrange(k, 0, -1)

    klex = track(uniq("zset"))
    @client.zadd(klex, 0, "a", 0, "b", 0, "c")
    assert_equal 2, @client.zremrangebylex(klex, "[a", "[b")
  end

  def test_zunionstore_zinterstore_with_weights_and_aggregate
    k1, k2, dest = track(uniq("zset"), uniq("zset"), uniq("zset"))
    @client.zadd(k1, 1, "a", 2, "b")
    @client.zadd(k2, 10, "b", 20, "c")

    assert_equal 3, @client.zunionstore(dest, [k1, k2])
    assert_equal 12.0, @client.zscore(dest, "b") # 2 + 10

    assert_equal 3, @client.zunionstore(dest, [k1, k2], weights: [1, 2])
    assert_equal 22.0, @client.zscore(dest, "b") # 2*1 + 10*2

    assert_equal 3, @client.zunionstore(dest, [k1, k2], aggregate: "MAX")
    assert_equal 10.0, @client.zscore(dest, "b")

    assert_equal 1, @client.zinterstore(dest, [k1, k2])
    assert_equal 12.0, @client.zscore(dest, "b")
  end

  def test_zdiffstore
    k1, k2, dest = track(uniq("zset"), uniq("zset"), uniq("zset"))
    @client.zadd(k1, 1, "a", 2, "b")
    @client.zadd(k2, 1, "b")
    assert_equal 1, @client.zdiffstore(dest, [k1, k2])
    assert_equal ["a"], @client.zrange(dest, 0, -1)
  end

  def test_zunion_zinter_zdiff_non_store
    k1, k2 = track(uniq("zset"), uniq("zset"))
    @client.zadd(k1, 1, "a", 2, "b")
    @client.zadd(k2, 10, "b", 20, "c")
    assert_equal %w[a b c].sort, @client.zunion([k1, k2]).sort
    assert_equal ["b"], @client.zinter([k1, k2])
    assert_equal ["a"], @client.zdiff([k1, k2])
    scored = @client.zunion([k1, k2], with_scores: true).to_h
    assert_equal 12.0, scored["b"]
  end

  def test_zintercard
    k1, k2 = track(uniq("zset"), uniq("zset"))
    @client.zadd(k1, 1, "a", 2, "b", 3, "c")
    @client.zadd(k2, 1, "b", 2, "c")
    assert_equal 2, @client.zintercard([k1, k2])
    assert_equal 1, @client.zintercard([k1, k2], limit: 1)
  end
end
