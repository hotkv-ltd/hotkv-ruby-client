# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Namespaces
    # Bloom filter (BF.*). Replies that are booleans on RESP3 and 0/1 on
    # RESP2 are normalized to true/false.
    class BF
      INFO_LABELS = {
        capacity: "Capacity", size: "Size", filters: "Number of filters",
        items: "Number of items inserted", expansion: "Expansion rate"
      }.freeze

      def initialize(client)
        @client = client
      end

      # Creates a filter. +error_rate+ is the target false positive rate
      # (0 < rate < 1), +capacity+ the items it is sized for before it grows.
      def reserve(key, error_rate, capacity, expansion: nil, nonscaling: false)
        args = ["BF.RESERVE", key, error_rate, capacity]
        args.push("EXPANSION", expansion) if expansion
        args.push("NONSCALING") if nonscaling
        @client.invoke(*args) { |r| r == "OK" }
      end

      # Adds +item+; true when it was new, false when it may already exist.
      def add(key, item)
        @client.invoke("BF.ADD", key, item) { |r| Commands::Support.truthy(r) }
      end

      def madd(key, *items)
        @client.invoke("BF.MADD", key, *items.flatten) { |r| r.map { |v| Commands::Support.truthy(v) } }
      end

      # Adds items, creating the filter with the options when missing.
      def insert(key, items, capacity: nil, error: nil, expansion: nil, nocreate: false, nonscaling: false)
        args = ["BF.INSERT", key]
        args.push("CAPACITY", capacity) if capacity
        args.push("ERROR", error) if error
        args.push("EXPANSION", expansion) if expansion
        args.push("NOCREATE") if nocreate
        args.push("NONSCALING") if nonscaling
        args.push("ITEMS", *Array(items))
        @client.invoke(*args) { |r| r.map { |v| Commands::Support.truthy(v) } }
      end

      # True when +item+ may be in the filter (false: definitely not).
      def exists(key, item)
        @client.invoke("BF.EXISTS", key, item) { |r| Commands::Support.truthy(r) }
      end

      def mexists(key, *items)
        @client.invoke("BF.MEXISTS", key, *items.flatten) { |r| r.map { |v| Commands::Support.truthy(v) } }
      end

      # Number of items added.
      def card(key)
        @client.invoke("BF.CARD", key)
      end

      # Hash of "Capacity", "Size", "Number of filters", "Number of items
      # inserted", "Expansion rate"; with +field+ (:capacity, :size, :filters,
      # :items, :expansion) a Hash of just that one.
      def info(key, field = nil)
        args = ["BF.INFO", key]
        args.push(field.to_s.upcase) if field
        @client.invoke(*args) do |r|
          if r.is_a?(Hash) then r
          elsif field then { INFO_LABELS.fetch(field.to_s.downcase.to_sym, field.to_s) => r.first } # RESP2: just the value
          else r.each_slice(2).to_h
          end
        end
      end

      # One chunk of the filter: [next_iterator, data]. Start with iterator 0;
      # a returned iterator of 0 ends the dump.
      def scandump(key, iterator)
        @client.invoke("BF.SCANDUMP", key, iterator)
      end

      def loadchunk(key, iterator, data)
        @client.invoke("BF.LOADCHUNK", key, iterator, data) { |r| r == "OK" }
      end
    end

    # Count-Min Sketch (CMS.*).
    class CMS
      def initialize(client)
        @client = client
      end

      def initbydim(key, width, depth)
        @client.invoke("CMS.INITBYDIM", key, width, depth) { |r| r == "OK" }
      end

      def initbyprob(key, error, probability)
        @client.invoke("CMS.INITBYPROB", key, error, probability) { |r| r == "OK" }
      end

      # +increments+ is a Hash or a flat [item, increment, ...] list. Returns
      # the new estimated counts in order.
      def incrby(key, increments)
        flat = increments.is_a?(Hash) ? increments.flatten(1) : increments.flatten
        @client.invoke("CMS.INCRBY", key, *flat)
      end

      def query(key, *items)
        @client.invoke("CMS.QUERY", key, *items.flatten)
      end

      # Hash with "width", "depth" and "count".
      def info(key)
        @client.invoke("CMS.INFO", key) { |r| r.is_a?(Hash) ? r : r.each_slice(2).to_h }
      end

      # Replaces +destination+ with the (optionally weighted) sum of +sources+.
      def merge(destination, sources, weights: nil)
        args = ["CMS.MERGE", destination, sources.length, *sources]
        args.push("WEIGHTS", *weights) if weights
        @client.invoke(*args) { |r| r == "OK" }
      end
    end

    # Top-K (TOPK.*).
    class TopK
      def initialize(client)
        @client = client
      end

      def reserve(key, topk, width: nil, depth: nil, decay: nil)
        args = ["TOPK.RESERVE", key, topk]
        given = [width, depth, decay].count { |v| !v.nil? }
        raise Error::ArgumentError, "width, depth and decay go together: give all three or none" unless [0, 3].include?(given)

        args.push(width, depth, decay) if given == 3
        @client.invoke(*args) { |r| r == "OK" }
      end

      # Counts the items; each reply element is the item pushed out of the
      # list, or nil.
      def add(key, *items)
        @client.invoke("TOPK.ADD", key, *items.flatten)
      end

      # +increments+ is a Hash or a flat [item, increment, ...] list.
      def incrby(key, increments)
        flat = increments.is_a?(Hash) ? increments.flatten(1) : increments.flatten
        @client.invoke("TOPK.INCRBY", key, *flat)
      end

      def query(key, *items)
        @client.invoke("TOPK.QUERY", key, *items.flatten) { |r| r.map { |v| Commands::Support.truthy(v) } }
      end

      def count(key, *items)
        @client.invoke("TOPK.COUNT", key, *items.flatten)
      end

      # The list, highest count first; with :withcount an Array of
      # [item, count] pairs.
      def list(key, withcount: false)
        return @client.invoke("TOPK.LIST", key) unless withcount

        @client.invoke("TOPK.LIST", key, "WITHCOUNT") do |r|
          r.first.is_a?(Array) ? r : r.each_slice(2).to_a
        end
      end

      # Hash with "k", "width", "depth" and "decay" (Float).
      def info(key)
        @client.invoke("TOPK.INFO", key) do |r|
          h = r.is_a?(Hash) ? r : r.each_slice(2).to_h
          h["decay"] = Wire.parse_float(h["decay"]) if h.key?("decay")
          h
        end
      end
    end
  end
end
