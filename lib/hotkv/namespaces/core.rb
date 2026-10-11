# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Namespaces
    # TAG.* (core): freeform tags on any key.
    class Tag
      def initialize(client)
        @client = client
      end

      def set(key, *tags)
        @client.invoke("TAG.SET", key, *tags.flatten)
      end

      def rem(key, *tags)
        @client.invoke("TAG.REM", key, *tags.flatten)
      end

      def get(key)
        @client.invoke("TAG.GET", key)
      end

      def members(*tags)
        @client.invoke("TAG.MEMBERS", *tags.flatten)
      end

      def inter(*tags)
        @client.invoke("TAG.INTER", *tags.flatten)
      end

      def count(key)
        @client.invoke("TAG.COUNT", key)
      end

      def exists(key, tag)
        @client.invoke("TAG.EXISTS", key, tag) { |r| r == 1 }
      end
    end

    # GCRA.* (core): the generic cell rate algorithm limiter primitive.
    class Gcra
      def initialize(client)
        @client = client
      end

      def limit(key, period_ms, burst, count = nil)
        args = ["GCRA.LIMIT", key, period_ms, burst]
        args.push(count) if count
        @client.invoke(*args) do |r|
          { denied: r[0] == 1, limit: r[1], remaining: r[2], retry_after_ms: r[3], reset_after_ms: r[4] }
        end
      end

      def reset(*keys)
        @client.invoke("GCRA.RESET", *keys.flatten)
      end
    end

    # VSIM.* (core, except SAVE/LOAD/LIST/DROP persistence which need a
    # license that includes the VSIMPersist feature): a vector similarity
    # index.
    class VSim
      def initialize(client)
        @client = client
      end

      def createindex(name, dims, metric: nil, m: nil, ef_construction: nil, ef_search: nil)
        args = ["VSIM.CREATEINDEX", name, dims]
        args.push("METRIC", metric) if metric
        args.push("M", m) if m
        args.push("EF_CONSTRUCTION", ef_construction) if ef_construction
        args.push("EF_SEARCH", ef_search) if ef_search
        @client.invoke(*args) { |r| r == "OK" }
      end

      def dropindex(name)
        @client.invoke("VSIM.DROPINDEX", name) { |r| r == "OK" }
      end

      def set(index, key, vector)
        @client.invoke("VSIM.SET", index, key, *Wire.finite_vector(vector))
      end

      def get(index, key)
        @client.invoke("VSIM.GET", index, key) { |r| r&.map { |v| Wire.parse_float(v) } }
      end

      def del(index, key)
        @client.invoke("VSIM.DEL", index, key)
      end

      def search(index, k, vector, filter: nil, ef: nil)
        args = ["VSIM.SEARCH", index, k, *Wire.finite_vector(vector)]
        args.push("FILTER", *Array(filter)) if filter
        args.push("EF", ef) if ef
        @client.invoke(*args) { |r| r.each_slice(2).map { |(key, dist)| [key, Wire.parse_float(dist)] } }
      end

      def info(index = nil)
        return @client.invoke("VSIM.INFO") if index.nil?

        @client.invoke("VSIM.INFO", index) { |r| Commands::Support.pairs_to_h(r) }
      end

      # Persistence: needs the VSIMPersist license feature.
      def save(snapshot_name, blob)
        @client.invoke("VSIM.SAVE", snapshot_name, blob)
      end

      def load(snapshot_name)
        @client.invoke("VSIM.LOAD", snapshot_name)
      end

      def list
        @client.invoke("VSIM.LIST")
      end

      def drop(snapshot_name)
        @client.invoke("VSIM.DROP", snapshot_name) { |r| r == 1 }
      end
    end

    # OBSERVE (needs the Observability license feature; admin).
    class Observe
      def initialize(client)
        @client = client
      end

      def info
        @client.invoke("OBSERVE", "INFO") { |r| Commands::Support.pairs_to_h(r) }
      end

      def metrics
        @client.invoke("OBSERVE", "METRICS") { |r| Commands::Support.pairs_to_h(r) }
      end
    end

    # ALERTS (needs the Observability license feature; admin).
    class Alerts
      def initialize(client)
        @client = client
      end

      def info
        @client.invoke("ALERTS", "INFO") { |r| Commands::Support.pairs_to_h(r) }
      end

      def test(severity = nil, *message)
        args = ["ALERTS", "TEST"]
        args.push(severity) if severity
        flat_message = message.flatten
        args.concat(flat_message) unless flat_message.empty?
        @client.invoke(*args)
      end

      def seturl(url)
        @client.invoke("ALERTS", "SETURL", url)
      end

      def setseverity(severity)
        @client.invoke("ALERTS", "SETSEVERITY", severity)
      end

      def on
        @client.invoke("ALERTS", "ON")
      end

      def off
        @client.invoke("ALERTS", "OFF")
      end
    end

    # HOTKEYS (core, admin).
    class Hotkeys
      def initialize(client)
        @client = client
      end

      def top(count = nil)
        args = count ? ["HOTKEYS", "TOP", count] : ["HOTKEYS", "TOP"]
        @client.invoke(*args)
      end

      def reset
        @client.invoke("HOTKEYS", "RESET") { |r| r == "OK" }
      end
    end
  end
end
