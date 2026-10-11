# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Namespaces
    # SCACHE.* (semantic cache; needs a license that includes the
    # SemanticCache feature). See also HotKV::AI::SemanticCache for the higher
    # level, provider neutral helper built on this.
    class SCache
      def initialize(client)
        @client = client
      end

      def create(ns, dims, metric: nil, threshold: nil, ttl: nil)
        args = ["SCACHE.CREATE", ns, dims]
        args.push("METRIC", metric) if metric
        args.push("THRESHOLD", Wire.finite(threshold)) if threshold
        args.push("TTL", ttl) if ttl
        @client.invoke(*args) { |r| r == "OK" }
      end

      # +usage+ (a HotKV::TokenUsage), if given, records the original
      # (uncached) call's token usage so a later hit attributes it (and
      # its cost, once the model is priced) to #stats's usage_saved_*
      # counters.
      def set(ns, query_text, response, vector, ttl: nil, usage: nil)
        args = ["SCACHE.SET", ns, query_text, response, *Wire.finite_vector(vector)]
        args.push("TTL", ttl) if ttl
        args.concat(usage.wire_args) if usage
        @client.invoke(*args) { |r| r == "OK" }
      end

      def get(ns, vector, threshold: nil)
        args = ["SCACHE.GET", ns, *Wire.finite_vector(vector)]
        args.push("THRESHOLD", Wire.finite(threshold)) if threshold
        @client.invoke(*args) { |r| r.nil? ? nil : { response: r[0], similarity: Wire.parse_float(r[1]) } }
      end

      # entries, hits, misses, hit_rate, p50_us and the usage_saved_*
      # savings counters for +ns+.
      def stats(ns)
        @client.invoke("SCACHE.STATS", ns) do |r|
          Commands::Support.pairs_to_h(r, float_keys: %i[hit_rate usage_saved_cost_usd])
        end
      end

      def flush(ns)
        @client.invoke("SCACHE.FLUSH", ns) { |r| r == 1 }
      end

      def drop(ns)
        @client.invoke("SCACHE.DROP", ns) { |r| r == 1 }
      end

      def list
        @client.invoke("SCACHE.LIST")
      end

      def threshold(ns, value)
        @client.invoke("SCACHE.THRESHOLD", ns, Wire.finite(value)) { |r| r == "OK" }
      end
    end

    # PCACHE.* (prompt/LLM response cache; needs the PromptCache license
    # feature). See also HotKV::AI::PromptCache for the higher level helper.
    class PCache
      def initialize(client)
        @client = client
      end

      def create(ns, max_entries: nil, ttl: nil, cost_per_hit: nil)
        args = ["PCACHE.CREATE", ns]
        args.push("MAX_ENTRIES", max_entries) if max_entries
        args.push("TTL", ttl) if ttl
        args.push("COST_PER_HIT", Wire.finite(cost_per_hit)) if cost_per_hit
        @client.invoke(*args) { |r| r == "OK" }
      end

      # +usage+ (a HotKV::TokenUsage), if given, records the original
      # (uncached) call's token usage so a later hit attributes it (and
      # its cost, once the model is priced) to #stats's usage_saved_*
      # counters.
      def set(ns, prompt, response, ttl: nil, meta: nil, usage: nil)
        args = ["PCACHE.SET", ns, prompt, response]
        args.push("TTL", ttl) if ttl
        args.push("META", meta) if meta
        args.concat(usage.wire_args) if usage
        @client.invoke(*args) { |r| r == "OK" }
      end

      def get(ns, prompt)
        @client.invoke("PCACHE.GET", ns, prompt)
      end

      def getex(ns, prompt)
        @client.invoke("PCACHE.GETEX", ns, prompt) do |r|
          r.nil? ? nil : { response: r[0], metadata: r[1], hit_count: r[2] }
        end
      end

      def del(ns, prompt)
        @client.invoke("PCACHE.DEL", ns, prompt) { |r| r == 1 }
      end

      # entry/hit/miss/eviction/latency/cost statistics for +ns+, including
      # the usage_saved_* savings counters.
      def stats(ns)
        @client.invoke("PCACHE.STATS", ns) do |r|
          Commands::Support.pairs_to_h(r, float_keys: %i[hit_rate cost_saved_usd usage_saved_cost_usd])
        end
      end

      def flush(ns)
        @client.invoke("PCACHE.FLUSH", ns)
      end

      def drop(ns)
        @client.invoke("PCACHE.DROP", ns) { |r| r == 1 }
      end

      def list
        @client.invoke("PCACHE.LIST")
      end

      def config_set(ns, key, value)
        @client.invoke("PCACHE.CONFIG", ns, "SET", key, value) { |r| r == "OK" }
      end
    end

    # Shared engine behind TOOL.CACHE.*, NCACHE.*, GUARD.* and RERANK.*:
    # four identical key/value caches, one per HotKV::Client#tool_cache,
    # #ncache, #guard and #rerank accessor.
    class KeyedCache
      def initialize(client, wire_prefix)
        @client = client
        @prefix = wire_prefix
      end

      def create(ns, max_entries: nil, ttl: nil)
        args = ["#{@prefix}.CREATE", ns]
        args.push("MAX_ENTRIES", max_entries) if max_entries
        args.push("TTL", ttl) if ttl
        @client.invoke(*args) { |r| r == "OK" }
      end

      # +usage+ (a HotKV::TokenUsage), if given, records the original
      # (uncached) call's token usage so a later hit attributes it (and
      # its cost, once the model is priced) to #stats's usage_saved_*
      # counters.
      def set(ns, key, value, ttl: nil, meta: nil, usage: nil)
        args = ["#{@prefix}.SET", ns, key, value]
        args.push("TTL", ttl) if ttl
        args.push("META", meta) if meta
        args.concat(usage.wire_args) if usage
        @client.invoke(*args) { |r| r == "OK" }
      end

      def get(ns, key)
        @client.invoke("#{@prefix}.GET", ns, key)
      end

      def del(ns, key)
        @client.invoke("#{@prefix}.DEL", ns, key) { |r| r == 1 }
      end

      # entries, hits, misses, evictions, memory_bytes and the
      # usage_saved_* savings counters for +ns+.
      def stats(ns)
        @client.invoke("#{@prefix}.STATS", ns) do |r|
          Commands::Support.pairs_to_h(r, float_keys: %i[usage_saved_cost_usd])
        end
      end

      def flush(ns)
        @client.invoke("#{@prefix}.FLUSH", ns)
      end

      def drop(ns)
        @client.invoke("#{@prefix}.DROP", ns) { |r| r == 1 }
      end

      def list
        @client.invoke("#{@prefix}.LIST")
      end
    end

    # LLMSTATS.* (needs the LLMStats license feature).
    class LLMStats
      def initialize(client)
        @client = client
      end

      def bucket(name)
        @client.invoke("LLMSTATS.BUCKET", name) { |r| r == "OK" }
      end

      # +cached_tokens+ is cache-READ tokens. With +model+, the server
      # prices the call itself from its LLMSTATS.PRICE table and ignores
      # +cost_usd+ (pass 0.0); an unpriced model still records tokens,
      # costs 0 and counts toward +unpriced_requests+. For OpenAI, pass
      # <tt>prompt_tokens - cached_tokens</tt> as +input_tokens+ (OpenAI
      # reports cache hits as part of prompt_tokens, unlike Anthropic).
      def record(bucket, input_tokens, output_tokens, cached_tokens, cost_usd, latency_ms,
                 error: nil, model: nil, cache_write_5m_tokens: nil, cache_write_1h_tokens: nil)
        args = ["LLMSTATS.RECORD", bucket, input_tokens, output_tokens, cached_tokens, Wire.finite(cost_usd), latency_ms]
        args.push("ERROR", error ? 1 : 0) unless error.nil?
        args.push("MODEL", model) if model
        args.push("CACHEWRITE5M", cache_write_5m_tokens) if cache_write_5m_tokens
        args.push("CACHEWRITE1H", cache_write_1h_tokens) if cache_write_1h_tokens
        @client.invoke(*args) { |r| r == "OK" }
      end

      # requests/errors/token/cost/latency stats for +bucket+, including a
      # trailing 1-minute rolling window and unpriced_requests.
      def get(bucket)
        @client.invoke("LLMSTATS.GET", bucket) do |r|
          Commands::Support.pairs_to_h(r, float_keys: %i[cost_usd avg_latency_ms cost_usd_1m])
        end
      end

      def reset(bucket)
        @client.invoke("LLMSTATS.RESET", bucket) { |r| r == 1 }
      end

      def drop(bucket)
        @client.invoke("LLMSTATS.DROP", bucket) { |r| r == 1 }
      end

      def list
        @client.invoke("LLMSTATS.LIST")
      end

      # -- LLMSTATS.PRICE (per model price table, used by #record and
      # Namespaces::LLMBudget#consume when given +model+/+usage+) --------

      # Sets a custom USD-per-1,000,000-token price for +model+. Prices
      # may be a Numeric or a decimal String; an omitted cache price
      # defaults to 0.1x/1.25x/2x +input_usd_per_mtok+.
      def price_set(model, input_usd_per_mtok, output_usd_per_mtok, cache_read_usd_per_mtok: nil,
                    cache_write_5m_usd_per_mtok: nil, cache_write_1h_usd_per_mtok: nil)
        args = [
          "LLMSTATS.PRICE", "SET", model,
          "INPUT", LLMPrice.format_price(input_usd_per_mtok),
          "OUTPUT", LLMPrice.format_price(output_usd_per_mtok)
        ]
        args.push("CACHEREAD", LLMPrice.format_price(cache_read_usd_per_mtok)) if cache_read_usd_per_mtok
        args.push("CACHEWRITE5M", LLMPrice.format_price(cache_write_5m_usd_per_mtok)) if cache_write_5m_usd_per_mtok
        args.push("CACHEWRITE1H", LLMPrice.format_price(cache_write_1h_usd_per_mtok)) if cache_write_1h_usd_per_mtok
        @client.invoke(*args) { |r| r == "OK" }
      end

      # +model+'s price table entry. An unknown model comes back with
      # <tt>source == "unpriced"</tt> and every price 0.0, not an error.
      def price_get(model)
        @client.invoke("LLMSTATS.PRICE", "GET", model) { |r| price_from_reply(r) }
      end

      # Every known model's price table entry (built in and custom).
      def price_list
        @client.invoke("LLMSTATS.PRICE", "LIST") { |r| r.map { |item| price_from_reply(item) } }
      end

      # Removes +model+'s custom price override, if any (false if there
      # was none; the model then falls back to its built-in price, if any).
      def price_del(model)
        @client.invoke("LLMSTATS.PRICE", "DEL", model) { |r| r == 1 }
      end

      private

      def price_from_reply(reply)
        LLMPrice.from_fields(Commands::Support.pairs_to_h(reply, float_keys: LLMPrice::FLOAT_FIELDS))
      end
    end

    # LLMBUDGET.* (needs the LLMBudget license feature).
    class LLMBudget
      def initialize(client)
        @client = client
      end

      def set(name, token_limit, cost_limit_usd, window_seconds)
        @client.invoke("LLMBUDGET.SET", name, token_limit, Wire.usd(cost_limit_usd), window_seconds) { |r| r == "OK" }
      end

      # Tries to consume +tokens+/+cost_usd+ from budget +name+; true if
      # allowed, false if it would exceed the cap. Pass +usage+ (a
      # HotKV::TokenUsage) instead to have the server compute both from
      # its LLMSTATS.PRICE table (this sends tokens/cost_usd as 0/0.0
      # regardless of what is passed, since the server ignores them).
      def consume(name, tokens = 0, cost_usd = 0.0, usage: nil)
        args = ["LLMBUDGET.CONSUME", name, tokens, Wire.finite(cost_usd)]
        args.concat(usage.wire_args) if usage
        @client.invoke(*args) { |r| r == 1 }
      end

      # usage, limits, the current window's remaining time and
      # unpriced_requests for +name+.
      def status(name)
        @client.invoke("LLMBUDGET.STATUS", name) do |r|
          Commands::Support.pairs_to_h(r, float_keys: %i[cost_used_usd cost_limit_usd])
        end
      end

      def reset(name)
        @client.invoke("LLMBUDGET.RESET", name) { |r| r == 1 }
      end

      def drop(name)
        @client.invoke("LLMBUDGET.DROP", name) { |r| r == 1 }
      end

      def list
        @client.invoke("LLMBUDGET.LIST")
      end
    end

    # PROMPT.* (versioned prompt/template registry; needs the PromptRegistry license feature).
    class Prompt
      def initialize(client)
        @client = client
      end

      def put(name, content, meta: nil)
        args = ["PROMPT.PUT", name, content]
        args.push("META", meta) if meta
        @client.invoke(*args)
      end

      def get(name, version = nil)
        args = version ? ["PROMPT.GET", name, version] : ["PROMPT.GET", name]
        @client.invoke(*args) { |r| prompt_version(r) }
      end

      def latest(name)
        @client.invoke("PROMPT.LATEST", name) { |r| prompt_version(r) }
      end

      def setactive(name, version)
        @client.invoke("PROMPT.SETACTIVE", name, version) { |r| r == "OK" }
      end

      def versions(name)
        @client.invoke("PROMPT.VERSIONS", name)
      end

      def drop(name)
        @client.invoke("PROMPT.DROP", name) { |r| r == 1 }
      end

      def list
        @client.invoke("PROMPT.LIST")
      end

      private

      def prompt_version(r)
        r.nil? ? nil : { version: r[0], content: r[1], metadata: r[2], created_unix: r[3] }
      end
    end

    # EMBED.DEDUP.* (needs the EmbedDedup license feature).
    class EmbedDedup
      def initialize(client)
        @client = client
      end

      def put(ns, hash, model, embedding)
        @client.invoke("EMBED.DEDUP.PUT", ns, hash, model, embedding) { |r| r == 1 }
      end

      def get(ns, hash)
        @client.invoke("EMBED.DEDUP.GET", ns, hash)
      end

      def release(ns, hash)
        @client.invoke("EMBED.DEDUP.RELEASE", ns, hash) { |r| r == 1 }
      end

      def stats(ns)
        @client.invoke("EMBED.DEDUP.STATS", ns) { |r| Commands::Support.pairs_to_h(r) }
      end

      def drop(ns)
        @client.invoke("EMBED.DEDUP.DROP", ns) { |r| r == 1 }
      end

      def purge(ns)
        @client.invoke("EMBED.DEDUP.PURGE", ns) { |r| r == 1 }
      end

      def list
        @client.invoke("EMBED.DEDUP.LIST")
      end
    end
  end
end
