# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Namespaces
    # AMEM.* (AI agent memory; needs a license that includes the
    # AgentMemory feature): conversation, semantic, working and episodic
    # memory, plus cross-memory search. AMEM.SUMMARY.* (the AMemSummary
    # feature) lives under the nested #summary accessor.
    class AMem
      attr_reader :summary

      def initialize(client)
        @client = client
        @summary = Summary.new(client)
      end

      # -- conversation memory --

      def conv_create(session_id, window: nil, ttl: nil)
        args = ["AMEM.CONV.CREATE", session_id]
        args.push("WINDOW", window) if window
        args.push("TTL", ttl) if ttl
        @client.invoke(*args) { |r| r == "OK" }
      end

      def conv_append(session_id, role, content)
        @client.invoke("AMEM.CONV.APPEND", session_id, role, content) { |r| r == "OK" }
      end

      def conv_get(session_id)
        @client.invoke("AMEM.CONV.GET", session_id) { |r| r.map { |row| labeled(row, %i[role content]) } }
      end

      def conv_window(session_id, n)
        @client.invoke("AMEM.CONV.WINDOW", session_id, n) { |r| r.map { |row| labeled(row, %i[role content]) } }
      end

      def conv_clear(session_id)
        @client.invoke("AMEM.CONV.CLEAR", session_id) { |r| r == 1 }
      end

      def conv_drop(session_id)
        @client.invoke("AMEM.CONV.DROP", session_id) { |r| r == 1 }
      end

      # -- semantic memory (per-agent vector store) --

      def sem_create(agent_id, dimensions)
        @client.invoke("AMEM.SEM.CREATE", agent_id, dimensions) { |r| r == "OK" }
      end

      def sem_store(agent_id, key, content, vector, ttl: nil)
        args = ["AMEM.SEM.STORE", agent_id, key, content, *Wire.finite_vector(vector)]
        args.push("TTL", ttl) if ttl
        @client.invoke(*args) { |r| r == "OK" }
      end

      def sem_recall(agent_id, k, vector)
        @client.invoke("AMEM.SEM.RECALL", agent_id, k, *Wire.finite_vector(vector)) do |r|
          r.map { |row| labeled(row, %i[key content similarity], float_fields: %i[similarity]) }
        end
      end

      def sem_forget(agent_id, key)
        @client.invoke("AMEM.SEM.FORGET", agent_id, key) { |r| r == 1 }
      end

      def sem_list(agent_id)
        @client.invoke("AMEM.SEM.LIST", agent_id)
      end

      # -- working memory (per-session scratch key/value) --

      def work_set(session_id, key, value, ttl: nil)
        args = ["AMEM.WORK.SET", session_id, key, value]
        args.push("TTL", ttl) if ttl
        @client.invoke(*args) { |r| r == "OK" }
      end

      def work_get(session_id, key)
        @client.invoke("AMEM.WORK.GET", session_id, key)
      end

      def work_del(session_id, key)
        @client.invoke("AMEM.WORK.DEL", session_id, key) { |r| r == 1 }
      end

      def work_clear(session_id)
        @client.invoke("AMEM.WORK.CLEAR", session_id) { |r| r == 1 }
      end

      def work_list(session_id)
        @client.invoke("AMEM.WORK.LIST", session_id)
      end

      # -- episodic memory (append only event log) --

      def epis_log(agent_id, event_type, content, metadata: nil)
        args = ["AMEM.EPIS.LOG", agent_id, event_type, content]
        args.push("METADATA", metadata) if metadata
        @client.invoke(*args) { |r| r == "OK" }
      end

      def epis_query(agent_id, type: nil, from: nil, to: nil, limit: nil)
        args = ["AMEM.EPIS.QUERY", agent_id]
        args.push("TYPE", type) if type
        args.push("FROM", from) if from
        args.push("TO", to) if to
        args.push("LIMIT", limit) if limit
        @client.invoke(*args) { |r| r.map { |row| labeled(row, %i[type content metadata timestamp]) } }
      end

      def epis_clear(agent_id)
        @client.invoke("AMEM.EPIS.CLEAR", agent_id) { |r| r == 1 }
      end

      def epis_stats(agent_id)
        @client.invoke("AMEM.EPIS.STATS", agent_id) { |r| Commands::Support.pairs_to_h(r) }
      end

      # -- cross-memory search (semantic + episodic + working together) --

      def search(agent_id, k, vector)
        @client.invoke("AMEM.SEARCH", agent_id, k, *Wire.finite_vector(vector)) do |r|
          r.map { |row| labeled(row, %i[source key content similarity], float_fields: %i[similarity]) }
        end
      end

      private

      # A "labeled flat array" reply looks like ["role", <role>, "content",
      # <content>]: fixed label tokens paired with their values. Unwraps
      # it into a Hash keyed by +fields+, in the order the server documents.
      def labeled(row, fields, float_fields: [])
        h = {}
        fields.each_with_index { |f, i| h[f] = row[(i * 2) + 1] }
        float_fields.each { |f| h[f] = Wire.parse_float(h[f]) }
        h
      end

      # AMEM.SUMMARY.* (needs the AMemSummary license feature).
      class Summary
        def initialize(client)
          @client = client
        end

        def set(agent_id, summary_text)
          @client.invoke("AMEM.SUMMARY.SET", agent_id, summary_text)
        end

        def append(agent_id, extra)
          @client.invoke("AMEM.SUMMARY.APPEND", agent_id, extra)
        end

        def get(agent_id)
          @client.invoke("AMEM.SUMMARY.GET", agent_id) do |r|
            r.nil? ? nil : { summary: r[0], version: r[1], updated_unix: r[2] }
          end
        end

        def drop(agent_id)
          @client.invoke("AMEM.SUMMARY.DROP", agent_id) { |r| r == 1 }
        end

        def list
          @client.invoke("AMEM.SUMMARY.LIST")
        end
      end
    end
  end
end
