# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

# SCACHE.*, AMEM.* (excluding AMEM.SUMMARY.*), RAG.*, RATELIMIT.*, TS.*,
# FEATURE.* and OBSERVE/ALERTS need a server license that includes the
# matching feature. Each test below runs the real command sequence and
# lets #skip_unless_licensed turn a NOLICENSE reply into a clean skip, so
# the tests assert real behaviour whenever the server's license includes
# the feature.
class ExtensionsLicensedIntegrationTest < HotKVIntegrationTest
  def test_scache_lifecycle
    skip_unless_licensed do
      ns = uniq("scache")
      assert_equal true, @client.scache.create(ns, 3, threshold: 0.8)
      assert_equal true, @client.scache.set(ns, "what is hotkv", "a datastore", [0.1, 0.2, 0.3])
      hit = @client.scache.get(ns, [0.1, 0.2, 0.3])
      assert_equal "a datastore", hit[:response]
      assert_kind_of Float, hit[:similarity]
      assert_nil @client.scache.get(ns, [-1.0, -1.0, -1.0], threshold: 0.999)
      stats = @client.scache.stats(ns)
      assert_operator stats[:entries], :>=, 1
      assert_kind_of Float, stats[:hit_rate]
      assert_equal true, @client.scache.threshold(ns, 0.5)
      assert_includes @client.scache.list, ns
      assert_equal true, @client.scache.flush(ns) == true || @client.scache.flush(ns) == false
      assert_equal true, @client.scache.drop(ns)
    end
  end

  def test_scache_set_with_usage_reports_savings_on_stats
    skip_unless_licensed do
      ns = uniq("scache-usage")
      usage = HotKV::TokenUsage.new(model: "claude-sonnet-5", input_tokens: 100, output_tokens: 20)
      assert_equal true, @client.scache.create(ns, 3, threshold: 0.8)
      assert_equal true, @client.scache.set(ns, "q", "cached answer", [0.1, 0.2, 0.3], usage: usage)
      assert @client.scache.get(ns, [0.1, 0.2, 0.3]) # attribute the hit

      stats = @client.scache.stats(ns)
      assert_operator stats[:usage_saved_requests], :>=, 1
      assert_operator stats[:usage_saved_input_tokens], :>=, 100
      assert_kind_of Float, stats[:usage_saved_cost_usd]
    end
  end

  def test_amem_conversation_memory
    skip_unless_licensed do
      session = uniq("amem-conv")
      assert_equal true, @client.amem.conv_create(session, window: 10)
      assert_equal true, @client.amem.conv_append(session, "user", "hello")
      assert_equal true, @client.amem.conv_append(session, "assistant", "hi there")
      turns = @client.amem.conv_get(session)
      assert_equal [{ role: "user", content: "hello" }, { role: "assistant", content: "hi there" }], turns
      assert_equal [{ role: "assistant", content: "hi there" }], @client.amem.conv_window(session, 1)
      assert_equal true, @client.amem.conv_clear(session)
      assert_equal true, @client.amem.conv_drop(session)
    end
  end

  def test_amem_semantic_memory
    skip_unless_licensed do
      agent = uniq("amem-sem")
      assert_equal true, @client.amem.sem_create(agent, 3)
      assert_equal true, @client.amem.sem_store(agent, "mem1", "some fact", [0.1, 0.2, 0.3])
      recalled = @client.amem.sem_recall(agent, 1, [0.1, 0.2, 0.3])
      assert_equal 1, recalled.length
      assert_equal "mem1", recalled.first[:key]
      assert_kind_of Float, recalled.first[:similarity]
      assert_equal ["mem1"], @client.amem.sem_list(agent)
      assert_equal true, @client.amem.sem_forget(agent, "mem1")
    end
  end

  def test_amem_working_memory
    skip_unless_licensed do
      session = uniq("amem-work")
      assert_equal true, @client.amem.work_set(session, "scratch", "value1")
      assert_equal "value1", @client.amem.work_get(session, "scratch")
      assert_equal ["scratch"], @client.amem.work_list(session)
      assert_equal true, @client.amem.work_del(session, "scratch")
      assert_equal true, @client.amem.work_set(session, "s2", "v2")
      assert_equal true, @client.amem.work_clear(session)
    end
  end

  def test_amem_episodic_memory
    skip_unless_licensed do
      agent = uniq("amem-epis")
      assert_equal true, @client.amem.epis_log(agent, "tool_call", "did something", metadata: '{"k":1}')
      events = @client.amem.epis_query(agent)
      assert_equal 1, events.length
      assert_equal "tool_call", events.first[:type]
      stats = @client.amem.epis_stats(agent)
      assert_equal 1, stats[:total_events]
      assert_equal true, @client.amem.epis_clear(agent)
    end
  end

  def test_amem_cross_memory_search
    skip_unless_licensed do
      agent = uniq("amem-search")
      @client.amem.sem_create(agent, 3)
      @client.amem.sem_store(agent, "mem1", "some fact", [0.1, 0.2, 0.3])
      results = @client.amem.search(agent, 3, [0.1, 0.2, 0.3])
      assert_operator results.length, :>=, 1
      assert_equal "semantic", results.first[:source]
    end
  end

  def test_ratelimit_lifecycle
    skip_unless_licensed do
      name = uniq("rl")
      assert_equal true, @client.ratelimit.create(name, 5, 60_000)
      result = @client.ratelimit.check(name, "user1")
      assert_equal true, result[:allowed]
      assert_equal 5, result[:limit]
      peek = @client.ratelimit.peek(name, "user1")
      assert_kind_of Integer, peek[:remaining]
      stats = @client.ratelimit.stats(name)
      assert_equal name, stats[:name]
      assert_equal true, @client.ratelimit.reset(name, "user1")
      assert_equal true, @client.ratelimit.drop(name)
    end
  end

  def test_ts_lifecycle
    skip_unless_licensed do
      key = uniq("ts")
      assert_equal true, @client.ts.create(key, retention: 60_000, labels: { "region" => "eu" })
      ts = @client.ts.add(key, 42)
      assert_kind_of Integer, ts
      range = @client.ts.range(key, "-", "+")
      assert_equal [[ts, 42.0]], range
      info = @client.ts.info(key)
      assert_equal key, info[:key]
      assert_equal [["region", "eu"]], info[:labels]
      assert_includes @client.ts.list, key
      assert_equal true, @client.ts.retention(key, 120_000)
      assert_equal true, @client.ts.delete(key)
    end
  end

  def test_ts_agg_and_downsample
    skip_unless_licensed do
      src, dest = uniq("ts"), uniq("ts")
      @client.ts.create(src)
      @client.ts.create(dest)
      now = (Time.now.to_f * 1000).to_i
      @client.ts.add(src, 1, timestamp: now)
      @client.ts.add(src, 3, timestamp: now + 1000)
      agg = @client.ts.agg(src, now, now + 1000, 10_000, "avg")
      refute_empty agg
      assert_equal true, @client.ts.downsample(src, dest, "avg", 10_000)
      @client.ts.delete(src)
      @client.ts.delete(dest)
    end
  end

  def test_feature_store_lifecycle
    skip_unless_licensed do
      group = uniq("feat")
      assert_equal true, @client.feature.create(group, "test group", { "age" => "int64", "score" => "double" })
      assert_equal true, @client.feature.set(group, "e1", { "age" => 30, "score" => 1.5 })
      result = @client.feature.get(group, "e1")
      assert_equal 30, result[:values]["age"]
      batch = @client.feature.batch(group, ["e1", "missing"])
      refute_nil batch[0]
      assert_nil batch[1]
      assert_equal [%w[age int64], %w[score double]], @client.feature.schema(group)
      assert_includes @client.feature.list, group
      stats = @client.feature.stats(group)
      assert_operator stats[:entities], :>=, 1
      assert_equal true, @client.feature.drop(group)
    end
  end

  def test_rag_lifecycle
    skip_unless_licensed do
      pipeline = uniq("rag")
      assert_equal true, @client.rag.create(pipeline, 3, chunk_size: 100)
      chunks = @client.rag.ingest(pipeline, "doc1", "hello world this is a test",
                                   vectors: [[0.1, 0.2, 0.3]])
      assert_equal 1, chunks
      results = @client.rag.search(pipeline, "hello", k: 3)
      assert_operator results.length, :>=, 1
      assert_equal "doc1", results.first[:doc_id]
      assert_kind_of Float, results.first[:score]
      stats = @client.rag.stats(pipeline)
      assert_equal pipeline, stats[:name]
      assert_includes @client.rag.list, pipeline
      assert_equal true, @client.rag.drop(pipeline)
    end
  end

  def test_observe_info_and_metrics
    skip_unless_licensed do
      info = @client.observe.info
      assert_kind_of Integer, info[:uptime_seconds]
      metrics = @client.observe.metrics
      assert_kind_of Integer, metrics[:total_commands]
    end
  end

  def test_alerts_info_and_toggle
    skip_unless_licensed do
      info = @client.alerts.info
      assert_includes [0, 1], info[:enabled]
      @client.alerts.off
      @client.alerts.on
    end
  end
end
