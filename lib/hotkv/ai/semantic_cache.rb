# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module AI
    # Embedding based answer cache: looks up the nearest cached answer
    # above a similarity threshold for a caller supplied embedding vector,
    # and stores new answers. Provider neutral: the SDK never computes
    # embeddings itself; +vector+ is whatever a caller's own embedding
    # model produced. Built on HotKV::Client#scache.
    class SemanticCache
      DEFAULT_NAMESPACE = "default"

      attr_reader :namespace

      def initialize(client, dims:, namespace: DEFAULT_NAMESPACE, metric: nil, threshold: nil, ttl: nil)
        @client = client
        @namespace = namespace
        @dims = dims
        @metric = metric
        @threshold = threshold
        @ttl = ttl
        @namespace_ready = false
      end

      # Looks up +vector+ in the cache. On a hit (similarity above the
      # configured, or overridden, threshold) returns
      # {response:, similarity:, cache_hit: true} without calling the
      # block. On a miss, calls the block (which should compute the real
      # answer and return it), stores it under +query_text+/+vector+, and
      # returns {response:, cache_hit: false}.
      #
      # The block may return either just the response, or a
      # [response, usage] pair (a HotKV::TokenUsage); when it does,
      # +usage+ is stored with the cache entry (see HotKV::Namespaces::SCache#set)
      # so a later hit attributes its savings through #stats.
      def get_or_call(query_text, vector, threshold: nil)
        ensure_namespace!
        hit = @client.scache.get(@namespace, vector, threshold: threshold)
        return hit.merge(cache_hit: true) if hit

        response, usage = CallResult.split_usage(yield)
        @client.scache.set(@namespace, query_text, response, vector, ttl: @ttl, usage: usage)
        { response: response, cache_hit: false }
      end

      # entries, hits, misses, hit_rate, p50_us and the usage_saved_*
      # savings counters (attributed from any +usage+ stored with an
      # entry) for this namespace.
      def stats
        @client.scache.stats(@namespace)
      end

      private

      def ensure_namespace!
        return if @namespace_ready

        @client.scache.create(@namespace, @dims, metric: @metric, threshold: @threshold, ttl: @ttl)
        @namespace_ready = true
      rescue Error::ServerError
        @namespace_ready = true
      end
    end
  end
end
