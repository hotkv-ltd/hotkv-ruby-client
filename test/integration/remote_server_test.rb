# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"
require "securerandom"
require "uri"

# A customer style session against a public, TLS and password protected
# HotKV server, over the internet. Skipped unless HOTKV_REMOTE_HOST is set:
#
#   HOTKV_REMOTE_HOST=<host> HOTKV_REMOTE_PORT=<port> \
#   HOTKV_REMOTE_CA=/path/to/ca.pem HOTKV_REMOTE_PASSWORD=... \
#     bundle exec ruby -Ilib -Itest test/integration/remote_server_test.rb
#
# The password is read from the environment only and is never printed.
# Every key and namespace carries a random prefix
# ("remote-ruby-<hex>") and is removed again; nothing global (FLUSHALL,
# CONFIG SET, ACL changes) is ever issued. The server is expected to be
# licensed for the AI features.
class RemoteServerTest < Minitest::Test
  HOST = ENV["HOTKV_REMOTE_HOST"]
  PORT = (ENV["HOTKV_REMOTE_PORT"] || "6379").to_i
  CA = ENV["HOTKV_REMOTE_CA"]
  PASSWORD = ENV["HOTKV_REMOTE_PASSWORD"]

  def setup
    skip "HOTKV_REMOTE_HOST not set, skipping the remote server session" unless HOST
    @prefix = "remote-ruby-#{SecureRandom.hex(4)}"
    @client = connect
    @cleanups = []
  end

  def teardown
    return unless @client

    @cleanups.reverse_each do |cleanup|
      begin
        cleanup.call
      rescue HotKV::Error::Base
        nil # best effort: a failed test may not have created the object
      end
    end
    @client.close
  end

  private

  def connect(**overrides)
    options = { ca_file: CA, password: PASSWORD, connect_timeout: 10.0, command_timeout: 30.0 }.merge(overrides)
    options.delete(:ca_file) if options[:ca_file].nil?
    HotKV::Client.new(url: "hotkvs://#{HOST}:#{PORT}", **options)
  end

  def rname(label)
    "#{@prefix}-#{label}"
  end

  def cleanup(&block)
    @cleanups << block
  end

  # Queue#pop(timeout:) needs Ruby 3.2; nil when nothing arrives in time.
  def pop_within(queue, seconds)
    Timeout.timeout(seconds) { queue.pop }
  rescue Timeout::Error
    nil
  end

  def key(label)
    k = rname(label)
    cleanup { @client.del(k) }
    k
  end

  public

  # -- connecting and authenticating --

  def test_ping_and_server_identity
    assert_equal "PONG", @client.ping
    assert_equal "echo-me", @client.echo("echo-me")
    refute_nil @client.info("server")
  end

  def test_url_form_with_the_password_in_the_url
    skip "no password configured" unless PASSWORD
    userinfo = ":#{URI.encode_www_form_component(PASSWORD)}"
    client = HotKV::Client.new(url: "hotkvs://#{userinfo}@#{HOST}:#{PORT}", ca_file: CA)
    assert_equal "PONG", client.ping
  ensure
    client&.close
  end

  def test_wrong_password_fails_cleanly
    client = connect(password: "definitely-not-the-password")
    assert_raises(HotKV::Error::WrongPassError, HotKV::Error::NoAuthError) { client.ping }
    # The failed login leaves no pooled connection behind.
    assert_equal 0, client.instance_variable_get(:@pool).size
  ensure
    client&.close
  end

  def test_no_password_is_refused
    client = connect(password: nil)
    err = assert_raises(HotKV::Error::ServerError) { client.get(rname("noauth")) }
    assert_includes %w[NOAUTH WRONGPASS DENIED], err.code
  ensure
    client&.close
  end

  def test_certificate_is_verified_against_the_ca
    skip "no CA file configured" unless CA
    client = HotKV::Client.new(url: "hotkvs://#{HOST}:#{PORT}", password: PASSWORD, connect_timeout: 10.0) # system CAs only
    assert_raises(HotKV::Error::ConnectionError) { client.ping } # a self signed certificate must not verify
  ensure
    client&.close
  end

  def test_the_certificate_must_match_the_host_name
    skip "no CA file configured" unless CA
    client = connect(server_name: "wrong.example.com")
    err = assert_raises(HotKV::Error::ConnectionError) { client.ping }
    assert_match(/does not match/, err.message)
  ensure
    client&.close
  end

  def test_insecure_skip_verify_connects_without_the_ca
    client = HotKV::Client.new(url: "hotkvs://#{HOST}:#{PORT}", password: PASSWORD, insecure_skip_verify: true,
                               connect_timeout: 10.0)
    assert_equal "PONG", client.ping
  ensure
    client&.close
  end

  def test_resp2_connection
    client = connect(resp3: false)
    assert_equal "PONG", client.ping
    k = rname("resp2")
    assert_equal "OK", client.set(k, "v")
    assert_equal "v", client.get(k)
    client.del(k)
  ensure
    client&.close
  end

  # -- data types --

  def test_strings_and_expiry
    k = key("str")
    assert_equal "OK", @client.set(k, "hello")
    assert_equal "hello", @client.get(k)
    assert_equal 11, @client.append(k, " world")
    assert_equal "hello world", @client.get(k)
    n = key("counter")
    assert_equal 1, @client.incr(n)
    assert_equal 11, @client.incrby(n, 10)
    assert_in_delta 11.5, @client.incrbyfloat(n, 0.5), 1e-9
    assert_equal true, @client.expire(k, 100)
    assert_includes 1..100, @client.ttl(k)
    assert_equal true, @client.persist(k)
    assert_equal(-1, @client.ttl(k))
    e = key("expiring")
    assert_equal "OK", @client.set(e, "gone soon", px: 300)
    assert_equal "gone soon", @client.get(e)
    sleep 0.6
    assert_nil @client.get(e)
    m1, m2 = key("m1"), key("m2")
    assert_equal true, @client.mset({ m1 => "1", m2 => "2" })
    assert_equal %w[1 2], @client.mget(m1, m2)
  end

  def test_hashes_lists_sets_sorted_sets
    h = key("hash")
    assert_equal 2, @client.hset(h, { "a" => "1", "b" => "2" })
    assert_equal({ "a" => "1", "b" => "2" }, @client.hgetall(h))
    assert_equal 5, @client.hincrby(h, "a", 4)

    l = key("list")
    assert_equal 3, @client.rpush(l, %w[x y z])
    assert_equal %w[x y z], @client.lrange(l, 0, -1)
    assert_equal "x", @client.lpop(l)

    s = key("set")
    assert_equal 3, @client.sadd(s, %w[a b c])
    assert_equal true, @client.sismember(s, "b")
    assert_equal %w[a b c], @client.smembers(s).sort

    z = key("zset")
    assert_equal 3, @client.zadd(z, 1, "one", 2.5, "two", 1.0e-05, "tiny")
    assert_equal [["tiny", 1.0e-05], ["one", 1.0], ["two", 2.5]], @client.zrange(z, 0, -1, with_scores: true)
    assert_equal 0, @client.zrank(z, "tiny")
  end

  def test_streams
    s = key("stream")
    id1 = @client.xadd(s, { "field" => "one" })
    id2 = @client.xadd(s, { "field" => "two" })
    assert_equal 2, @client.xlen(s)
    assert_equal [[id1, { "field" => "one" }], [id2, { "field" => "two" }]], @client.xrange(s)
    assert_equal true, @client.xgroup_create(s, "g", "0")
    read = @client.xreadgroup("g", "c1", keys: [s], ids: [">"], count: 10)
    assert_equal 2, read[s].length
    assert_equal 2, @client.xack(s, "g", id1, id2)
  end

  def test_binary_safe_values_and_a_one_megabyte_round_trip
    k = key("big")
    payload = Random.new(42).bytes(1_048_576)
    assert_equal "OK", @client.set(k, payload)
    got = @client.get(k)
    assert_equal payload.bytesize, got.bytesize
    assert_equal payload, got.b
    assert_equal 1_048_576, @client.strlen(k)
    all_bytes = (0..255).map(&:chr).join.b * 100
    small = key("allbytes")
    @client.set(small, all_bytes)
    assert_equal all_bytes, @client.get(small).b
  end

  # -- batching --

  def test_pipeline_and_transaction
    a = key("pipe")
    results = @client.pipelined do |p|
      p.set(a, "1")
      p.incr(a)
      p.get(a)
      p.get(rname("pipe-missing"))
    end
    assert_equal ["OK", 2, "2", nil], results

    b = key("tx")
    result = @client.multi do |tx|
      tx.set(b, "100")
      tx.decrby(b, 30)
    end
    assert_equal ["OK", 70], result
    assert_equal "70", @client.get(b)

    w = key("watch")
    @client.set(w, "10")
    out = @client.watch(w) do |session|
      current = session.get(w).to_i
      session.multi { |tx| tx.set(w, (current + 5).to_s) }
    end
    assert_equal ["OK"], out
    assert_equal "15", @client.get(w)
  end

  def test_pubsub_over_separate_connections
    channel = rname("chan")
    subscriber = connect
    ready = Queue.new
    received = Queue.new
    thread = Thread.new do
      subscriber.subscribe(channel) do |on|
        on.subscribe { |_ch, _n| ready << :ready }
        on.message do |ch, payload|
          received << [ch, payload]
          on.unsubscribe
        end
      end
    end
    refute_nil pop_within(ready, 15), "subscribe was not confirmed"
    publisher = connect
    assert_equal 1, publisher.publish(channel, "over-the-internet")
    ch, payload = pop_within(received, 15)
    assert_equal channel, ch
    assert_equal "over-the-internet", payload
    assert thread.join(15)
    publisher.close
  ensure
    subscriber&.close
  end

  def test_concurrent_use_of_one_client
    k = key("concurrent")
    threads = Array.new(8) do
      Thread.new { 25.times { @client.incr(k) } }
    end
    threads.each(&:join)
    assert_equal "200", @client.get(k)
  end

  def test_reconnects_after_the_server_closes_a_connection
    victim = connect(pool_size: 1, idle_timeout: 0.2)
    assert_equal "PONG", victim.ping
    id = victim.client_id
    assert_equal 1, @client.client_kill_id(id) # the server closes the idle connection
    sleep 0.4
    k = rname("reconnect")
    assert_equal "OK", victim.set(k, "after reconnect") # the idle health check replaced the dead connection
    assert_equal "after reconnect", victim.get(k)
    victim.del(k)
    # Without the idle check a read only command is retried transparently.
    plain = connect(pool_size: 1)
    plain.ping
    assert_equal 1, @client.client_kill_id(plain.client_id)
    assert_equal "PONG", plain.ping
  ensure
    victim&.close
    plain&.close
  end

  # -- AI features through the typed API --

  def test_semantic_cache
    ns = rname("scache")
    cleanup { @client.scache.drop(ns) }
    assert_equal true, @client.scache.create(ns, 3, threshold: 0.9)
    assert_equal true, @client.scache.set(ns, "what is hotkv", "a datastore", [0.1, 0.2, 0.3],
                                          usage: HotKV::TokenUsage.new(model: "claude-sonnet-5", input_tokens: 50,
                                                                       output_tokens: 10))
    hit = @client.scache.get(ns, [0.1, 0.2, 0.31]) # a similar, not identical, embedding
    assert_equal "a datastore", hit[:response]
    assert_operator hit[:similarity], :>, 0.99
    assert_nil @client.scache.get(ns, [-1.0, -0.5, -0.2])
    stats = @client.scache.stats(ns)
    assert_equal 1, stats[:entries]
    assert_operator stats[:hits], :>=, 1
    assert_operator stats[:usage_saved_input_tokens], :>=, 50
    assert_equal true, @client.scache.threshold(ns, 1.0e-05)
    assert_includes @client.scache.list, ns
    assert_equal true, @client.scache.drop(ns)
  end

  def test_prompt_cache_and_keyed_caches
    ns = rname("pcache")
    cleanup { @client.pcache.drop(ns) }
    assert_equal true, @client.pcache.create(ns, max_entries: 100, ttl: 300, cost_per_hit: 2.5e-05)
    assert_equal true, @client.pcache.set(ns, "prompt", "response")
    assert_equal "response", @client.pcache.get(ns, "prompt")
    assert_equal "response", @client.pcache.getex(ns, "prompt")[:response]
    assert_operator @client.pcache.stats(ns)[:hits], :>=, 2
    assert_equal true, @client.pcache.drop(ns)

    %i[tool_cache ncache guard rerank].each do |accessor|
      cache = @client.public_send(accessor)
      cns = rname(accessor.to_s.tr("_", "-"))
      cleanup { cache.drop(cns) }
      assert_equal true, cache.create(cns, max_entries: 20, ttl: 300), accessor.to_s
      assert_equal true, cache.set(cns, "k1", "v1"), accessor.to_s
      assert_equal "v1", cache.get(cns, "k1"), accessor.to_s
      assert_operator cache.stats(cns)[:entries], :>=, 1, accessor.to_s
      assert_equal true, cache.del(cns, "k1"), accessor.to_s
      assert_equal true, cache.drop(cns), accessor.to_s
    end
  end

  def test_llm_budget_with_float_limits_and_llm_stats
    budget = rname("budget")
    cleanup { @client.llmbudget.drop(budget) }
    assert_equal true, @client.llmbudget.set(budget, 1_000_000, 1.0e-05, 3600) # a tiny float limit
    status = @client.llmbudget.status(budget)
    assert_in_delta 1.0e-05, status[:cost_limit_usd], 1e-9
    assert_equal true, @client.llmbudget.consume(budget, 10, 5.0e-06)
    assert_equal false, @client.llmbudget.consume(budget, 10, 9.0e-06) # would pass the cost cap
    assert_equal true, @client.llmbudget.set(budget, 1_000_000, 25.5, 3600)
    assert_in_delta 25.5, @client.llmbudget.status(budget)[:cost_limit_usd], 1e-9
    assert_equal true, @client.llmbudget.drop(budget)

    bucket = rname("stats")
    cleanup { @client.llmstats.drop(bucket) }
    assert_equal true, @client.llmstats.bucket(bucket)
    assert_equal true, @client.llmstats.record(bucket, 100, 50, 0, 0.002, 250)
    assert_equal true, @client.llmstats.record(bucket, 100, 20, 0, 0, 120, model: "claude-sonnet-5")
    stats = @client.llmstats.get(bucket)
    assert_equal 2, stats[:requests]
    assert_operator stats[:cost_usd], :>, 0.0
    model = rname("model")
    cleanup { @client.llmstats.price_del(model) }
    assert_equal true, @client.llmstats.price_set(model, 1.0e-05, 3.0, cache_read_usd_per_mtok: 0.3)
    price = @client.llmstats.price_get(model)
    assert_in_delta 1.0e-05, price.input_usd_per_mtok, 1e-9
    assert_equal true, @client.llmstats.price_del(model)
    assert_equal true, @client.llmstats.drop(bucket)
  end

  def test_prompt_registry_and_embedding_dedup
    prompt = rname("prompt")
    cleanup { @client.prompt.drop(prompt) }
    assert_equal 1, @client.prompt.put(prompt, "You are a {{role}}.")
    assert_equal 2, @client.prompt.put(prompt, "You are a helpful {{role}}.")
    assert_equal "You are a {{role}}.", @client.prompt.get(prompt, 1)[:content]
    assert_equal 2, @client.prompt.latest(prompt)[:version]
    assert_equal [1, 2], @client.prompt.versions(prompt)
    assert_equal true, @client.prompt.setactive(prompt, 1)
    assert_includes @client.prompt.list, prompt
    assert_equal true, @client.prompt.drop(prompt)

    ns = rname("dedup")
    cleanup { @client.embed_dedup.drop(ns) }
    assert_equal true, @client.embed_dedup.put(ns, "hash1", "text-embedding-3", "0.1,0.2,0.3")
    assert_equal "0.1,0.2,0.3", @client.embed_dedup.get(ns, "hash1")
    assert_equal 1, @client.embed_dedup.stats(ns)[:entries]
    assert_equal true, @client.embed_dedup.release(ns, "hash1")
    assert_equal true, @client.embed_dedup.drop(ns)
  end

  def test_agent_memory_and_rag
    session = rname("conv")
    cleanup { @client.amem.conv_drop(session) }
    assert_equal true, @client.amem.conv_create(session, window: 10)
    @client.amem.conv_append(session, "user", "hello")
    @client.amem.conv_append(session, "assistant", "hi there")
    assert_equal [{ role: "user", content: "hello" }, { role: "assistant", content: "hi there" }],
                 @client.amem.conv_get(session)

    agent = rname("agent")
    cleanup { @client.amem.sem_forget(agent, "m1") }
    assert_equal true, @client.amem.sem_create(agent, 3)
    assert_equal true, @client.amem.sem_store(agent, "m1", "a fact", [0.1, 0.2, 0.3])
    assert_equal "m1", @client.amem.sem_recall(agent, 1, [0.1, 0.2, 0.3]).first[:key]
    assert_equal "semantic", @client.amem.search(agent, 3, [0.1, 0.2, 0.3]).first[:source]
    assert_equal true, @client.amem.work_set(session, "scratch", "v")
    assert_equal "v", @client.amem.work_get(session, "scratch")
    assert_equal true, @client.amem.work_clear(session)
    assert_equal true, @client.amem.epis_log(agent, "tool_call", "did a thing")
    assert_equal "tool_call", @client.amem.epis_query(agent).first[:type]
    assert_equal true, @client.amem.epis_clear(agent)
    assert_equal 1, @client.amem.summary.set(agent, "Likes Ruby.")
    assert_includes @client.amem.summary.get(agent)[:summary], "Ruby"
    @client.amem.summary.drop(agent)
    assert_equal true, @client.amem.conv_drop(session)

    pipeline = rname("rag")
    cleanup { @client.rag.drop(pipeline) }
    assert_equal true, @client.rag.create(pipeline, 3, chunk_size: 100)
    assert_equal 1, @client.rag.ingest(pipeline, "doc1", "hello world this is a test", vectors: [[0.1, 0.2, 1.0e-05]])
    results = @client.rag.search(pipeline, "hello", k: 3, alpha: 0.5, vector: [0.1, 0.2, 1.0e-05])
    assert_equal "doc1", results.first[:doc_id]
    assert_equal true, @client.rag.drop(pipeline)
  end

  def test_rate_limiting_time_series_features_and_vectors
    rl = rname("rl")
    cleanup { @client.ratelimit.drop(rl) }
    assert_equal true, @client.ratelimit.create(rl, 3, 60_000)
    allowed = Array.new(4) { @client.ratelimit.check(rl, "user1")[:allowed] }
    assert_equal [true, true, true, false], allowed
    assert_equal true, @client.ratelimit.drop(rl)

    g = rname("gcra")
    cleanup { @client.gcra.reset(g) }
    first = @client.gcra.limit(g, 1000, 2)
    assert_equal false, first[:denied]
    assert_equal 1, @client.gcra.reset(g)

    ts = rname("ts")
    cleanup { @client.ts.delete(ts) }
    assert_equal true, @client.ts.create(ts, retention: 600_000)
    now = (Time.now.to_f * 1000).to_i
    @client.ts.add(ts, 1.5, timestamp: now)
    @client.ts.add(ts, 2.5, timestamp: now + 1000)
    assert_equal [[now, 1.5], [now + 1000, 2.5]], @client.ts.range(ts, now, now + 1000)
    assert_equal true, @client.ts.delete(ts)

    group = rname("feat")
    cleanup { @client.feature.drop(group) }
    assert_equal true, @client.feature.create(group, "remote group", { "age" => "int64", "score" => "double" })
    assert_equal true, @client.feature.set(group, "e1", { "age" => 30, "score" => 1.5 })
    got = @client.feature.get(group, "e1")
    assert_equal 30, got[:values]["age"]
    assert_equal true, @client.feature.drop(group)

    index = rname("vsim")
    cleanup { @client.vsim.dropindex(index) }
    assert_equal true, @client.vsim.createindex(index, 3, metric: "cosine")
    @client.vsim.set(index, "a", [1.0, 0.0, 1.0e-05])
    @client.vsim.set(index, "b", [0.0, 1.0, 0.0])
    nearest = @client.vsim.search(index, 1, [0.9, 0.1, 0.0])
    assert_equal "a", nearest.first.first
    assert_equal 1, @client.vsim.del(index, "b")
    assert_equal true, @client.vsim.dropindex(index)
  end
end
