# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"
require_relative "support/fake_server"

# HotKV::Cluster routing and redirect handling against fake nodes, so MOVED,
# ASK, an empty redirect host, a dead seed and a redirect loop are tested
# without a real multi-node cluster.
class ClusterRedirectTest < HotKVUnitTest
  SLOTS = HotKV::Cluster::CRC16
  CRLF = "\r\n"

  def teardown
    (@servers || []).each(&:stop)
  end

  def start(&handler)
    server = FakeServer.new(&handler)
    (@servers ||= []) << server
    server
  end

  # A key whose slot is in 0..8191 (:low) or 8192..16383 (:high).
  def key_in(half)
    (0..).each do |i|
      key = "key#{i}"
      slot = SLOTS.key_slot(key)
      return key if half == :low ? slot < 8192 : slot >= 8192
    end
  end

  # One CLUSTER SLOTS range entry [from, to, [host, port, id]].
  def range_entry(from, to, port, host: "127.0.0.1")
    "*3#{CRLF}:#{from}#{CRLF}:#{to}#{CRLF}*3#{CRLF}#{FakeServer.bulk(host)}:#{port}#{CRLF}#{FakeServer.bulk("id#{port}")}"
  end

  def table(*entries)
    "*#{entries.length}#{CRLF}#{entries.join}"
  end

  def cluster_cmd?(req)
    req[0].casecmp?("CLUSTER")
  end

  def test_routes_each_key_to_the_node_owning_its_slot
    low = high = nil
    split = -> { table(range_entry(0, 8191, low.port), range_entry(8192, 16_383, high.port)) }
    low = start { |req, _| cluster_cmd?(req) ? split.call : "+LOW#{CRLF}" }
    high = start { |req, _| cluster_cmd?(req) ? split.call : "+HIGH#{CRLF}" }
    cluster = HotKV::Cluster.new(urls: ["hotkv://#{low.addr}"])
    assert_equal "LOW", cluster.get(key_in(:low))
    assert_equal "HIGH", cluster.get(key_in(:high))
    assert_equal 1, high.requests.count { |r| r[0] == "GET" }
    assert_equal 1, low.requests.count { |r| r[0] == "GET" }
    cluster.close
  end

  def test_moved_redirects_and_remembers_the_new_owner
    low = high = nil
    stale = -> { table(range_entry(0, 16_383, low.port)) } # claims every slot, which is wrong
    low = start do |req, _|
      if cluster_cmd?(req) then stale.call
      elsif req[0] == "GET" then "-MOVED #{SLOTS.key_slot(req[1])} 127.0.0.1:#{high.port}#{CRLF}"
      else "+OK#{CRLF}"
      end
    end
    high = start { |req, _| cluster_cmd?(req) ? stale.call : "+HIGH#{CRLF}" }
    cluster = HotKV::Cluster.new(urls: ["hotkv://#{low.addr}"])
    key = key_in(:high)
    assert_equal "HIGH", cluster.get(key)
    low_gets = low.requests.count { |r| r[0] == "GET" }
    assert_equal "HIGH", cluster.get(key) # goes straight to the owner now
    assert_equal low_gets, low.requests.count { |r| r[0] == "GET" }
    cluster.close
  end

  def test_moved_with_an_empty_host_means_the_answering_node
    low = nil
    high = start { |_req, _| "+HIGH#{CRLF}" }
    low = start do |req, _|
      if cluster_cmd?(req) then table(range_entry(0, 16_383, low.port))
      elsif req[0] == "GET" then "-MOVED #{SLOTS.key_slot(req[1])} :#{high.port}#{CRLF}" # no host: the same machine
      else "+OK#{CRLF}"
      end
    end
    cluster = HotKV::Cluster.new(urls: ["hotkv://#{low.addr}"])
    assert_equal "HIGH", cluster.get("anything")
    cluster.close
  end

  def test_an_empty_host_in_cluster_slots_means_the_answering_node
    node = nil
    node = start do |req, _|
      cluster_cmd?(req) ? table(range_entry(0, 16_383, node.port, host: "")) : "+HERE#{CRLF}"
    end
    cluster = HotKV::Cluster.new(urls: ["hotkv://#{node.addr}"])
    assert_equal ["127.0.0.1:#{node.port}"], cluster.known_nodes
    assert_equal "HERE", cluster.get("k")
    cluster.close
  end

  def test_ask_sends_asking_then_the_command_to_the_target_once
    target = start { |req, _| req[0].casecmp?("ASKING") ? "+OK#{CRLF}" : "+MIGRATED#{CRLF}" }
    source = nil
    source = start do |req, _|
      if cluster_cmd?(req) then table(range_entry(0, 16_383, source.port))
      elsif req[0] == "GET" then "-ASK #{SLOTS.key_slot(req[1])} 127.0.0.1:#{target.port}#{CRLF}"
      else "+OK#{CRLF}"
      end
    end
    cluster = HotKV::Cluster.new(urls: ["hotkv://#{source.addr}"])
    assert_equal "MIGRATED", cluster.get("k")
    assert_equal %w[ASKING GET], target.commands
    cluster.close
  end

  def test_refresh_skips_a_dead_seed
    live = nil
    live = start { |req, _| cluster_cmd?(req) ? table(range_entry(0, 16_383, live.port)) : "+LIVE#{CRLF}" }
    dead = TCPServer.new("127.0.0.1", 0)
    dead_port = dead.addr[1]
    dead.close
    cluster = HotKV::Cluster.new(urls: ["hotkv://127.0.0.1:#{dead_port}", "hotkv://#{live.addr}"],
                                 connect_timeout: 1.0)
    assert_equal "LIVE", cluster.get("k")
    cluster.close
  end

  def test_redirect_loop_ends_in_clusterdown
    a = b = nil
    a = start do |req, _|
      cluster_cmd?(req) ? table(range_entry(0, 16_383, a.port)) : "-MOVED 1 127.0.0.1:#{b.port}#{CRLF}"
    end
    b = start { |req, _| cluster_cmd?(req) ? "*0#{CRLF}" : "-MOVED 1 127.0.0.1:#{a.port}#{CRLF}" }
    cluster = HotKV::Cluster.new(urls: ["hotkv://#{a.addr}"], max_redirects: 3)
    assert_raises(HotKV::Error::ClusterDownError) { cluster.get("k") }
    cluster.close
  end

  def test_other_server_errors_are_raised_not_followed
    a = nil
    a = start do |req, _|
      cluster_cmd?(req) ? table(range_entry(0, 16_383, a.port)) : "-WRONGTYPE bad#{CRLF}"
    end
    cluster = HotKV::Cluster.new(urls: ["hotkv://#{a.addr}"])
    assert_raises(HotKV::Error::WrongTypeError) { cluster.get("k") }
    assert_equal 1, a.requests.count { |r| r[0] == "GET" }
    cluster.close
  end

  def test_malformed_redirect_reply_does_not_crash_the_parser
    err = HotKV::Error::ServerError.from_message("MOVED")
    assert_kind_of HotKV::Error::MovedError, err
    assert_equal 0, err.slot
  end
end
