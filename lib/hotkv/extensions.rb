# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "namespaces/core"
require_relative "namespaces/caching"
require_relative "namespaces/amem"
require_relative "namespaces/rag"
require_relative "namespaces/ops"

module HotKV
  module Commands
    # HotKV exclusive and AI command groups, exposed as
    # namespaced helpers, one memoized accessor per family, e.g.
    # `client.pcache.get(ns, prompt)` or `client.amem.conv_append(...)`.
    # Also NEXPIRE/NTTL/NEXPIREAT, the three standalone nanosecond
    # resolution TTL commands, as plain methods alongside EXPIRE/TTL.
    module Extensions
      # Nanosecond resolution relative TTL. -> 1 if set, 0 if key does not exist.
      def nexpire(key, nanoseconds)
        invoke("NEXPIRE", key, nanoseconds) { |r| r == 1 }
      end

      # -> remaining TTL in nanoseconds, -2 if key does not exist, -1 if no expiry.
      def nttl(key)
        invoke("NTTL", key)
      end

      # Nanosecond resolution absolute TTL (unix nanosecond timestamp).
      def nexpireat(key, unix_nanoseconds)
        invoke("NEXPIREAT", key, unix_nanoseconds) { |r| r == 1 }
      end

      def tag
        @hotkv_ns_tag ||= Namespaces::Tag.new(self)
      end

      def gcra
        @hotkv_ns_gcra ||= Namespaces::Gcra.new(self)
      end

      def vsim
        @hotkv_ns_vsim ||= Namespaces::VSim.new(self)
      end

      def observe
        @hotkv_ns_observe ||= Namespaces::Observe.new(self)
      end

      def alerts
        @hotkv_ns_alerts ||= Namespaces::Alerts.new(self)
      end

      def hotkeys
        @hotkv_ns_hotkeys ||= Namespaces::Hotkeys.new(self)
      end

      def scache
        @hotkv_ns_scache ||= Namespaces::SCache.new(self)
      end

      def pcache
        @hotkv_ns_pcache ||= Namespaces::PCache.new(self)
      end

      def tool_cache
        @hotkv_ns_tool_cache ||= Namespaces::KeyedCache.new(self, "TOOL.CACHE")
      end

      def ncache
        @hotkv_ns_ncache ||= Namespaces::KeyedCache.new(self, "NCACHE")
      end

      def guard
        @hotkv_ns_guard ||= Namespaces::KeyedCache.new(self, "GUARD")
      end

      def rerank
        @hotkv_ns_rerank ||= Namespaces::KeyedCache.new(self, "RERANK")
      end

      def llmstats
        @hotkv_ns_llmstats ||= Namespaces::LLMStats.new(self)
      end

      def llmbudget
        @hotkv_ns_llmbudget ||= Namespaces::LLMBudget.new(self)
      end

      def prompt
        @hotkv_ns_prompt ||= Namespaces::Prompt.new(self)
      end

      def embed_dedup
        @hotkv_ns_embed_dedup ||= Namespaces::EmbedDedup.new(self)
      end

      def amem
        @hotkv_ns_amem ||= Namespaces::AMem.new(self)
      end

      def rag
        @hotkv_ns_rag ||= Namespaces::RAG.new(self)
      end

      def ratelimit
        @hotkv_ns_ratelimit ||= Namespaces::RateLimit.new(self)
      end

      def ts
        @hotkv_ns_ts ||= Namespaces::TS.new(self)
      end

      def feature
        @hotkv_ns_feature ||= Namespaces::Feature.new(self)
      end
    end
  end
end
