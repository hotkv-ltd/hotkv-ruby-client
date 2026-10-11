# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

# HOTKV_TEST_URL points at a single standalone node, not a multi-node HotKV
# Cluster deployment, so these tests exercise HotKV::Cluster's fallback
# routing path (CLUSTER SLOTS comes back empty, so every command is routed
# to the configured seed) rather than real MOVED/ASK redirects. The
# CRC16/slot math itself is covered exhaustively, server free, in
# test/unit/crc16_test.rb.
class ClusterIntegrationTest < HotKVIntegrationTest
  def setup
    super # sets up @client (used here only for cleanup) and @cleanup_keys
    @cluster = HotKV::Cluster.new(urls: [ENV["HOTKV_TEST_URL"]])
  end

  def teardown
    @cluster&.close
    super
  end

  def test_typed_commands_work_through_fallback_routing
    k = track(uniq("cluster"))
    assert_equal "OK", @cluster.set(k, "1")
    assert_equal "1", @cluster.get(k)
    assert_equal 2, @cluster.incr(k)
  end

  def test_generic_command_escape_hatch
    assert_equal "PONG", @cluster.command("PING")
    assert_equal "PONG", @cluster.execute("PING")
  end

  def test_hash_tagged_keys_route_together_without_error
    tag = uniq("tag")
    k1, k2 = track("{#{tag}}:a", "{#{tag}}:b")
    assert_equal "OK", @cluster.set(k1, "1")
    assert_equal "OK", @cluster.set(k2, "2")
    assert_equal %w[1 2], @cluster.mget(k1, k2)
  end

  def test_namespace_helpers_available_on_cluster
    assert_respond_to @cluster, :tag
    assert_respond_to @cluster, :scache
    assert_respond_to @cluster, :pcache
    k = track(uniq("cluster"))
    tag = uniq("cluster-tag")
    @cluster.set(k, "v")
    @cluster.tag.set(k, tag)
    assert_equal [tag], @cluster.tag.get(k)
  end

  def test_unknown_seed_raises_argument_error
    assert_raises(HotKV::Error::ArgumentError) { HotKV::Cluster.new(urls: []) }
  end
end
