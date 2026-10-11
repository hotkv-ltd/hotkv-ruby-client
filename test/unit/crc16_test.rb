# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class CRC16Test < HotKVUnitTest
  include HotKV::Cluster::CRC16

  def test_raw_crc16_xmodem_check_vector
    assert_equal 0x31C3, crc16("123456789")
  end

  KEY_SLOT_VECTORS = {
    "foo" => 12_182,
    "bar" => 5_061,
    "hello" => 866,
    "{user1000}.following" => 3_443,
    "{user1000}.followers" => 3_443,
    "{}foo" => 9_500,
    "foo{}{bar}" => 8_363,
    "foo{{bar}}zap" => 4_015,
    "foo{bar}{zap}" => 5_061
  }.freeze

  KEY_SLOT_VECTORS.each do |key, expected_slot|
    define_method("test_key_slot_#{key.gsub(/[^a-zA-Z0-9]/, '_')}") do
      assert_equal expected_slot, key_slot(key)
    end
  end

  def test_hash_tagged_keys_share_a_slot
    assert_equal key_slot("{user1000}.following"), key_slot("{user1000}.followers")
  end

  def test_slot_is_always_in_range
    100.times do |i|
      slot = key_slot("random-key-#{i}")
      assert_operator slot, :>=, 0
      assert_operator slot, :<, HotKV::Cluster::CRC16::SLOT_COUNT
    end
  end

  def test_hash_tag_extraction
    assert_equal "bar", hash_tag("foo{bar}")
    assert_equal "{bar", hash_tag("foo{{bar}}zap") # tag is between the first { and the next }
    assert_equal "{}foo", hash_tag("{}foo") # empty tag falls back to the whole key
    assert_equal "foo", hash_tag("foo") # no braces at all
  end
end
