# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"
require_relative "support/recording_client"

class CallResultSplitUsageTest < HotKVUnitTest
  def test_plain_response_has_no_usage
    response, usage = HotKV::AI::CallResult.split_usage("hello")
    assert_equal "hello", response
    assert_nil usage
  end

  def test_response_usage_pair_is_split
    tu = HotKV::TokenUsage.new(model: "m")
    response, usage = HotKV::AI::CallResult.split_usage(["hello", tu])
    assert_equal "hello", response
    assert_same tu, usage
  end

  def test_a_two_element_array_response_without_a_token_usage_is_not_mistaken_for_a_pair
    response, usage = HotKV::AI::CallResult.split_usage(%w[a b])
    assert_equal %w[a b], response
    assert_nil usage
  end
end

class PromptCacheUsageTest < HotKVUnitTest
  def test_get_or_call_forwards_usage_from_block_pair_on_a_miss
    client = RecordingClient.new(reply: nil) # PCACHE.CREATE / PCACHE.GET (miss) / PCACHE.SET
    cache = HotKV::AI::PromptCache.new(client, namespace: "ns")
    usage = HotKV::TokenUsage.new(model: "claude-sonnet-5", input_tokens: 10, output_tokens: 2)

    result = cache.get_or_call(provider: "anthropic", model: "claude-sonnet-5",
                                messages: [{ role: "user", content: "hi" }]) do
      ["hello there", usage]
    end

    assert_equal false, result[:cache_hit]
    set_call = client.calls.find { |c| c.first == "PCACHE.SET" }
    refute_nil set_call
    assert_includes set_call, "MODEL"
    assert_equal "claude-sonnet-5", set_call[set_call.index("MODEL") + 1]
    assert_includes set_call, "INPUT"
  end

  def test_get_or_call_without_usage_sends_no_usage_group
    client = RecordingClient.new(reply: nil)
    cache = HotKV::AI::PromptCache.new(client, namespace: "ns")

    cache.get_or_call(provider: "anthropic", model: "claude-sonnet-5",
                       messages: [{ role: "user", content: "hi" }]) { "hello there" }

    set_call = client.calls.find { |c| c.first == "PCACHE.SET" }
    refute_includes set_call, "MODEL"
  end

  def test_record_usage_forwards_model_and_cache_write_options
    client = RecordingClient.new(reply: "OK")
    cache = HotKV::AI::PromptCache.new(client, namespace: "ns", stats_bucket: "bucket1")
    cache.record_usage(input_tokens: 100, output_tokens: 20, model: "claude-sonnet-5",
                        cache_write_5m_tokens: 5, cache_write_1h_tokens: 0)
    record_call = client.calls.find { |c| c.first == "LLMSTATS.RECORD" }
    assert_includes record_call, "MODEL"
    assert_includes record_call, "CACHEWRITE5M"
  end
end

class SemanticCacheUsageTest < HotKVUnitTest
  def test_get_or_call_forwards_usage_from_block_pair_on_a_miss
    client = RecordingClient.new(reply: nil) # SCACHE.CREATE / SCACHE.GET (miss) / SCACHE.SET
    cache = HotKV::AI::SemanticCache.new(client, dims: 2, namespace: "ns")
    usage = HotKV::TokenUsage.new(model: "claude-sonnet-5", input_tokens: 10)

    result = cache.get_or_call("question", [0.1, 0.2]) { ["answer", usage] }

    assert_equal false, result[:cache_hit]
    set_call = client.calls.find { |c| c.first == "SCACHE.SET" }
    refute_nil set_call
    assert_includes set_call, "MODEL"
  end
end
