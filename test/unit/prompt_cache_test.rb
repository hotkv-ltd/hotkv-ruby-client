# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"
require "digest"

class PromptCacheKeyTest < HotKVUnitTest
  def test_canonical_json_key_order_and_defaults
    json = HotKV::AI::PromptCache.canonical_json(provider: "openai", model: "gpt-4o", messages: [])
    assert_equal '{"provider":"openai","model":"gpt-4o","system":"","messages":[],"params":{}}', json
  end

  def test_canonical_json_is_compact_no_insignificant_whitespace
    json = HotKV::AI::PromptCache.canonical_json(
      provider: "openai", model: "gpt-4o", system: "be terse",
      messages: [{ role: "user", content: "hi" }], params: { "temperature" => "0.7" }
    )
    refute_match(/:\s|,\s/, json)
  end

  def test_message_keys_are_role_then_content_in_caller_order
    json = HotKV::AI::PromptCache.canonical_json(
      provider: "p", model: "m",
      messages: [{ role: "user", content: "first" }, { role: "assistant", content: "second" }]
    )
    assert_equal(
      '{"provider":"p","model":"m","system":"","messages":' \
      '[{"role":"user","content":"first"},{"role":"assistant","content":"second"}],"params":{}}', json
    )
  end

  def test_messages_accept_string_keyed_hashes_too
    json_sym = HotKV::AI::PromptCache.canonical_json(provider: "p", model: "m",
                                                       messages: [{ role: "user", content: "hi" }])
    json_str = HotKV::AI::PromptCache.canonical_json(provider: "p", model: "m",
                                                       messages: [{ "role" => "user", "content" => "hi" }])
    assert_equal json_sym, json_str
  end

  def test_params_are_sorted_by_byte_value_ascending
    json = HotKV::AI::PromptCache.canonical_json(
      provider: "p", model: "m", messages: [], params: { "b" => "2", "Z" => "1", "a" => "3" }
    )
    assert_equal '{"provider":"p","model":"m","system":"","messages":[],"params":{"Z":"1","a":"3","b":"2"}}', json
  end

  def test_params_key_order_does_not_affect_the_key
    key1 = HotKV::AI::PromptCache.cache_key(provider: "p", model: "m", messages: [],
                                             params: { "a" => "1", "b" => "2" })
    key2 = HotKV::AI::PromptCache.cache_key(provider: "p", model: "m", messages: [],
                                             params: { "b" => "2", "a" => "1" })
    assert_equal key1, key2
  end

  def test_non_string_param_value_raises
    assert_raises(HotKV::Error::ArgumentError) do
      HotKV::AI::PromptCache.canonical_json(provider: "p", model: "m", messages: [], params: { "temperature" => 0.7 })
    end
  end

  def test_non_ascii_characters_kept_literal_not_escaped
    json = HotKV::AI::PromptCache.canonical_json(provider: "p", model: "m",
                                                   messages: [{ role: "user", content: "café 中文" }])
    assert_includes json, "café 中文"
    refute_match(/\\u00e9|\\u4e2d/, json)
  end

  def test_control_characters_are_escaped_as_u_escapes
    json = HotKV::AI::PromptCache.canonical_json(provider: "p", model: "m",
                                                   messages: [{ role: "user", content: "a\u0001b" }])
    assert_includes json, '\u0001'
  end

  def test_cache_key_is_lowercase_hex_sha256_of_canonical_json
    json = HotKV::AI::PromptCache.canonical_json(provider: "openai", model: "gpt-4o",
                                                   messages: [{ role: "user", content: "hi" }])
    key = HotKV::AI::PromptCache.cache_key(provider: "openai", model: "gpt-4o",
                                            messages: [{ role: "user", content: "hi" }])
    assert_equal 64, key.length
    assert_match(/\A[0-9a-f]{64}\z/, key)
    assert_equal Digest::SHA256.hexdigest(json), key
  end

  def test_cache_key_changes_when_any_field_changes
    base = { provider: "openai", model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
    baseline = HotKV::AI::PromptCache.cache_key(**base)

    refute_equal baseline, HotKV::AI::PromptCache.cache_key(**base.merge(model: "gpt-4o-mini"))
    refute_equal baseline, HotKV::AI::PromptCache.cache_key(**base.merge(system: "be terse"))
    refute_equal baseline,
                 HotKV::AI::PromptCache.cache_key(**base.merge(messages: [{ role: "user", content: "hi!" }]))
    refute_equal baseline, HotKV::AI::PromptCache.cache_key(**base.merge(params: { "temperature" => "0.7" }))
  end

  def test_cache_key_is_deterministic_across_repeated_calls
    args = { provider: "anthropic", model: "claude-sonnet-5", system: "You are helpful.",
              messages: [{ role: "user", content: "Explain hash tags." }],
              params: { "max_tokens" => "512", "temperature" => "0.20" } }
    keys = Array.new(20) { HotKV::AI::PromptCache.cache_key(**args) }
    assert_equal 1, keys.uniq.length
  end
end
