# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

# Floats go out as plain decimal text (HotKV::Wire.float), never Ruby's
# exponent form. Verifies tiny, huge, negative and infinite values against a
# real server through the core commands that take floats.
class NumericFormatIntegrationTest < HotKVIntegrationTest
  def test_zadd_with_tiny_huge_negative_and_integral_scores
    k = track(uniq("numfmt"))
    assert_equal 6, @client.zadd(k, 1.0e-05, "tiny", 1.0e21, "huge", -2.5e-07, "negtiny", -1.0e16, "neghuge",
                                  5.0, "integral", 0.1 + 0.2, "sum")
    assert_equal 1.0e-05, @client.zscore(k, "tiny")
    assert_equal 1.0e21, @client.zscore(k, "huge")
    assert_equal(-2.5e-07, @client.zscore(k, "negtiny"))
    assert_equal(-1.0e16, @client.zscore(k, "neghuge"))
    assert_equal 5.0, @client.zscore(k, "integral")
    assert_equal 0.1 + 0.2, @client.zscore(k, "sum")
    assert_equal %w[neghuge negtiny tiny sum integral huge], @client.zrange(k, 0, -1)
  end

  def test_zadd_infinite_scores_and_float_bounds
    k = track(uniq("numfmt"))
    assert_equal 3, @client.zadd(k, Float::INFINITY, "top", -Float::INFINITY, "bottom", 0, "zero")
    assert_equal Float::INFINITY, @client.zscore(k, "top")
    assert_equal(-Float::INFINITY, @client.zscore(k, "bottom"))
    assert_equal %w[bottom zero], @client.zrangebyscore(k, -Float::INFINITY, 1.0e-05)
    assert_equal %w[zero top], @client.zrangebyscore(k, -1.0e-05, Float::INFINITY)
    assert_equal ["zero"], @client.zrangebyscore(k, -1.0e-05, 1.0e-05)
  end

  def test_zincrby_tiny_increments_accumulate
    k = track(uniq("numfmt"))
    @client.zadd(k, 0, "m")
    3.times { @client.zincrby(k, 1.0e-05, "m") }
    assert_in_delta 3.0e-05, @client.zscore(k, "m"), 1.0e-12
  end

  def test_incrbyfloat_tiny_huge_and_negative
    k = track(uniq("numfmt"))
    assert_equal 1.0e-05, @client.incrbyfloat(k, 1.0e-05)
    assert_equal "0.00001", @client.get(k)
    assert_in_delta 2.0e-05, @client.incrbyfloat(k, 1.0e-05), 1.0e-12
    k2 = track(uniq("numfmt"))
    assert_equal 1.0e21, @client.incrbyfloat(k2, 1.0e21)
    assert_equal(-9.0e20, @client.incrbyfloat(k2, -1.9e21))
    k3 = track(uniq("numfmt"))
    assert_equal 5.0, @client.incrbyfloat(k3, 5.0)
    assert_equal 4.5, @client.incrbyfloat(k3, -0.5)
  end

  def test_incrbyfloat_refuses_infinity_client_side
    k = track(uniq("numfmt"))
    assert_raises(HotKV::Error::ArgumentError) { @client.incrbyfloat(k, Float::INFINITY) }
    assert_raises(HotKV::Error::ArgumentError) { @client.incrbyfloat(k, Float::NAN) }
    assert_nil @client.get(k)
  end

  def test_hincrbyfloat_tiny_and_huge
    k = track(uniq("numfmt"))
    assert_equal 2.5e-06, @client.hincrbyfloat(k, "f", 2.5e-06)
    assert_equal "0.0000025", @client.hget(k, "f")
    assert_equal 1.0e20, @client.hincrbyfloat(k, "g", 1.0e20)
  end

  def test_geoadd_with_tiny_coordinates_and_geosearch_with_float_radius
    k = track(uniq("numfmt"))
    assert_equal 2, @client.geoadd(k, [[1.0e-05, 1.0e-05, "origin"], [-1.0e-05, -1.0e-05, "negorigin"]])
    pos = @client.geopos(k, "origin")
    assert_in_delta 1.0e-05, pos[0][0], 1.0e-05
    found = @client.geosearch(k, lonlat: [0.0, 0.0], radius: [1.0e+07, "m"], asc: true)
    assert_equal 2, found.length
    near = @client.geosearch(k, lonlat: [0.0, 0.0], radius: [1.0e-03, "m"])
    assert_equal [], near
  end

  def test_blocking_pop_accepts_a_fractional_timeout
    k = track(uniq("numfmt"))
    assert_nil @client.blpop(k, timeout: 0.05)
  end
end
