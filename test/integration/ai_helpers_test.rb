# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class AIHelpersIntegrationTest < HotKVIntegrationTest
  def test_semantic_cache_miss_then_hit
    skip_unless_licensed do
      calls = 0
      cache = HotKV::AI::SemanticCache.new(@client, dims: 3, namespace: uniq("sc"), threshold: 0.8)

      result1 = cache.get_or_call("What is HotKV?", [0.1, 0.2, 0.3]) do
        calls += 1
        "HotKV is an in-memory data store."
      end
      assert_equal false, result1[:cache_hit]
      assert_equal "HotKV is an in-memory data store.", result1[:response]
      assert_equal 1, calls

      result2 = cache.get_or_call("What is HotKV?", [0.1, 0.2, 0.3]) do
        calls += 1
        "should not run"
      end
      assert_equal true, result2[:cache_hit]
      assert_equal "HotKV is an in-memory data store.", result2[:response]
      assert_kind_of Float, result2[:similarity]
      assert_equal 1, calls # block never called again

      stats = cache.stats
      assert_operator stats[:hits], :>=, 1
      assert_operator stats[:misses], :>=, 1
    end
  end

  def test_semantic_cache_miss_below_threshold_calls_block_again
    skip_unless_licensed do
      cache = HotKV::AI::SemanticCache.new(@client, dims: 3, namespace: uniq("sc"), threshold: 0.99)
      cache.get_or_call("query one", [1.0, 0.0, 0.0]) { "answer one" }
      result = cache.get_or_call("totally different", [0.0, 1.0, 0.0]) { "answer two" }
      assert_equal false, result[:cache_hit]
      assert_equal "answer two", result[:response]
    end
  end

  def test_semantic_cache_get_or_call_reports_usage_on_a_later_hit
    skip_unless_licensed do
      cache = HotKV::AI::SemanticCache.new(@client, dims: 3, namespace: uniq("sc"), threshold: 0.8)
      usage = HotKV::TokenUsage.new(model: "claude-sonnet-5", input_tokens: 100, output_tokens: 20)

      cache.get_or_call("What is HotKV?", [0.1, 0.2, 0.3]) { ["HotKV is an in-memory data store.", usage] }
      cache.get_or_call("What is HotKV?", [0.1, 0.2, 0.3]) { "should not run" } # attribute the hit

      stats = cache.stats
      assert_operator stats[:usage_saved_requests], :>=, 1
      assert_operator stats[:usage_saved_input_tokens], :>=, 100
    end
  end

  def test_prompt_cache_get_or_call_uses_deterministic_key
    key = HotKV::AI::PromptCache.cache_key(provider: "openai", model: "gpt-4o",
                                            messages: [{ role: "user", content: "hi" }])
    assert_equal 64, key.length

    cache = HotKV::AI::PromptCache.new(@client, namespace: uniq("pc"))
    skip_unless_licensed do
      calls = 0
      r1 = cache.get_or_call(provider: "openai", model: "gpt-4o",
                              messages: [{ role: "user", content: "hi" }]) do
        calls += 1
        "hello there"
      end
      assert_equal false, r1[:cache_hit]
      assert_equal key, r1[:cache_key]

      r2 = cache.get_or_call(provider: "openai", model: "gpt-4o",
                              messages: [{ role: "user", content: "hi" }]) do
        calls += 1
        "should not run"
      end
      assert_equal true, r2[:cache_hit]
      assert_equal "hello there", r2[:response]
      assert_equal 1, calls

      stats = cache.stats
      assert_operator stats[:entries], :>=, 1
    end
  end

  def test_prompt_cache_record_usage_pushes_to_llmstats
    bucket = uniq("pc-bucket")
    cache = HotKV::AI::PromptCache.new(@client, namespace: uniq("pc"), stats_bucket: bucket)
    skip_unless_licensed do
      cache.record_usage(input_tokens: 100, output_tokens: 50, cost_usd: 0.01, latency_ms: 200)
      stats = @client.llmstats.get(bucket)
      assert_equal 1, stats[:requests]
      assert_equal 100, stats[:input_tokens]
    end
  end

  def test_prompt_cache_record_usage_with_model_is_priced_by_the_server
    bucket = uniq("pc-bucket-model")
    cache = HotKV::AI::PromptCache.new(@client, namespace: uniq("pc"), stats_bucket: bucket)
    skip_unless_licensed do
      cache.record_usage(input_tokens: 100, output_tokens: 20, latency_ms: 150, model: "claude-sonnet-5")
      stats = @client.llmstats.get(bucket)
      assert_equal 1, stats[:requests]
      assert_operator stats[:cost_usd], :>, 0.0
    end
  end

  def test_prompt_cache_get_or_call_reports_usage_on_a_later_hit
    cache = HotKV::AI::PromptCache.new(@client, namespace: uniq("pc"))
    skip_unless_licensed do
      usage = HotKV::TokenUsage.new(model: "claude-sonnet-5", input_tokens: 100, output_tokens: 20)
      messages = [{ role: "user", content: "usage test" }]

      cache.get_or_call(provider: "anthropic", model: "claude-sonnet-5", messages: messages) do
        ["hello there", usage]
      end
      cache.get_or_call(provider: "anthropic", model: "claude-sonnet-5", messages: messages) do
        "should not run"
      end # attribute the hit

      stats = cache.stats
      assert_operator stats[:usage_saved_requests], :>=, 1
      assert_operator stats[:usage_saved_input_tokens], :>=, 100
      assert_operator stats[:usage_saved_output_tokens], :>=, 20
    end
  end
end
