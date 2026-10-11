# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require "json"
require "digest"

module HotKV
  module AI
    # Deterministic LLM prompt/response cache. Builds a cache key from
    # provider, model, the normalized messages/system prompt and
    # generation parameters, and wraps #get_or_call so the wrapped LLM
    # call only ever runs on a cache miss. Built on HotKV::Client#pcache.
    #
    # The key is the lowercase hex SHA-256 digest of a canonical, compact
    # JSON encoding of {provider, model, system, messages, params}. This
    # exact encoding (key order, compact separators, UTF-8 kept literal,
    # params sorted by byte value) is shared byte for byte by every
    # official HotKV SDK, so two different SDKs given the same logical
    # call always agree on the key.
    class PromptCache
      DEFAULT_NAMESPACE = "default"

      attr_reader :namespace, :stats_bucket

      # +stats_bucket+, if given, is used by #record_usage to push real
      # token/cost/latency numbers (which only the caller's LLM
      # integration knows) into LLMSTATS.
      def initialize(client, namespace: DEFAULT_NAMESPACE, stats_bucket: nil)
        @client = client
        @namespace = namespace
        @stats_bucket = stats_bucket
        @namespace_ready = false
        @bucket_ready = false
      end

      # Computes the canonical cache key without touching the server.
      def self.cache_key(provider:, model:, messages:, system: "", params: {})
        Digest::SHA256.hexdigest(canonical_json(provider: provider, model: model, messages: messages,
                                                 system: system, params: params))
      end

      def self.canonical_json(provider:, model:, messages:, system: "", params: {})
        JSON.generate(
          "provider" => provider.to_s,
          "model" => model.to_s,
          "system" => system.to_s,
          "messages" => messages.map { |m| canonical_message(m) },
          "params" => canonical_params(params)
        )
      end

      def self.canonical_message(message)
        { "role" => fetch_field(message, :role).to_s, "content" => fetch_field(message, :content).to_s }
      end
      private_class_method :canonical_message

      def self.fetch_field(message, key)
        message[key] || message[key.to_s]
      end
      private_class_method :fetch_field

      # Params must already be string valued (callers format numbers
      # themselves, e.g. "0.7"), sorted ascending by byte value.
      def self.canonical_params(params)
        sorted = params.map { |k, v| [k.to_s, v] }.sort_by { |k, _v| k }.to_h
        sorted.each_value do |v|
          next if v.is_a?(String)

          raise Error::ArgumentError,
                "PromptCache params must be string valued (got #{v.class}); format numbers yourself so " \
                "the encoding never differs between SDKs"
        end
        sorted
      end
      private_class_method :canonical_params

      # Looks up the cache for this exact call. On a hit, returns the
      # cached response and never calls the block. On a miss, calls the
      # block (which should perform the real LLM call and return the text
      # to cache), stores it, and returns it. Always returns
      # {response:, cache_hit:, cache_key:}.
      #
      # The block may return either just the response, or a
      # [response, usage] pair (a HotKV::TokenUsage); when it does,
      # +usage+ is stored with the cache entry (see HotKV::Namespaces::PCache#set)
      # so a later hit attributes its savings through #stats.
      def get_or_call(provider:, model:, messages:, system: "", params: {}, ttl: nil, meta: nil)
        ensure_namespace!
        key = self.class.cache_key(provider: provider, model: model, messages: messages, system: system,
                                    params: params)
        cached = @client.pcache.get(@namespace, key)
        return { response: cached, cache_hit: true, cache_key: key } unless cached.nil?

        response, usage = CallResult.split_usage(yield)
        @client.pcache.set(@namespace, key, response, ttl: ttl, meta: meta, usage: usage)
        { response: response, cache_hit: false, cache_key: key }
      end

      # Hit/miss counts and cost saved are already tracked server side;
      # see #stats. This pushes real per call token/cost/latency numbers
      # (which only the caller knows) into LLMSTATS, optionally priced
      # from the LLMSTATS.PRICE table via +model+. A no-op unless
      # :stats_bucket was configured or +bucket+ is given here.
      def record_usage(input_tokens:, output_tokens:, cached_tokens: 0, cost_usd: 0.0, latency_ms: 0, error: false,
                        model: nil, cache_write_5m_tokens: nil, cache_write_1h_tokens: nil, bucket: @stats_bucket)
        return unless bucket

        @client.llmstats.bucket(bucket) unless @bucket_ready
        @bucket_ready = true
        @client.llmstats.record(bucket, input_tokens, output_tokens, cached_tokens, cost_usd, latency_ms,
                                 error: error, model: model, cache_write_5m_tokens: cache_write_5m_tokens,
                                 cache_write_1h_tokens: cache_write_1h_tokens)
      end

      # entries, hits, misses, evictions, memory_bytes, hit_rate, p50_ns,
      # p95_ns, p99_ns, cost_saved_usd and the usage_saved_* savings
      # counters (attributed from any +usage+ stored with an entry) for
      # this namespace.
      def stats
        @client.pcache.stats(@namespace)
      end

      private

      def ensure_namespace!
        return if @namespace_ready

        @client.pcache.create(@namespace)
        @namespace_ready = true
      rescue Error::ServerError
        @namespace_ready = true
      end
    end
  end
end
