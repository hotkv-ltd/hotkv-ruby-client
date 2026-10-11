# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class LLMPriceTest < HotKVUnitTest
  RESP2_FIELDS = [
    "model", "claude-sonnet-5", "source", "custom", "priced", 1, "retired", 0,
    "input_usd_per_mtok", "3.000000", "output_usd_per_mtok", "15.000000",
    "cache_read_usd_per_mtok", "0.300000", "cache_write_5m_usd_per_mtok", "3.750000",
    "cache_write_1h_usd_per_mtok", "6.000000"
  ].freeze

  def parse(reply)
    fields = HotKV::Commands::Support.pairs_to_h(reply, float_keys: HotKV::LLMPrice::FLOAT_FIELDS)
    HotKV::LLMPrice.from_fields(fields)
  end

  def test_parses_resp2_flat_array_by_field_name
    price = parse(RESP2_FIELDS)
    assert_equal "claude-sonnet-5", price.model
    assert_equal "custom", price.source
    assert_equal true, price.priced
    assert_equal false, price.retired
    assert_in_delta 3.0, price.input_usd_per_mtok
    assert_in_delta 15.0, price.output_usd_per_mtok
    assert_in_delta 0.3, price.cache_read_usd_per_mtok
    assert_in_delta 3.75, price.cache_write_5m_usd_per_mtok
    assert_in_delta 6.0, price.cache_write_1h_usd_per_mtok
  end

  def test_parses_resp3_map_reply_identically
    hash_reply = RESP2_FIELDS.each_slice(2).to_h
    assert_equal parse(RESP2_FIELDS), parse(hash_reply)
  end

  def test_unpriced_model_defaults
    fields = ["model", "unknown-model", "source", "unpriced", "priced", 0, "retired", 0,
              "input_usd_per_mtok", "0.000000", "output_usd_per_mtok", "0.000000",
              "cache_read_usd_per_mtok", "0.000000", "cache_write_5m_usd_per_mtok", "0.000000",
              "cache_write_1h_usd_per_mtok", "0.000000"]
    price = parse(fields)
    assert_equal "unpriced", price.source
    assert_equal false, price.priced
    assert_in_delta 0.0, price.input_usd_per_mtok
  end

  def test_missing_fields_default
    price = HotKV::LLMPrice.from_fields({ model: "m" })
    assert_equal "m", price.model
    assert_equal "", price.source
    assert_equal false, price.priced
    assert_equal false, price.retired
    assert_in_delta 0.0, price.input_usd_per_mtok
  end

  def test_unknown_extra_field_is_ignored_not_raised
    price = parse(RESP2_FIELDS + ["brand_new_field", "x"])
    assert_equal "claude-sonnet-5", price.model
  end

  def test_format_price_passes_strings_through_unchanged
    assert_equal "15.000001", HotKV::LLMPrice.format_price("15.000001")
  end

  def test_format_price_formats_integers_and_floats_without_exponent_or_trailing_zeros
    assert_equal "3", HotKV::LLMPrice.format_price(3)
    assert_equal "0.3", HotKV::LLMPrice.format_price(0.30)
    assert_equal "15.000001", HotKV::LLMPrice.format_price(15.000001)
    assert_equal "0", HotKV::LLMPrice.format_price(0)
    assert_equal "100", HotKV::LLMPrice.format_price(100)
  end
end
