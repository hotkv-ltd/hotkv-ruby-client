# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class StreamsIntegrationTest < HotKVIntegrationTest
  def test_xadd_xrange_xrevrange_xlen_xdel
    k = track(uniq("stream"))
    id1 = @client.xadd(k, { "f" => "v1" })
    id2 = @client.xadd(k, { "f" => "v2" })
    assert_operator id2, :>, id1
    assert_equal 2, @client.xlen(k)
    assert_equal [[id1, { "f" => "v1" }], [id2, { "f" => "v2" }]], @client.xrange(k)
    assert_equal [[id2, { "f" => "v2" }], [id1, { "f" => "v1" }]], @client.xrevrange(k)
    assert_equal [[id1, { "f" => "v1" }]], @client.xrange(k, "-", "+", count: 1)
    assert_equal 1, @client.xdel(k, id1)
    assert_equal 1, @client.xlen(k)
  end

  def test_xadd_with_explicit_id_and_nomkstream
    k = track(uniq("stream"))
    assert_nil @client.xadd(k, { "f" => "v" }, nomkstream: true)
    assert_equal 0, @client.exists(k)
    id = @client.xadd(k, { "f" => "v" }, id: "5-1")
    assert_equal "5-1", id
  end

  def test_xtrim_maxlen
    k = track(uniq("stream"))
    5.times { |i| @client.xadd(k, { "n" => i.to_s }) }
    assert_equal 5, @client.xlen(k)
    @client.xtrim(k, maxlen: 2, approx: false)
    assert_equal 2, @client.xlen(k)
  end

  def test_xread
    k = track(uniq("stream"))
    id = @client.xadd(k, { "f" => "v" })
    result = @client.xread(keys: [k], ids: ["0"])
    assert_equal [[id, { "f" => "v" }]], result[k]
    assert_nil @client.xread(keys: [k], ids: ["$"], count: 1)
  end

  def test_consumer_groups_lifecycle
    k = track(uniq("stream"))
    id1 = @client.xadd(k, { "f" => "v1" })
    @client.xadd(k, { "f" => "v2" })

    assert_equal true, @client.xgroup_create(k, "g1", "0")
    assert_equal true, @client.xgroup_createconsumer(k, "g1", "c1")

    read = @client.xreadgroup("g1", "c1", keys: [k], ids: [">"])
    assert_equal 2, read[k].length

    assert_equal 1, @client.xack(k, "g1", id1)

    summary = @client.xpending(k, "g1")
    assert_equal 1, summary[:count]

    detail = @client.xpending(k, "g1", count: 10)
    assert_equal 1, detail.length
    assert_equal "c1", detail.first[:consumer]

    claimed = @client.xclaim(k, "g1", "c2", 0, detail.first[:id])
    assert_equal 1, claimed.length

    autoclaimed = @client.xautoclaim(k, "g1", "c3", 0, "0")
    assert_kind_of String, autoclaimed[:cursor]
    assert_kind_of Array, autoclaimed[:entries]

    assert_equal true, @client.xgroup_setid(k, "g1", "0")
    assert_kind_of Integer, @client.xgroup_delconsumer(k, "g1", "c1")
    assert_equal true, @client.xgroup_destroy(k, "g1")
  end

  def test_xinfo_stream_groups_consumers
    k = track(uniq("stream"))
    @client.xadd(k, { "f" => "v" })
    @client.xgroup_create(k, "g1", "0")
    @client.xreadgroup("g1", "c1", keys: [k], ids: [">"])

    info = @client.xinfo_stream(k)
    assert_equal 1, info["length"]

    groups = @client.xinfo_groups(k)
    assert_equal 1, groups.length
    assert_equal "g1", groups.first["name"]

    consumers = @client.xinfo_consumers(k, "g1")
    assert_equal 1, consumers.length
    assert_equal "c1", consumers.first["name"]
  end
end
