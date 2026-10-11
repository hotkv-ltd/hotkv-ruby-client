# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"
require_relative "support/recording_client"

# Exact wire argument lists for the token usage options and their
# combinations (the token usage group on SCACHE.SET,
# PCACHE.SET, every keyed cache SET and LLMBUDGET.CONSUME; the new
# LLMSTATS.RECORD options; LLMSTATS.PRICE SET/GET/LIST/DEL), and parsing
# of canned replies, all against a RecordingClient instead of a live
# server.
class AICacheCommandArgsTest < HotKVUnitTest
  def usage
    HotKV::TokenUsage.new(model: "claude-sonnet-5", input_tokens: 100, output_tokens: 20,
                           cache_read_tokens: 5, cache_write_5m_tokens: 7, cache_write_1h_tokens: 9)
  end

  # -- SCACHE.SET -------------------------------------------------------

  def test_scache_set_without_usage_sends_no_usage_group
    client = RecordingClient.new(reply: "OK")
    HotKV::Namespaces::SCache.new(client).set("ns", "q", "r", [0.1, 0.2])
    assert_equal ["SCACHE.SET", "ns", "q", "r", 0.1, 0.2], client.last_call
  end

  def test_scache_set_with_ttl_and_usage
    client = RecordingClient.new(reply: "OK")
    HotKV::Namespaces::SCache.new(client).set("ns", "q", "r", [0.1, 0.2], ttl: 60, usage: usage)
    assert_equal(
      ["SCACHE.SET", "ns", "q", "r", 0.1, 0.2, "TTL", 60, "MODEL", "claude-sonnet-5", "INPUT", 100,
       "OUTPUT", 20, "CACHEREAD", 5, "CACHEWRITE5M", 7, "CACHEWRITE1H", 9],
      client.last_call
    )
  end

  def test_scache_stats_parses_usage_saved_fields
    reply = ["entries", 3, "hits", 2, "misses", 1, "hit_rate", "0.666667", "p50_us", 120,
             "usage_saved_requests", 2, "usage_saved_input_tokens", 200, "usage_saved_output_tokens", 40,
             "usage_saved_cache_read_tokens", 10, "usage_saved_cache_write_tokens", 5,
             "usage_saved_cost_usd", "0.000160"]
    client = RecordingClient.new(reply: reply)
    stats = HotKV::Namespaces::SCache.new(client).stats("ns")
    assert_in_delta 0.666667, stats[:hit_rate]
    assert_in_delta 0.000160, stats[:usage_saved_cost_usd]
    assert_equal 200, stats[:usage_saved_input_tokens]
  end

  # -- PCACHE.SET -------------------------------------------------------

  def test_pcache_set_without_usage_sends_no_usage_group
    client = RecordingClient.new(reply: "OK")
    HotKV::Namespaces::PCache.new(client).set("ns", "p", "r")
    assert_equal ["PCACHE.SET", "ns", "p", "r"], client.last_call
  end

  def test_pcache_set_with_ttl_meta_and_usage
    client = RecordingClient.new(reply: "OK")
    HotKV::Namespaces::PCache.new(client).set("ns", "p", "r", ttl: 60, meta: "{}", usage: usage)
    assert_equal(
      ["PCACHE.SET", "ns", "p", "r", "TTL", 60, "META", "{}", "MODEL", "claude-sonnet-5", "INPUT", 100,
       "OUTPUT", 20, "CACHEREAD", 5, "CACHEWRITE5M", 7, "CACHEWRITE1H", 9],
      client.last_call
    )
  end

  def test_pcache_set_with_only_a_usage_model_omits_zero_counts
    client = RecordingClient.new(reply: "OK")
    HotKV::Namespaces::PCache.new(client).set("ns", "p", "r", usage: HotKV::TokenUsage.new(model: "m"))
    assert_equal ["PCACHE.SET", "ns", "p", "r", "MODEL", "m"], client.last_call
  end

  def test_pcache_stats_parses_usage_saved_cost_usd_as_float
    reply = ["entries", 1, "hits", 0, "misses", 1, "evictions", 0, "memory_bytes", 100,
             "hit_rate", "0.0", "p50_ns", 1, "p95_ns", 2, "p99_ns", 3, "cost_saved_usd", "0.000000",
             "usage_saved_requests", 0, "usage_saved_input_tokens", 0, "usage_saved_output_tokens", 0,
             "usage_saved_cache_read_tokens", 0, "usage_saved_cache_write_tokens", 0,
             "usage_saved_cost_usd", "0.000000"]
    client = RecordingClient.new(reply: reply)
    stats = HotKV::Namespaces::PCache.new(client).stats("ns")
    assert_in_delta 0.0, stats[:usage_saved_cost_usd]
    assert_kind_of Float, stats[:usage_saved_cost_usd]
  end

  # -- Keyed caches (TOOL.CACHE/NCACHE/GUARD/RERANK share one engine) ---

  def test_keyed_cache_set_with_usage
    client = RecordingClient.new(reply: "OK")
    HotKV::Namespaces::KeyedCache.new(client, "TOOL.CACHE").set("ns", "k", "v", usage: usage)
    assert_equal(
      ["TOOL.CACHE.SET", "ns", "k", "v", "MODEL", "claude-sonnet-5", "INPUT", 100, "OUTPUT", 20,
       "CACHEREAD", 5, "CACHEWRITE5M", 7, "CACHEWRITE1H", 9],
      client.last_call
    )
  end

  def test_keyed_cache_set_ttl_meta_no_usage
    client = RecordingClient.new(reply: "OK")
    HotKV::Namespaces::KeyedCache.new(client, "GUARD").set("ns", "k", "v", ttl: 30, meta: "m")
    assert_equal ["GUARD.SET", "ns", "k", "v", "TTL", 30, "META", "m"], client.last_call
  end

  def test_keyed_cache_stats_parses_usage_saved_cost_usd
    reply = ["entries", 1, "hits", 1, "misses", 0, "evictions", 0, "memory_bytes", 10,
             "usage_saved_requests", 1, "usage_saved_input_tokens", 10, "usage_saved_output_tokens", 2,
             "usage_saved_cache_read_tokens", 0, "usage_saved_cache_write_tokens", 0,
             "usage_saved_cost_usd", "0.000030"]
    client = RecordingClient.new(reply: reply)
    stats = HotKV::Namespaces::KeyedCache.new(client, "NCACHE").stats("ns")
    assert_in_delta 0.000030, stats[:usage_saved_cost_usd]
  end

  # -- LLMSTATS.RECORD ---------------------------------------------------

  def test_llmstats_record_legacy_positional_only
    client = RecordingClient.new(reply: "OK")
    HotKV::Namespaces::LLMStats.new(client).record("b", 100, 20, 0, 0.01, 200)
    assert_equal ["LLMSTATS.RECORD", "b", 100, 20, 0, 0.01, 200], client.last_call
  end

  def test_llmstats_record_with_error_flag
    client = RecordingClient.new(reply: "OK")
    HotKV::Namespaces::LLMStats.new(client).record("b", 100, 20, 0, 0.01, 200, error: true)
    assert_equal ["LLMSTATS.RECORD", "b", 100, 20, 0, 0.01, 200, "ERROR", 1], client.last_call
  end

  def test_llmstats_record_with_model_and_cache_write_options
    client = RecordingClient.new(reply: "OK")
    HotKV::Namespaces::LLMStats.new(client).record(
      "b", 100, 20, 0, 0, 200, error: false, model: "claude-sonnet-5",
      cache_write_5m_tokens: 30, cache_write_1h_tokens: 40
    )
    assert_equal(
      ["LLMSTATS.RECORD", "b", 100, 20, 0, 0, 200, "ERROR", 0, "MODEL", "claude-sonnet-5",
       "CACHEWRITE5M", 30, "CACHEWRITE1H", 40],
      client.last_call
    )
  end

  def test_llmstats_get_parses_new_fields
    reply = ["requests", 1, "errors", 0, "input_tokens", 100, "output_tokens", 20, "cached_tokens", 0,
             "cost_usd", "0.002", "avg_latency_ms", "200.0", "requests_1m", 1, "tokens_1m", 120,
             "cost_usd_1m", "0.002", "cache_write_5m_tokens", 30, "cache_write_1h_tokens", 40,
             "unpriced_requests", 0]
    client = RecordingClient.new(reply: reply)
    stats = HotKV::Namespaces::LLMStats.new(client).get("b")
    assert_equal 30, stats[:cache_write_5m_tokens]
    assert_equal 40, stats[:cache_write_1h_tokens]
    assert_equal 0, stats[:unpriced_requests]
    assert_kind_of Float, stats[:cost_usd]
  end

  # -- LLMSTATS.PRICE -----------------------------------------------------

  def test_price_set_required_fields_only
    client = RecordingClient.new(reply: "OK")
    HotKV::Namespaces::LLMStats.new(client).price_set("m", 3, 15)
    assert_equal ["LLMSTATS.PRICE", "SET", "m", "INPUT", "3", "OUTPUT", "15"], client.last_call
  end

  def test_price_set_with_optional_cache_prices
    client = RecordingClient.new(reply: "OK")
    HotKV::Namespaces::LLMStats.new(client).price_set(
      "m", 3, 15, cache_read_usd_per_mtok: 0.3, cache_write_5m_usd_per_mtok: 3.75,
      cache_write_1h_usd_per_mtok: 6
    )
    assert_equal(
      ["LLMSTATS.PRICE", "SET", "m", "INPUT", "3", "OUTPUT", "15", "CACHEREAD", "0.3",
       "CACHEWRITE5M", "3.75", "CACHEWRITE1H", "6"],
      client.last_call
    )
  end

  def test_price_set_accepts_decimal_strings_unchanged
    client = RecordingClient.new(reply: "OK")
    HotKV::Namespaces::LLMStats.new(client).price_set("m", "3", "15.000001")
    assert_equal ["LLMSTATS.PRICE", "SET", "m", "INPUT", "3", "OUTPUT", "15.000001"], client.last_call
  end

  def test_price_get_argument_list
    client = RecordingClient.new(reply: %w[model m source unpriced priced 0 retired 0
                                            input_usd_per_mtok 0.000000 output_usd_per_mtok 0.000000
                                            cache_read_usd_per_mtok 0.000000 cache_write_5m_usd_per_mtok
                                            0.000000 cache_write_1h_usd_per_mtok 0.000000])
    HotKV::Namespaces::LLMStats.new(client).price_get("m")
    assert_equal ["LLMSTATS.PRICE", "GET", "m"], client.last_call
  end

  def test_price_list_parses_array_of_entries
    entry = ["model", "m", "source", "default", "priced", 1, "retired", 0,
             "input_usd_per_mtok", "3.000000", "output_usd_per_mtok", "15.000000",
             "cache_read_usd_per_mtok", "0.300000", "cache_write_5m_usd_per_mtok", "3.750000",
             "cache_write_1h_usd_per_mtok", "6.000000"]
    client = RecordingClient.new(reply: [entry, entry])
    list = HotKV::Namespaces::LLMStats.new(client).price_list
    assert_equal ["LLMSTATS.PRICE", "LIST"], client.last_call
    assert_equal 2, list.length
    assert_kind_of HotKV::LLMPrice, list.first
    assert_equal "m", list.first.model
  end

  def test_price_del_argument_list_and_bool_reply
    client = RecordingClient.new(reply: 1)
    result = HotKV::Namespaces::LLMStats.new(client).price_del("m")
    assert_equal ["LLMSTATS.PRICE", "DEL", "m"], client.last_call
    assert_equal true, result
  end

  # -- LLMBUDGET.CONSUME --------------------------------------------------

  def test_llmbudget_consume_legacy_positional
    client = RecordingClient.new(reply: 1)
    HotKV::Namespaces::LLMBudget.new(client).consume("b", 100, 0.01)
    assert_equal ["LLMBUDGET.CONSUME", "b", 100, 0.01], client.last_call
  end

  def test_llmbudget_consume_with_usage_sends_zero_positional_tokens_and_cost
    client = RecordingClient.new(reply: 1)
    HotKV::Namespaces::LLMBudget.new(client).consume("b", usage: usage)
    assert_equal(
      ["LLMBUDGET.CONSUME", "b", 0, 0.0, "MODEL", "claude-sonnet-5", "INPUT", 100, "OUTPUT", 20,
       "CACHEREAD", 5, "CACHEWRITE5M", 7, "CACHEWRITE1H", 9],
      client.last_call
    )
  end

  def test_llmbudget_status_parses_unpriced_requests
    reply = ["tokens_used", 100, "token_limit", 1000, "cost_used_usd", "0.01", "cost_limit_usd", "5.0",
             "window_seconds", 3600, "window_remaining", 1800, "requests_allowed", 1,
             "requests_rejected", 0, "unpriced_requests", 0]
    client = RecordingClient.new(reply: reply)
    status = HotKV::Namespaces::LLMBudget.new(client).status("b")
    assert_equal 0, status[:unpriced_requests]
    assert_kind_of Float, status[:cost_used_usd]
  end
end
