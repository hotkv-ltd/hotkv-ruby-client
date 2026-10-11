# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class GeoIntegrationTest < HotKVIntegrationTest
  def seed(key)
    @client.geoadd(key, [[13.361389, 38.115556, "Palermo"], [15.087269, 37.502669, "Catania"]])
  end

  def test_geoadd_geopos_geodist_geohash
    k = track(uniq("geo"))
    assert_equal 2, seed(k)
    pos = @client.geopos(k, "Palermo", "Catania")
    assert_in_delta 13.361389, pos[0][0], 0.001
    assert_in_delta 38.115556, pos[0][1], 0.001
    dist = @client.geodist(k, "Palermo", "Catania", unit: "km")
    assert_in_delta 166.27, dist, 2.0
    hashes = @client.geohash(k, "Palermo")
    refute_empty hashes.first
  end

  def test_geoadd_nx_xx_ch
    k = track(uniq("geo"))
    seed(k)
    assert_equal 0, @client.geoadd(k, [[13.4, 38.1, "Palermo"]], nx: true)
    assert_equal 1, @client.geoadd(k, [[13.4, 38.1, "Palermo"]], xx: true, ch: true)
  end

  def test_geosearch_by_radius_and_box
    k = track(uniq("geo"))
    seed(k)
    result = @client.geosearch(k, member: "Palermo", radius: [200, "km"], withdist: true, withcoord: true)
    names = result.map { |r| r[:member] }
    assert_includes names, "Catania"
    entry = result.find { |r| r[:member] == "Catania" }
    assert_kind_of Float, entry[:dist]
    assert_kind_of Array, entry[:coord]

    result2 = @client.geosearch(k, lonlat: [15, 37], box: [400, 400, "km"])
    assert_includes result2, "Catania"
  end

  def test_geosearchstore
    k, dest = track(uniq("geo"), uniq("geo"))
    seed(k)
    count = @client.geosearchstore(dest, k, member: "Palermo", radius: [200, "km"])
    assert_equal 2, count
    assert_equal 1, @client.geopos(dest, "Catania").compact.length
  end
end
