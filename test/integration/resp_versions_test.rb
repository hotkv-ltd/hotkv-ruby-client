# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

# Checks that HGETALL, HRANDFIELD WITHVALUES, SMEMBERS, ZSCORE, ZRANGE
# WITHSCORES, ZPOPMIN with a count, ZRANDMEMBER WITHSCORES, XREAD, XINFO
# STREAM, CONFIG GET and INFO decode to the same shape whether the
# connection negotiated RESP3 (the default) or RESP2.
class RespVersionsIntegrationTest < HotKVIntegrationTest
  def test_resp3
    run_checks(resp3: true, label: "resp3")
  end

  def test_resp2
    run_checks(resp3: false, label: "resp2")
  end

  private

  def run_checks(resp3:, label:)
    client = HotKV::Client.new(url: ENV["HOTKV_TEST_URL"], resp3: resp3)

    hkey = uniq("conform-#{label}-hash")
    skey = uniq("conform-#{label}-set")
    zkey = uniq("conform-#{label}-zset")
    xkey = uniq("conform-#{label}-stream")

    client.hset(hkey, { "f1" => "v1", "f2" => "v2" })
    assert_equal({ "f1" => "v1", "f2" => "v2" }, client.hgetall(hkey))

    fvs = client.hrandfield(hkey, 2, withvalues: true)
    assert_equal 2, fvs.size
    fvs.each { |(f, v)| assert_equal(f == "f1" ? "v1" : "v2", v) }

    client.sadd(skey, "a", "b", "c")
    assert_equal %w[a b c], client.smembers(skey).sort

    client.zadd(zkey, 1, "a", 2, "b", 3, "c")
    assert_equal 2.0, client.zscore(zkey, "b")

    with_scores = client.zrange(zkey, 0, -1, with_scores: true)
    assert_equal [["a", 1.0], ["b", 2.0], ["c", 3.0]], with_scores

    popped = client.zpopmin(zkey, 2)
    assert_equal [["a", 1.0], ["b", 2.0]], popped

    client.zadd(zkey, 1, "a", 2, "b")
    rand_scored = client.zrandmember(zkey, 3, withscores: true)
    assert_equal 3, rand_scored.size

    id1 = client.xadd(xkey, { "field1" => "v1" })
    id2 = client.xadd(xkey, { "field2" => "v2" })
    streams = client.xread(keys: [xkey], ids: ["0"])
    assert_equal 1, streams.size
    entries = streams[xkey]
    assert_equal 2, entries.size
    assert_equal [id1, { "field1" => "v1" }], entries[0]
    assert_equal id2, entries[1][0]

    info = client.xinfo_stream(xkey)
    assert_equal 2, info["length"]
    assert_equal id2, info["last-generated-id"]

    cfg = client.config_get("maxmemory")
    assert cfg.key?("maxmemory")

    info_str = client.info
    refute info_str.start_with?("txt:"), "INFO leaked a verbatim string encoding prefix"
    refute info_str.start_with?("mkd:"), "INFO leaked a verbatim string encoding prefix"
    assert_includes info_str, "hotkv_version"
  ensure
    client&.del(hkey, skey, zkey, xkey)
    client&.close
  end
end
