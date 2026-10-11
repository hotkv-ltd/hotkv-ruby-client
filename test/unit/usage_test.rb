# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class TokenUsageTest < HotKVUnitTest
  def test_model_only_sends_just_model
    usage = HotKV::TokenUsage.new(model: "claude-sonnet-5")
    assert_equal ["MODEL", "claude-sonnet-5"], usage.wire_args
  end

  def test_zero_counts_are_omitted_from_the_wire
    usage = HotKV::TokenUsage.new(model: "claude-sonnet-5", input_tokens: 0, output_tokens: 0,
                                   cache_read_tokens: 0, cache_write_5m_tokens: 0, cache_write_1h_tokens: 0)
    assert_equal ["MODEL", "claude-sonnet-5"], usage.wire_args
  end

  def test_non_zero_counts_are_included_in_order
    usage = HotKV::TokenUsage.new(model: "claude-sonnet-5", input_tokens: 100, output_tokens: 20,
                                   cache_read_tokens: 5, cache_write_5m_tokens: 7, cache_write_1h_tokens: 9)
    assert_equal(
      ["MODEL", "claude-sonnet-5", "INPUT", 100, "OUTPUT", 20, "CACHEREAD", 5, "CACHEWRITE5M", 7,
       "CACHEWRITE1H", 9],
      usage.wire_args
    )
  end

  def test_a_single_non_zero_count_is_included_alone
    usage = HotKV::TokenUsage.new(model: "m", cache_write_1h_tokens: 3)
    assert_equal ["MODEL", "m", "CACHEWRITE1H", 3], usage.wire_args
  end

  def test_model_is_required
    assert_raises(ArgumentError) { HotKV::TokenUsage.new(input_tokens: 5) }
  end

  def test_counts_default_to_zero
    usage = HotKV::TokenUsage.new(model: "m")
    assert_equal 0, usage.input_tokens
    assert_equal 0, usage.output_tokens
    assert_equal 0, usage.cache_read_tokens
    assert_equal 0, usage.cache_write_5m_tokens
    assert_equal 0, usage.cache_write_1h_tokens
  end
end
