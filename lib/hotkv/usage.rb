# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  # One model call's token usage: the token usage group shared by
  # PCACHE.SET, SCACHE.SET, every keyed cache SET (TOOL.CACHE/NCACHE/
  # GUARD/RERANK) and LLMBUDGET.CONSUME.
  #
  # Recording a TokenUsage with a cache entry lets a later cache hit
  # attribute its tokens, and once the model is priced its exact cost, to
  # the namespace's usage_saved_* stats fields.
  #
  # +model+ is required; every count defaults to 0 and is left off the
  # wire when zero (MODEL itself is always sent once a TokenUsage is
  # given):
  #
  #   usage = HotKV::TokenUsage.new(model: "claude-sonnet-5", input_tokens: 120, output_tokens: 40)
  #   client.pcache.set(ns, prompt, response, usage: usage)
  TokenUsage = Struct.new(
    :model, :input_tokens, :output_tokens, :cache_read_tokens, :cache_write_5m_tokens,
    :cache_write_1h_tokens,
    keyword_init: true
  ) do
    def initialize(model:, input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
                   cache_write_5m_tokens: 0, cache_write_1h_tokens: 0)
      super
    end

    # The `MODEL <model> [INPUT n] [OUTPUT n] [CACHEREAD n] [CACHEWRITE5M
    # n] [CACHEWRITE1H n]` KEY VALUE pairs this usage adds to a command's
    # trailing options.
    def wire_args
      args = ["MODEL", model]
      args.push("INPUT", input_tokens) unless input_tokens.zero?
      args.push("OUTPUT", output_tokens) unless output_tokens.zero?
      args.push("CACHEREAD", cache_read_tokens) unless cache_read_tokens.zero?
      args.push("CACHEWRITE5M", cache_write_5m_tokens) unless cache_write_5m_tokens.zero?
      args.push("CACHEWRITE1H", cache_write_1h_tokens) unless cache_write_1h_tokens.zero?
      args
    end
  end
end
