# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"
require_relative "support/recording_client"
begin
  require "bigdecimal"
rescue LoadError
  nil # bigdecimal is a bundled gem from Ruby 3.4; the BigDecimal tests skip without it
end

# Numeric argument formatting. Ruby prints Float#to_s as "1.0e-05" for small
# and "1.0e+16" for large values; the server's fixed point USD parser (behind
# LLMBUDGET.SET and LLMSTATS.PRICE SET) accepts plain digits only, so every
# float the SDK sends must be plain decimal text.
class WireTest < HotKVUnitTest
  W = HotKV::Wire

  # -- Wire.float --

  def test_float_tiny_values_have_no_exponent
    assert_equal "0.00001", W.float(1.0e-05)
    assert_equal "0.000000001", W.float(1e-9)
    assert_equal "0.000000000000000000001", W.float(1e-21)
    assert_equal "0.0000123", W.float(1.23e-05)
    assert_equal "-0.00001", W.float(-1.0e-05)
  end

  def test_float_huge_values_have_no_exponent
    assert_equal "10000000000000000", W.float(1.0e16)
    assert_equal "1000000000000000000000", W.float(1e21)
    assert_equal "12300000000000000000000", W.float(1.23e22)
    assert_equal "-2500000000000000000000", W.float(-2.5e21)
    assert_equal 309, W.float(Float::MAX).length
    assert_equal "17976931348623157", W.float(Float::MAX)[0, 17]
  end

  def test_float_ordinary_values
    assert_equal "3.5", W.float(3.5)
    assert_equal "0.1", W.float(0.1)
    assert_equal "0.30000000000000004", W.float(0.1 + 0.2)
    assert_equal "123456.789", W.float(123_456.789)
    assert_equal "-42.25", W.float(-42.25)
  end

  def test_float_integral_values_have_no_trailing_zero
    assert_equal "5", W.float(5.0)
    assert_equal "-5", W.float(-5.0)
    assert_equal "0", W.float(0.0)
    assert_equal "100", W.float(100.0)
    assert_equal "1000000", W.float(1_000_000.0)
  end

  def test_float_negative_zero_is_zero
    assert_equal "0", W.float(-0.0)
  end

  def test_float_integers_and_rationals
    assert_equal "7", W.float(7)
    assert_equal "-7", W.float(-7)
    assert_equal "123456789012345678901234567890", W.float(123_456_789_012_345_678_901_234_567_890)
    assert_equal "0.5", W.float(Rational(1, 2))
    assert_equal "0.25", W.float(Rational(1, 4))
  end

  def test_float_bigdecimal
    skip "bigdecimal is not available" unless defined?(BigDecimal)
    assert_equal "0.00001", W.float(BigDecimal("1e-5"))
    assert_equal "123.456", W.float(BigDecimal("123.456"))
    assert_equal "100000000000000000000", W.float(BigDecimal("1e20"))
    assert_equal "-0.5", W.float(BigDecimal("-0.5"))
    assert_equal "0", W.float(BigDecimal("0"))
  end

  def test_float_infinity_is_inf
    assert_equal "inf", W.float(Float::INFINITY)
    assert_equal "-inf", W.float(-Float::INFINITY)
  end

  def test_float_nan_raises
    assert_raises(HotKV::Error::ArgumentError) { W.float(Float::NAN) }
    assert_raises(HotKV::Error::ArgumentError) { W.float(BigDecimal("NaN")) } if defined?(BigDecimal)
  end

  def test_float_rejects_non_numbers
    assert_raises(HotKV::Error::ArgumentError) { W.float("1.5") }
    assert_raises(HotKV::Error::ArgumentError) { W.float(nil) }
    assert_raises(HotKV::Error::ArgumentError) { W.float(Complex(1, 2)) }
  end

  def test_float_output_round_trips
    [0.1, 1e-300, 4.9e-324, 1.7976931348623157e308, 123.456e-7, 9_007_199_254_740_993.0, 0.000123, 2.5e-5].each do |f|
      assert_equal f, Float(W.float(f)), "round trip of #{f}"
      refute_match(/e/i, W.float(f))
    end
  end

  def test_float_ignores_locale_style_formatting
    # Kernel#format and String#% are not involved; the text is built from
    # digits only, so no thousands or decimal separator can ever appear.
    assert_equal "1234567.5", W.float(1_234_567.5)
  end

  # -- Wire.parse_float (replies) --

  def test_parse_float_reads_what_the_server_prints
    assert_equal 1.5, W.parse_float("1.5")
    assert_equal 1.0e-05, W.parse_float("1e-05")
    assert_equal(-2.0, W.parse_float("-2"))
    assert_equal Float::INFINITY, W.parse_float("inf")
    assert_equal Float::INFINITY, W.parse_float("+inf")
    assert_equal Float::INFINITY, W.parse_float("Infinity")
    assert_equal(-Float::INFINITY, W.parse_float("-inf"))
    assert_equal(-Float::INFINITY, W.parse_float("-Infinity"))
    assert W.parse_float("nan").nan?
    assert_equal 3.0, W.parse_float(3)
    assert_equal 2.5, W.parse_float(2.5)
  end

  def test_parse_float_rejects_garbage
    assert_raises(ArgumentError) { W.parse_float("abc") }
    assert_raises(TypeError) { W.parse_float(nil) }
  end

  def test_typed_replies_parse_infinite_scores_from_a_resp2_string
    c = RecordingClient.new(reply: "inf")
    c.extend(HotKV::Commands::All)
    assert_equal Float::INFINITY, c.zscore("z", "m")
    assert_equal Float::INFINITY, c.zincrby("z", 1, "m")
    c2 = RecordingClient.new(reply: ["a", "-inf", "b", "inf"])
    c2.extend(HotKV::Commands::All)
    assert_equal [["a", -Float::INFINITY], ["b", Float::INFINITY]], c2.zrange("z", 0, -1, with_scores: true)
  end

  # -- Wire.finite --

  def test_finite_passes_numbers_and_non_numbers_through
    assert_equal 1.5, W.finite(1.5)
    assert_equal 3, W.finite(3)
    assert_equal "0.5", W.finite("0.5")
    assert_nil W.finite(nil)
    assert_equal Rational(1, 3), W.finite(Rational(1, 3))
  end

  def test_finite_rejects_nan_and_infinity
    assert_raises(HotKV::Error::ArgumentError) { W.finite(Float::NAN) }
    assert_raises(HotKV::Error::ArgumentError) { W.finite(Float::INFINITY) }
    assert_raises(HotKV::Error::ArgumentError) { W.finite(-Float::INFINITY) }
  end

  def test_finite_vector
    assert_equal [0.1, 0.2], W.finite_vector([0.1, 0.2])
    assert_raises(HotKV::Error::ArgumentError) { W.finite_vector([0.1, Float::NAN]) }
  end

  def test_csv_vector_is_plain_decimal
    assert_equal "0.5,0.00001,1000000000000000000000,-3", W.csv_vector([0.5, 1.0e-05, 1e21, -3])
    assert_raises(HotKV::Error::ArgumentError) { W.csv_vector([1.0, Float::INFINITY]) }
  end

  # -- Wire.usd --

  def test_usd_plain_fixed_point
    assert_equal "0.00001", W.usd(1.0e-05)
    assert_equal "0.000001", W.usd(1.0e-06)
    assert_equal "5", W.usd(5.0)
    assert_equal "5", W.usd(5)
    assert_equal "0.5", W.usd(0.5)
    assert_equal "12.345678", W.usd(12.345678)
    assert_equal "0", W.usd(0)
    assert_equal "0", W.usd(0.0)
    assert_equal "1000000000", W.usd(1.0e9)
  end

  def test_usd_rounds_to_the_nearest_micro_dollar
    assert_equal "0.3", W.usd(0.1 + 0.2) # 0.30000000000000004
    assert_equal "1.234568", W.usd(1.2345678)
    assert_equal "2", W.usd(1.9999999)
  end

  def test_usd_strings_pass_through_for_the_server_to_judge
    assert_equal "15.000001", W.usd("15.000001")
    assert_equal "1e-5", W.usd("1e-5")
  end

  def test_usd_rejects_negative_nan_infinity
    assert_raises(HotKV::Error::ArgumentError) { W.usd(-0.5) }
    assert_raises(HotKV::Error::ArgumentError) { W.usd(-1) }
    assert_raises(HotKV::Error::ArgumentError) { W.usd(Float::NAN) }
    assert_raises(HotKV::Error::ArgumentError) { W.usd(Float::INFINITY) }
    assert_raises(HotKV::Error::ArgumentError) { W.usd(nil) }
  end

  def test_usd_refuses_a_non_zero_amount_that_would_round_to_zero
    # 0 means "no cost limit" to LLMBUDGET.SET, so silently turning 1e-9
    # into 0 would remove the cap.
    assert_raises(HotKV::Error::ArgumentError) { W.usd(1.0e-09) }
    assert_equal "0.000001", W.usd(5.0e-07)
  end

  def test_usd_bigdecimal_and_rational
    skip "bigdecimal is not available" unless defined?(BigDecimal)
    assert_equal "0.00001", W.usd(BigDecimal("0.00001"))
    assert_equal "0.25", W.usd(Rational(1, 4))
  end

  # -- wire encoding of numeric arguments --

  def encode(*args)
    HotKV::RESP.encode_command(args)
  end

  def bulk(text)
    "$#{text.bytesize}\r\n#{text}\r\n"
  end

  def test_encode_command_writes_floats_as_plain_decimal
    assert_equal "*4\r\n#{bulk('X')}#{bulk('0.00001')}#{bulk('10000000000000000')}#{bulk('-0.5')}",
                 encode("X", 1.0e-05, 1.0e16, -0.5)
  end

  def test_encode_command_writes_infinity_as_inf
    assert_equal "*3\r\n#{bulk('ZADD')}#{bulk('inf')}#{bulk('-inf')}", encode("ZADD", Float::INFINITY, -Float::INFINITY)
  end

  def test_encode_command_refuses_nan
    assert_raises(HotKV::Error::ArgumentError) { encode("ZADD", Float::NAN) }
  end

  def test_encode_command_leaves_strings_and_integers_alone
    assert_equal "*3\r\n#{bulk('X')}#{bulk('1e-5')}#{bulk('12')}", encode("X", "1e-5", 12)
  end

  # -- typed methods --

  def client
    @client ||= RecordingClient.new
  end

  def wire_of(call)
    call.map { |a| HotKV::RESP.to_wire_string(a) }
  end

  def test_llmbudget_set_sends_a_plain_decimal_cost_limit
    client.llmbudget.set("team", 1_000_000, 1.0e-05, 3600)
    assert_equal %w[LLMBUDGET.SET team 1000000 0.00001 3600], wire_of(client.last_call)
    client.llmbudget.set("team", 1_000_000, 25.5, 3600)
    assert_equal %w[LLMBUDGET.SET team 1000000 25.5 3600], wire_of(client.last_call)
    client.llmbudget.set("team", 0, 0, 60)
    assert_equal %w[LLMBUDGET.SET team 0 0 60], wire_of(client.last_call)
  end

  def test_llmbudget_set_refuses_values_the_server_would_misread
    assert_raises(HotKV::Error::ArgumentError) { client.llmbudget.set("t", 1, -1.0, 60) }
    assert_raises(HotKV::Error::ArgumentError) { client.llmbudget.set("t", 1, Float::NAN, 60) }
    assert_raises(HotKV::Error::ArgumentError) { client.llmbudget.set("t", 1, 1.0e-12, 60) }
  end

  def test_llmbudget_consume_cost_is_plain_decimal
    client.llmbudget.consume("team", 10, 2.5e-05)
    assert_equal %w[LLMBUDGET.CONSUME team 10 0.000025], wire_of(client.last_call)
    assert_raises(HotKV::Error::ArgumentError) { client.llmbudget.consume("team", 10, Float::INFINITY) }
  end

  def test_llmstats_record_cost_is_plain_decimal
    client.llmstats.record("b", 1, 2, 0, 1.5e-06, 30)
    assert_equal %w[LLMSTATS.RECORD b 1 2 0 0.0000015 30], wire_of(client.last_call)
  end

  def test_llmstats_price_set_prices_are_plain_decimal
    client.llmstats.price_set("m", 3.0, 1.5e-05, cache_read_usd_per_mtok: 0.3)
    assert_equal %w[LLMSTATS.PRICE SET m INPUT 3 OUTPUT 0.000015 CACHEREAD 0.3], wire_of(client.last_call)
  end

  def test_scache_thresholds_and_vectors_are_plain_decimal
    client.scache.create("ns", 3, threshold: 0.85)
    assert_equal %w[SCACHE.CREATE ns 3 THRESHOLD 0.85], wire_of(client.last_call)
    client.scache.set("ns", "q", "r", [1.0e-05, 0.5, -2.0e-07])
    assert_equal %w[SCACHE.SET ns q r 0.00001 0.5 -0.0000002], wire_of(client.last_call)
    client.scache.get("ns", [1.0e-05, 0.5, 1.0e+21], threshold: 1.0e-05)
    assert_equal %w[SCACHE.GET ns 0.00001 0.5 1000000000000000000000 THRESHOLD 0.00001], wire_of(client.last_call)
    client.scache.threshold("ns", 0.9)
    assert_equal %w[SCACHE.THRESHOLD ns 0.9], wire_of(client.last_call)
  end

  def test_scache_refuses_non_finite_components
    assert_raises(HotKV::Error::ArgumentError) { client.scache.set("ns", "q", "r", [1.0, Float::NAN]) }
    assert_raises(HotKV::Error::ArgumentError) { client.scache.get("ns", [Float::INFINITY]) }
    assert_raises(HotKV::Error::ArgumentError) { client.scache.threshold("ns", Float::NAN) }
  end

  def test_pcache_cost_per_hit_is_plain_decimal
    client.pcache.create("ns", cost_per_hit: 2.5e-05)
    assert_equal %w[PCACHE.CREATE ns COST_PER_HIT 0.000025], wire_of(client.last_call)
  end

  def test_ratelimit_rates_are_plain_decimal
    client.ratelimit.create("rl", 100, 1000, algo: "token_bucket", refill: 1.0e-05, drain: 2.5)
    assert_equal %w[RATELIMIT.CREATE rl 100 1000 ALGO token_bucket REFILL 0.00001 DRAIN 2.5], wire_of(client.last_call)
  end

  def test_ts_add_value_is_plain_decimal
    client.ts.add("k", 1.0e-07)
    assert_equal %w[TS.ADD k * 0.0000001], wire_of(client.last_call)
    client.ts.add("k", 1.0e+22, timestamp: 1000)
    assert_equal ["TS.ADD", "k", "1000", "10000000000000000000000"], wire_of(client.last_call)
    assert_raises(HotKV::Error::ArgumentError) { client.ts.add("k", Float::NAN) }
  end

  def test_vsim_vectors_are_plain_decimal
    rc = RecordingClient.new(reply: [])
    rc.vsim.set("idx", "k", [1.0e-05, 0.25])
    assert_equal %w[VSIM.SET idx k 0.00001 0.25], wire_of(rc.last_call)
    rc.vsim.search("idx", 3, [0.5, 1.0e-06])
    assert_equal %w[VSIM.SEARCH idx 3 0.5 0.000001], wire_of(rc.last_call)
  end

  def test_amem_vectors_are_plain_decimal
    rc = RecordingClient.new(reply: [])
    rc.amem.sem_store("a", "k", "c", [1.0e-05, 0.5])
    assert_equal %w[AMEM.SEM.STORE a k c 0.00001 0.5], wire_of(rc.last_call)
    rc.amem.sem_recall("a", 2, [1.0e-05])
    assert_equal %w[AMEM.SEM.RECALL a 2 0.00001], wire_of(rc.last_call)
    rc.amem.search("a", 2, [2.0e-07])
    assert_equal %w[AMEM.SEARCH a 2 0.0000002], wire_of(rc.last_call)
  end

  def test_rag_vectors_and_alpha_are_plain_decimal
    rc = RecordingClient.new(reply: [])
    rc.rag.ingest("p", "d", "text", vectors: [[1.0e-05, 0.5], [0.25, 1.0e+21]])
    assert_equal ["RAG.INGEST", "p", "d", "text", "VECTORS", "0.00001,0.5", "0.25,1000000000000000000000"],
                 wire_of(rc.last_call)
    rc.rag.search("p", "q", k: 3, alpha: 0.5, vector: [1.0e-05, 2])
    assert_equal %w[RAG.SEARCH p q K 3 ALPHA 0.5 VECTOR 0.00001,2], wire_of(rc.last_call)
  end

  def test_core_float_commands_are_plain_decimal
    # RecordingClient#invoke records instead of sending and feeds "1.5"
    # through each method's reply block.
    client = RecordingClient.new(reply: "1.5")
    client.extend(HotKV::Commands::All)
    client.incrbyfloat("k", 1.0e-05)
    assert_equal %w[INCRBYFLOAT k 0.00001], wire_of(client.last_call)
    client.incrbyfloat("k", -1.0e+21)
    assert_equal %w[INCRBYFLOAT k -1000000000000000000000], wire_of(client.last_call)
    assert_raises(HotKV::Error::ArgumentError) { client.incrbyfloat("k", Float::INFINITY) }
    client.hincrbyfloat("h", "f", 2.5e-06)
    assert_equal %w[HINCRBYFLOAT h f 0.0000025], wire_of(client.last_call)
    client.zadd("z", 1.0e-05, "a", Float::INFINITY, "b")
    assert_equal %w[ZADD z 0.00001 a inf b], wire_of(client.last_call)
    client.zadd("z", { "m" => -Float::INFINITY })
    assert_equal %w[ZADD z -inf m], wire_of(client.last_call)
    client.zincrby("z", 1.0e-10, "a")
    assert_equal %w[ZINCRBY z 0.0000000001 a], wire_of(client.last_call)
    client.zrangebyscore("z", -Float::INFINITY, 1.0e-05)
    assert_equal %w[ZRANGEBYSCORE z -inf 0.00001], wire_of(client.last_call)
    client.zrangebyscore("z", "(1", "+inf")
    assert_equal %w[ZRANGEBYSCORE z (1 +inf], wire_of(client.last_call)
    client.geoadd("g", [[13.361389, 38.115556, "Palermo"], [1.0e-05, -1.0e-05, "Tiny"]])
    assert_equal %w[GEOADD g 13.361389 38.115556 Palermo 0.00001 -0.00001 Tiny], wire_of(client.last_call)
    assert_raises(HotKV::Error::ArgumentError) { client.geoadd("g", [[Float::NAN, 1.0, "x"]]) }
    client.geosearch("g", lonlat: [1.0e-05, 2.5], radius: [1.0e+07, "m"])
    assert_equal %w[GEOSEARCH g FROMLONLAT 0.00001 2.5 BYRADIUS 10000000 m], wire_of(client.last_call)
  end
end
