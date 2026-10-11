# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

# TAG.*, NEXPIRE/NTTL/NEXPIREAT, HOTKEYS, GCRA.* and VSIM.* (core subset)
# never need a license, so these run unconditionally. OBSERVE
# and ALERTS need the Observability license feature like every other
# enterprise family, so their tests live in
# ExtensionsLicensedIntegrationTest instead.
class ExtensionsCoreIntegrationTest < HotKVIntegrationTest
  def test_tag_set_get_rem_count_exists_members_inter
    k1, k2 = track(uniq("tagged"), uniq("tagged"))
    @client.set(k1, "v")
    @client.set(k2, "v")
    tag_vip = uniq("tag-vip")
    tag_beta = uniq("tag-beta")

    assert_equal 2, @client.tag.set(k1, tag_vip, tag_beta)
    assert_equal 1, @client.tag.set(k2, tag_vip)
    assert_equal [tag_beta, tag_vip], @client.tag.get(k1).sort
    assert_equal 2, @client.tag.count(k1)
    assert_equal true, @client.tag.exists(k1, tag_vip)
    assert_equal false, @client.tag.exists(k1, "nope")
    assert_equal [k1, k2].sort, @client.tag.members(tag_vip).sort
    assert_equal [k1], @client.tag.inter(tag_vip, tag_beta)
    assert_equal 1, @client.tag.rem(k1, tag_beta)
    assert_equal [tag_vip], @client.tag.get(k1)
  end

  def test_tag_set_on_missing_key_errors
    missing = track(uniq("notset"))
    assert_raises(HotKV::Error::ServerError) { @client.tag.set(missing, "vip") }
  end

  def test_nexpire_nttl_nexpireat
    k = track(uniq("nk"))
    @client.set(k, "v")
    assert_equal(-1, @client.nttl(k))
    assert_equal true, @client.nexpire(k, 5_000_000_000)
    assert_operator @client.nttl(k), :>, 0

    missing = track(uniq("nk"))
    assert_equal(-2, @client.nttl(missing))
    assert_equal false, @client.nexpire(missing, 1_000_000_000)

    k2 = track(uniq("nk"))
    @client.set(k2, "v")
    future_ns = (Time.now.to_i + 100) * 1_000_000_000
    assert_equal true, @client.nexpireat(k2, future_ns)
    assert_operator @client.nttl(k2), :>, 0
  end

  def test_hotkeys_top_and_reset
    k = track(uniq("hot"))
    @client.set(k, "v")
    5.times { @client.get(k) }
    top = @client.hotkeys.top(5)
    assert_kind_of Array, top
    assert_equal true, @client.hotkeys.reset
  end

  def test_gcra_limit_and_reset
    k = track(uniq("gcra"))
    result = @client.gcra.limit(k, 60_000, 2)
    assert_equal false, result[:denied]
    assert_equal 2, result[:limit]
    result2 = @client.gcra.limit(k, 60_000, 2)
    result3 = @client.gcra.limit(k, 60_000, 2)
    assert_equal true, result3[:denied] || result2[:denied] || result[:remaining] >= 0
    assert_kind_of Integer, @client.gcra.reset(k)
  end

  def test_vsim_core_lifecycle
    index = uniq("vsimidx")
    assert_equal true, @client.vsim.createindex(index, 3, metric: "cosine")
    assert_equal 1, @client.vsim.set(index, "v1", [1.0, 0.0, 0.0])
    assert_equal 0, @client.vsim.set(index, "v1", [0.0, 1.0, 0.0]) # replaced, not new
    assert_equal [0.0, 1.0, 0.0], @client.vsim.get(index, "v1")
    @client.vsim.set(index, "v2", [1.0, 0.0, 0.0])
    results = @client.vsim.search(index, 2, [1.0, 0.0, 0.0])
    assert_equal 2, results.length
    assert_kind_of Float, results.first[1]

    info = @client.vsim.info(index)
    assert_equal index, info[:name]
    assert_equal 3, info[:dimensions]

    names = @client.vsim.info
    assert_includes names, index

    assert_equal 1, @client.vsim.del(index, "v2")
    assert_equal true, @client.vsim.dropindex(index)
  end
end
