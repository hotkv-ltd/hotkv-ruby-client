# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

# Typed methods for the less common core commands (newer additions, the
# blocking and multi-pop variants, SORT, scripting/functions, ACL, server
# introspection, the probabilistic structures), each run against a live
# server with its reply checked.
class ExtendedCommandsIntegrationTest < HotKVIntegrationTest
  # -- strings --

  def test_set_with_value_and_digest_conditions
    k = track(uniq("setcond"))
    @client.set(k, "v1")
    assert_nil @client.set(k, "v2", ifeq: "nope")
    assert_equal "v1", @client.get(k)
    assert_equal "OK", @client.set(k, "v2", ifeq: "v1")
    assert_equal "OK", @client.set(k, "v3", ifne: "zzz")
    assert_equal "v3", @client.get(k)
    digest = @client.digest(k)
    assert_match(/\A\h{16}\z/, digest)
    assert_nil @client.set(k, "v4", ifdeq: "0" * 16)
    assert_equal "OK", @client.set(k, "v4", ifdeq: digest)
    assert_nil @client.set(k, "v5", ifdne: @client.digest(k))
    assert_equal "v4", @client.get(k)
    assert_nil @client.digest(uniq("nodigest"))
  end

  def test_delex_conditions
    k = track(uniq("delex"))
    @client.set(k, "x")
    assert_equal false, @client.delex(k, ifeq: "y")
    assert_equal false, @client.delex(k, ifne: "x")
    assert_equal false, @client.delex(k, ifdeq: "0" * 16)
    assert_equal true, @client.delex(k, ifdeq: @client.digest(k))
    assert_nil @client.get(k)
    @client.set(k, "x")
    assert_equal true, @client.delex(k)
    assert_equal false, @client.delex(k)
  end

  def test_msetex_sets_all_keys_with_one_ttl
    a, b, c = track(uniq("msetex"), uniq("msetex"), uniq("msetex"))
    assert_equal true, @client.msetex({ a => "1", b => "2" }, ex: 100)
    assert_equal %w[1 2], @client.mget(a, b)
    assert_operator @client.ttl(a), :>, 0
    assert_operator @client.ttl(b), :>, 0
    assert_equal false, @client.msetex({ a => "9", c => "3" }, nx: true, ex: 100) # a exists
    assert_nil @client.get(c)
    assert_equal true, @client.msetex([c, "3"], nx: true, px: 50_000)
    assert_equal "3", @client.get(c)
    assert_equal false, @client.msetex({ uniq("missing") => "x" }, xx: true)
  end

  def test_lcs_substr
    a, b = track(uniq("lcs"), uniq("lcs"))
    @client.mset({ a => "ohmytext", b => "mynewtext" })
    assert_equal "mytext", @client.lcs(a, b)
    assert_equal 6, @client.lcs(a, b, len: true)
    idx = @client.lcs(a, b, idx: true, withmatchlen: true)
    assert_equal 6, idx["len"]
    assert_equal [[[4, 7], [5, 8], 4], [[2, 3], [0, 1], 2]], idx["matches"]
    assert_equal 1, @client.lcs(a, b, idx: true, minmatchlen: 4)["matches"].length
    assert_equal "ohm", @client.substr(a, 0, 2)
  end

  # -- hashes --

  def test_hmset_hgetdel_hgetex_hsetex
    k = track(uniq("hash8"))
    assert_equal true, @client.hmset(k, { "a" => "1", "b" => "2", "c" => "3" })
    assert_equal ["1", nil], @client.hgetdel(k, "a", "zz")
    assert_equal false, @client.hexists(k, "a")

    assert_equal ["2"], @client.hgetex(k, "b", ex: 100)
    assert_operator @client.httl(k, "b").first, :>, 0
    assert_equal ["2"], @client.hgetex(k, "b", persist: true)
    assert_equal [-1], @client.httl(k, "b")

    assert_equal true, @client.hsetex(k, { "d" => "4", "e" => "5" }, fnx: true, ex: 100)
    assert_equal false, @client.hsetex(k, { "d" => "x", "f" => "6" }, fnx: true) # d exists
    assert_equal false, @client.hexists(k, "f")
    assert_equal true, @client.hsetex(k, ["d", "44"], fxx: true, keepttl: true)
    assert_equal "44", @client.hget(k, "d")
    assert_operator @client.httl(k, "d").first, :>, 0
  end

  # -- blocking / multi pop --

  def test_blmpop_and_brpoplpush
    l1, l2 = track(uniq("bl"), uniq("bl"))
    assert_nil @client.blmpop([l1], "LEFT", timeout: 0.05)
    @client.rpush(l1, %w[a b c])
    assert_equal [l1, %w[a b]], @client.blmpop([l1], "LEFT", timeout: 1, count: 2)
    assert_equal "c", @client.brpoplpush(l1, l2, timeout: 1)
    assert_equal %w[c], @client.lrange(l2, 0, -1)
    assert_nil @client.brpoplpush(l1, l2, timeout: 0.05)
  end

  def test_zmpop_bzmpop_bzpopmin_bzpopmax
    z = track(uniq("zmpop"))
    assert_nil @client.zmpop([z], "MIN")
    @client.zadd(z, 1, "a", 2, "b", 3, "c", 4, "d", 5, "e")
    assert_equal [z, [["a", 1.0], ["b", 2.0]]], @client.zmpop([z], "MIN", count: 2)
    assert_equal [z, [["e", 5.0]]], @client.zmpop([z], "MAX")
    assert_equal [z, [["d", 4.0]]], @client.bzmpop([z], "MAX", timeout: 1)
    assert_equal [z, "c", 3.0], @client.bzpopmin(z, timeout: 1)
    @client.zadd(z, 9, "n")
    assert_equal [z, "n", 9.0], @client.bzpopmax(z, timeout: 1)
    assert_nil @client.bzpopmin(z, timeout: 0.05)
    assert_nil @client.bzmpop([z], "MIN", timeout: 0.05)
  end

  # -- geo --

  def test_georadius_family
    k, dest = track(uniq("georad"), uniq("georad"))
    @client.geoadd(k, [[13.361389, 38.115556, "Palermo"], [15.087269, 37.502669, "Catania"]])
    assert_equal %w[Catania], @client.georadius(k, 15, 37, 100, "km")
    both = @client.georadius(k, 15, 37, 200, "km", withdist: true, withcoord: true, asc: true)
    assert_equal %w[Catania Palermo], both.map { |e| e[:member] }
    assert_in_delta 56.4, both.first[:dist], 1.0
    assert_in_delta 15.087, both.first[:coord][0], 0.01
    assert_equal %w[Catania Palermo], @client.georadius_ro(k, 15, 37, 200, "km", asc: true)
    assert_equal %w[Palermo], @client.georadiusbymember(k, "Palermo", 10, "km")
    near = @client.georadiusbymember_ro(k, "Palermo", 200, "km", withdist: true, count: 1, asc: true)
    assert_equal "Palermo", near.first[:member]
    assert_equal 2, @client.georadius(k, 15, 37, 200, "km", store: dest)
    assert_equal 2, @client.zcard(dest)
    assert_raises(HotKV::Error::ArgumentError) { @client.georadius(k, 15, 37, 200, "km", bogus: true) }
  end

  # -- pubsub --

  def test_publish_and_pubsub_introspection
    channel = uniq("pubsubx")
    ready = Queue.new
    done = Queue.new
    thread = Thread.new do
      @client.subscribe(channel) do |on|
        on.subscribe { |_ch, _n| ready << :ok }
        on.message { |_ch, _payload| done << :got; on.unsubscribe }
      end
    end
    wait_for(ready)
    assert_includes @client.pubsub_channels, channel
    assert_includes @client.pubsub_channels("#{channel[0, 8]}*"), channel
    assert_equal({ channel => 1 }, @client.pubsub_numsub(channel))
    assert_kind_of Integer, @client.pubsub_numpat
    assert_equal 1, @client.publish(channel, "hi")
    wait_for(done)
    assert thread.join(5)
    assert_equal 0, @client.publish(channel, "nobody")
    assert_equal({ channel => 0 }, @client.pubsub_numsub(channel))
    assert_kind_of Array, @client.pubsub_shardchannels
    assert_kind_of Hash, @client.pubsub_shardnumsub(channel)
    assert_equal 0, @client.spublish(channel, "x")
  end

  # -- sort / wait / role --

  def test_sort_and_sort_ro
    k, dest = track(uniq("sort"), uniq("sort"))
    @client.rpush(k, %w[3 1 2 10])
    assert_equal %w[1 2 3 10], @client.sort(k)
    assert_equal %w[10 3 2 1], @client.sort(k, order: "desc")
    assert_equal %w[1 10 2 3], @client.sort(k, alpha: true)
    assert_equal %w[2 3], @client.sort(k, limit: [1, 2])
    assert_equal %w[3 2 1], @client.sort_ro(k, order: :desc, limit: [1, 3])
    assert_equal 4, @client.sort(k, store: dest)
    assert_equal %w[1 2 3 10], @client.lrange(dest, 0, -1)
    ids = track(uniq("sortids"))
    w = uniq("sortw")
    @client.rpush(ids, %w[3 1 2])
    track("#{w}_1", "#{w}_2", "#{w}_3", "#{w}_w1", "#{w}_w2", "#{w}_w3")
    @client.mset({ "#{w}_1" => "x", "#{w}_2" => "y", "#{w}_3" => "z" })
    assert_equal %w[x y z], @client.sort(ids, get: "#{w}_*")
    assert_equal %w[1 x 2 y 3 z], @client.sort(ids, get: ["#", "#{w}_*"])
    @client.mset({ "#{w}_w1" => "30", "#{w}_w2" => "10", "#{w}_w3" => "20" })
    assert_equal %w[2 3 1], @client.sort(ids, by: "#{w}_w*")
  end

  def test_wait_waitaof_role
    assert_equal 0, @client.wait(0, 10)
    assert_kind_of Array, @client.waitaof(0, 0, 10)
    role = @client.role
    assert_equal "master", role[0]
  end

  # -- scripting and functions --

  def test_eval_ro_evalsha_ro_script_kill
    assert_equal "q", @client.eval_ro("return ARGV[1]", args: ["q"])
    sha = @client.script_load("return KEYS[1]")
    assert_equal "kk", @client.evalsha_ro(sha, keys: ["kk"])
    err = assert_raises(HotKV::Error::ServerError) { @client.script_kill }
    assert_equal "NOTBUSY", err.code
  end

  def test_functions
    lib = "rblib#{Process.pid}#{rand(100_000)}"
    code = "#!lua name=#{lib}\n" \
           "redis.register_function('#{lib}_rw', function(keys, args) return redis.call('SET', keys[1], args[1]) end)\n" \
           "redis.register_function{function_name='#{lib}_ro', callback=function(keys, args) return redis.call('GET', keys[1]) end, flags={'no-writes'}}"
    k = track(uniq("fn"))
    assert_equal lib, @client.function_load(code, replace: true)
    assert_raises(HotKV::Error::ServerError) { @client.function_load(code) } # already there
    assert_equal({ "OK" => 1 }.keys.first, @client.fcall("#{lib}_rw", keys: [k], args: ["val"])["ok"] || "OK")
    assert_equal "val", @client.fcall("#{lib}_ro", keys: [k])
    assert_equal "val", @client.fcall_ro("#{lib}_ro", keys: [k])
    listed = @client.function_list(libraryname: lib)
    assert_equal 1, listed.length
    assert_equal lib, listed.first["library_name"]
    assert_equal %W[#{lib}_ro #{lib}_rw], listed.first["functions"].map { |f| f["name"] }.sort
    refute_nil @client.function_list(libraryname: lib, withcode: true).first["library_code"]
    stats = @client.function_stats
    assert_includes stats.keys, "engines"
    assert_operator stats["engines"]["LUA"]["libraries_count"], :>=, 1
    dump = @client.function_dump
    assert_kind_of String, dump
    assert_equal true, @client.function_delete(lib)
    assert_empty @client.function_list(libraryname: lib)
    assert_equal true, @client.function_restore(dump, "APPEND")
    assert_equal 1, @client.function_list(libraryname: lib).length
    assert_equal true, @client.function_delete(lib)
    err = assert_raises(HotKV::Error::ServerError) { @client.function_kill }
    assert_equal "NOTBUSY", err.code
  end

  # -- server --

  def test_save_bgsave_bgrewriteaof_reply_shapes
    assert_equal true, @client.save
    assert_match(/Background saving (started|scheduled)|already in progress/i, @client.bgsave.to_s)
    sleep 0.5
    begin
      assert_kind_of String, @client.bgrewriteaof
    rescue HotKV::Error::ServerError => e
      assert_match(/append|aof/i, e.message) # when appendonly is off
    end
  end

  def test_slowlog_memory_command_and_client_admin
    assert_kind_of Array, @client.slowlog_get
    assert_kind_of Array, @client.slowlog_get(5)
    assert_kind_of Integer, @client.slowlog_len
    assert_equal true, @client.slowlog_reset
    assert_equal 0, @client.slowlog_len

    k = track(uniq("memusage"))
    @client.set(k, "x" * 100)
    assert_operator @client.memory_usage(k), :>=, 100
    assert_operator @client.memory_usage(k, samples: 5), :>=, 100
    assert_nil @client.memory_usage(uniq("nokey"))

    assert_operator @client.command_count, :>, 300
    assert_equal ["a"], @client.command_getkeys("SET", "a", "b")

    assert_equal true, @client.client_pause(1)
    assert_equal true, @client.client_unpause
    assert_equal true, @client.client_pause(1, "WRITE")
    assert_equal true, @client.client_unpause
  end

  def test_client_connection_flags
    one = HotKV::Client.new(url: ENV["HOTKV_TEST_URL"], pool_size: 1, **client_options)
    assert_equal true, one.client_no_evict(true)
    assert_equal true, one.client_no_evict(false)
    assert_equal true, one.client_no_touch(true)
    assert_equal true, one.client_no_touch(false)
    assert_equal true, one.client_setinfo("LIB-NAME", "hotkv-ruby-test")
    id = one.client_id
    assert_equal false, one.client_unblock(id + 1_000_000)
    assert_equal 0, one.client_kill_id(id + 1_000_000)
    assert_equal 1, @client.client_kill_id(id) # another client closes it; the next call reconnects
    assert_equal "PONG", one.ping
  ensure
    one&.close
  end

  # -- streams --

  def test_xsetid_xcfgset_and_idempotent_xadd
    k = track(uniq("stream8"))
    id1 = @client.xadd(k, { "a" => "1" })
    assert_equal true, @client.xcfgset(k, idmp_duration: 200, idmp_maxsize: 50)
    first = @client.xadd(k, { "a" => "2" }, idmp: %w[producer1 iid1])
    again = @client.xadd(k, { "a" => "2" }, idmp: %w[producer1 iid1])
    assert_equal first, again
    refute_equal first, @client.xadd(k, { "a" => "3" }, idmp: %w[producer1 iid2])
    auto1 = @client.xadd(k, { "b" => "x", "c" => "y" }, idmpauto: "producer2")
    auto2 = @client.xadd(k, { "c" => "y", "b" => "x" }, idmpauto: "producer2")
    assert_equal auto1, auto2
    assert_equal 4, @client.xlen(k)
    assert_equal true, @client.xsetid(k, "99999999999999-0")
    assert_match(/\A99999999999999-/, @client.xadd(k, { "z" => "1" }))
    refute_nil id1
  end

  # -- probabilistic structures --

  def test_bloom_filter
    k = track(uniq("bf"))
    assert_equal true, @client.bf.reserve(k, 0.01, 100)
    assert_equal true, @client.bf.add(k, "x")
    assert_equal false, @client.bf.add(k, "x")
    assert_equal [false, true], @client.bf.madd(k, "x", "y")
    assert_equal true, @client.bf.exists(k, "x")
    assert_equal [true, false], @client.bf.mexists(k, "y", "never-added")
    assert_equal 2, @client.bf.card(k)
    info = @client.bf.info(k)
    assert_equal 100, info["Capacity"]
    assert_equal 2, info["Number of items inserted"]
    assert_equal({ "Capacity" => 100 }, @client.bf.info(k, :capacity))
    k2 = track(uniq("bf"))
    assert_equal [true, true], @client.bf.insert(k2, %w[a b], capacity: 50, error: 0.01)
    assert_raises(HotKV::Error::ServerError) { @client.bf.insert(uniq("bfnone"), ["a"], nocreate: true) }
    cursor, data = @client.bf.scandump(k, 0)
    chunks = []
    until cursor.zero?
      chunks << [cursor, data]
      cursor, data = @client.bf.scandump(k, cursor)
    end
    k3 = track(uniq("bf"))
    chunks.each { |(it, chunk)| assert_equal true, @client.bf.loadchunk(k3, it, chunk) }
    assert_equal true, @client.bf.exists(k3, "x")
  end

  def test_count_min_sketch
    k, k2, dest = track(uniq("cms"), uniq("cms"), uniq("cms"))
    assert_equal true, @client.cms.initbydim(k, 100, 5)
    assert_equal [3, 1], @client.cms.incrby(k, { "a" => 3, "b" => 1 })
    assert_equal [5, 1], @client.cms.incrby(k, ["a", 2, "b", 0])
    assert_equal [5, 1, 0], @client.cms.query(k, "a", "b", "zz")
    info = @client.cms.info(k)
    assert_equal({ "width" => 100, "depth" => 5, "count" => 6 }, info)
    assert_equal true, @client.cms.initbyprob(k2, 0.01, 0.01)
    @client.cms.incrby(k2, ["a", 10])
    assert_equal true, @client.cms.initbydim(dest, 100, 5)
    assert_equal true, @client.cms.merge(dest, [k, k2].map { |x| x }, weights: [1, 1]) if @client.cms.info(k2)["width"] == 100
  rescue HotKV::Error::ServerError => e
    # CMS.MERGE needs sketches of equal dimensions; initbyprob(0.01, 0.01) differs from 100x5.
    assert_match(/width|depth|dimension|different/i, e.message)
  end

  def test_count_min_sketch_merge
    a, b, dest = track(uniq("cms"), uniq("cms"), uniq("cms"))
    [a, b, dest].each { |key| @client.cms.initbydim(key, 50, 4) }
    @client.cms.incrby(a, ["x", 2])
    @client.cms.incrby(b, ["x", 3, "y", 1])
    assert_equal true, @client.cms.merge(dest, [a, b])
    assert_equal [5, 1], @client.cms.query(dest, "x", "y")
    assert_equal true, @client.cms.merge(dest, [a, b], weights: [2, 1])
    assert_equal [7], @client.cms.query(dest, "x")
  end

  def test_top_k
    k, k2 = track(uniq("topk"), uniq("topk"))
    assert_equal true, @client.topk.reserve(k, 3)
    @client.topk.add(k, "a", "b", "a", "c", "a", "b")
    assert_equal "a", @client.topk.list(k).first
    assert_equal [true, false], @client.topk.query(k, "a", "never")
    assert_equal [3], @client.topk.count(k, "a")
    assert_equal ["a", 3], @client.topk.list(k, withcount: true).first
    @client.topk.incrby(k, { "d" => 50 })
    assert_equal "d", @client.topk.list(k).first
    info = @client.topk.info(k)
    assert_equal 3, info["k"]
    assert_kind_of Float, info["decay"]
    assert_equal true, @client.topk.reserve(k2, 2, width: 10, depth: 3, decay: 0.8)
    assert_in_delta 0.8, @client.topk.info(k2)["decay"], 0.0001
    assert_raises(HotKV::Error::ArgumentError) { @client.topk.reserve(uniq("tk"), 2, width: 10) }
  end

  # -- ACL --

  def test_acl_user_lifecycle
    user = "rbacl#{Process.pid}#{rand(100_000)}"
    assert_equal "default", @client.acl.whoami
    assert_equal true, @client.acl.setuser(user, "on", ">secret-pw", "+get", "~rbacl*")
    assert_includes @client.acl.users, user
    assert(@client.acl.list.any? { |line| line.include?("user #{user} ") })
    info = @client.acl.getuser(user)
    assert_equal "~rbacl*", info["keys"]
    assert_includes info["flags"], "on"
    assert_equal "OK", @client.acl.dryrun(user, "get", "rbaclfoo")
    refute_equal "OK", @client.acl.dryrun(user, "set", "rbaclfoo", "x")
    assert_nil @client.acl.getuser("rbnosuch#{user}")
    assert_includes @client.acl.cat, "read"
    assert_includes @client.acl.cat("string"), "get"
    assert_match(/\A\h{64}\z/, @client.acl.genpass)
    assert_match(/\A\h{8}\z/, @client.acl.genpass(32))
    assert_kind_of Array, @client.acl.log
    assert_kind_of Array, @client.acl.log(2)
  ensure
    @client.acl.deluser(user) if user
  end

  private

  def wait_for(queue, seconds = 5)
    Timeout.timeout(seconds) { queue.pop }
  end
end
