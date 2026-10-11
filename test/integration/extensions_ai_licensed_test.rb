# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

# PCACHE.*, LLMSTATS.*, LLMBUDGET.*, PROMPT.*, TOOL.CACHE.*/NCACHE.*/
# GUARD.*/RERANK.*, EMBED.DEDUP.*, AMEM.SUMMARY.* and VSIM.SAVE/LOAD/LIST/
# DROP need a server license that includes the matching feature. Each
# test below runs the real command sequence and lets #skip_unless_licensed
# turn the server's NOLICENSE reply into a clean skip, so the tests assert
# real behaviour whenever the server's license includes the feature.
class ExtensionsAiLicensedIntegrationTest < HotKVIntegrationTest
  def test_pcache_lifecycle
    skip_unless_licensed do
      ns = uniq("pcache")
      assert_equal true, @client.pcache.create(ns, max_entries: 100, ttl: 60)
      assert_equal true, @client.pcache.set(ns, "prompt1", "response1")
      assert_equal "response1", @client.pcache.get(ns, "prompt1")
      getex = @client.pcache.getex(ns, "prompt1")
      assert_equal "response1", getex[:response]
      stats = @client.pcache.stats(ns)
      assert_operator stats[:entries], :>=, 1
      assert_kind_of Float, stats[:usage_saved_cost_usd]
      assert_equal true, @client.pcache.config_set(ns, "TTL", 120)
      assert_includes @client.pcache.list, ns
      assert_equal true, @client.pcache.del(ns, "prompt1")
      assert_kind_of Integer, @client.pcache.flush(ns)
      assert_equal true, @client.pcache.drop(ns)
    end
  end

  def test_pcache_set_with_usage_reports_savings_on_stats
    skip_unless_licensed do
      ns = uniq("pcache-usage")
      assert_equal true, @client.pcache.create(ns)
      usage = HotKV::TokenUsage.new(model: "claude-sonnet-5", input_tokens: 100, output_tokens: 20)
      assert_equal true, @client.pcache.set(ns, "prompt1", "response1", usage: usage)
      assert_equal "response1", @client.pcache.get(ns, "prompt1") # attribute the hit

      stats = @client.pcache.stats(ns)
      assert_operator stats[:usage_saved_requests], :>=, 1
      assert_operator stats[:usage_saved_input_tokens], :>=, 100
      assert_operator stats[:usage_saved_output_tokens], :>=, 20
      assert_equal true, @client.pcache.drop(ns)
    end
  end

  def test_llmstats_lifecycle
    skip_unless_licensed do
      bucket = uniq("llmstats")
      assert_equal true, @client.llmstats.bucket(bucket)
      assert_equal true, @client.llmstats.record(bucket, 100, 50, 0, 0.002, 250)
      stats = @client.llmstats.get(bucket)
      assert_equal 1, stats[:requests]
      assert_kind_of Float, stats[:cost_usd]
      assert_equal 0, stats[:unpriced_requests]
      assert_includes @client.llmstats.list, bucket
      assert_equal true, @client.llmstats.reset(bucket)
      assert_equal true, @client.llmstats.drop(bucket)
    end
  end

  def test_llmstats_record_with_model_prices_from_the_server_table
    skip_unless_licensed do
      bucket = uniq("llmstats-model")
      assert_equal true, @client.llmstats.bucket(bucket)
      assert_equal true, @client.llmstats.record(bucket, 100, 20, 0, 0, 150, model: "claude-sonnet-5",
                                                                              cache_write_5m_tokens: 10)
      stats = @client.llmstats.get(bucket)
      assert_equal 1, stats[:requests]
      assert_operator stats[:cost_usd], :>, 0.0
      assert_equal 10, stats[:cache_write_5m_tokens]
      assert_equal 0, stats[:unpriced_requests]

      assert_equal true, @client.llmstats.record(bucket, 5, 5, 0, 0, 10, model: "totally-unknown-model-xyz")
      unpriced_stats = @client.llmstats.get(bucket)
      assert_operator unpriced_stats[:unpriced_requests], :>=, 1
    end
  end

  def test_llmstats_price_set_get_list_del
    skip_unless_licensed do
      model = uniq("model")
      assert_equal true, @client.llmstats.price_set(model, 3, 15, cache_read_usd_per_mtok: 0.3)
      price = @client.llmstats.price_get(model)
      assert_kind_of HotKV::LLMPrice, price
      assert_equal model, price.model
      assert_equal "custom", price.source
      assert_equal true, price.priced
      assert_in_delta 3.0, price.input_usd_per_mtok
      assert_in_delta 15.0, price.output_usd_per_mtok
      assert_in_delta 0.3, price.cache_read_usd_per_mtok
      # Undeclared cache write tiers default to 1.25x/2x the input price.
      assert_in_delta 3.75, price.cache_write_5m_usd_per_mtok
      assert_in_delta 6.0, price.cache_write_1h_usd_per_mtok

      list = @client.llmstats.price_list
      assert_kind_of Array, list
      assert_includes list.map(&:model), model

      unknown = @client.llmstats.price_get(uniq("no-such-model"))
      assert_equal "unpriced", unknown.source
      assert_equal false, unknown.priced

      assert_equal true, @client.llmstats.price_del(model)
      assert_equal false, @client.llmstats.price_del(model) # already gone
    end
  end

  def test_llmbudget_lifecycle
    skip_unless_licensed do
      name = uniq("llmbudget")
      assert_equal true, @client.llmbudget.set(name, 10_000, 5.0, 3600)
      assert_equal true, @client.llmbudget.consume(name, 100, 0.01)
      status = @client.llmbudget.status(name)
      assert_equal 10_000, status[:token_limit]
      assert_equal 0, status[:unpriced_requests]
      assert_equal true, @client.llmbudget.reset(name)
      assert_equal true, @client.llmbudget.drop(name)
    end
  end

  def test_llmbudget_consume_with_usage_is_priced_by_the_server
    skip_unless_licensed do
      name = uniq("llmbudget-usage")
      assert_equal true, @client.llmbudget.set(name, 10_000, 5.0, 3600)
      usage = HotKV::TokenUsage.new(model: "claude-sonnet-5", input_tokens: 100, output_tokens: 20)
      assert_equal true, @client.llmbudget.consume(name, usage: usage)
      status = @client.llmbudget.status(name)
      assert_equal 120, status[:tokens_used]
      assert_operator status[:cost_used_usd], :>, 0.0
    end
  end

  def test_prompt_registry_lifecycle
    skip_unless_licensed do
      name = uniq("prompt")
      assert_equal 1, @client.prompt.put(name, "You are a {{role}}.")
      assert_equal 2, @client.prompt.put(name, "You are a helpful {{role}}.")
      got = @client.prompt.get(name)
      assert_equal 2, got[:version]
      v1 = @client.prompt.get(name, 1)
      assert_equal "You are a {{role}}.", v1[:content]
      assert_equal [1, 2], @client.prompt.versions(name)
      assert_equal true, @client.prompt.setactive(name, 1)
      assert_includes @client.prompt.list, name
      assert_equal true, @client.prompt.drop(name)
    end
  end

  %i[tool_cache ncache guard rerank].each do |accessor|
    define_method("test_#{accessor}_lifecycle") do
      skip_unless_licensed do
        ns = uniq(accessor.to_s)
        cache = @client.public_send(accessor)
        assert_equal true, cache.create(ns, max_entries: 50)
        usage = HotKV::TokenUsage.new(model: "claude-sonnet-5", input_tokens: 100, output_tokens: 20)
        assert_equal true, cache.set(ns, "key1", "value1", usage: usage)
        assert_equal "value1", cache.get(ns, "key1") # attribute the hit
        stats = cache.stats(ns)
        assert_operator stats[:entries], :>=, 1
        assert_operator stats[:usage_saved_requests], :>=, 1
        assert_kind_of Float, stats[:usage_saved_cost_usd]
        assert_includes cache.list, ns
        assert_equal true, cache.del(ns, "key1")
        assert_kind_of Integer, cache.flush(ns)
        assert_equal true, cache.drop(ns)
      end
    end
  end

  def test_embed_dedup_lifecycle
    skip_unless_licensed do
      ns = uniq("embeddedup")
      assert_equal true, @client.embed_dedup.put(ns, "hash1", "text-embedding-3", "0.1,0.2,0.3")
      assert_equal false, @client.embed_dedup.put(ns, "hash1", "text-embedding-3", "0.1,0.2,0.3")
      assert_equal "0.1,0.2,0.3", @client.embed_dedup.get(ns, "hash1")
      stats = @client.embed_dedup.stats(ns)
      assert_kind_of Integer, stats[:entries]
      assert_includes @client.embed_dedup.list, ns
      assert_equal true, @client.embed_dedup.release(ns, "hash1")
      assert_equal true, @client.embed_dedup.purge(ns)
      assert_equal true, @client.embed_dedup.drop(ns)
    end
  end

  def test_amem_summary_lifecycle
    skip_unless_licensed do
      agent = uniq("amem-summary")
      assert_equal 1, @client.amem.summary.set(agent, "User likes concise answers.")
      assert_equal 2, @client.amem.summary.append(agent, " Prefers Ruby examples.")
      got = @client.amem.summary.get(agent)
      assert_includes got[:summary], "Ruby"
      assert_includes @client.amem.summary.list, agent
      assert_equal true, @client.amem.summary.drop(agent)
    end
  end

  def test_vsim_persistence_lifecycle
    skip_unless_licensed do
      index = uniq("vsimidx")
      snapshot = uniq("snap").tr(":.", "--") # snapshot names may not contain ":" or "."
      @client.vsim.createindex(index, 2)
      @client.vsim.set(index, "v1", [0.1, 0.2])
      blob = "fake-snapshot-blob"
      assert_kind_of Integer, @client.vsim.save(snapshot, blob)
      assert_equal blob, @client.vsim.load(snapshot)
      assert_includes @client.vsim.list, snapshot
      assert_equal true, @client.vsim.drop(snapshot)
      @client.vsim.dropindex(index)
    end
  end
end
