# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Namespaces
    # RATELIMIT.* (needs the RateLimiting license feature).
    class RateLimit
      def initialize(client)
        @client = client
      end

      def create(name, limit, window_ms, algo: nil, refill: nil, drain: nil)
        args = ["RATELIMIT.CREATE", name, limit, window_ms]
        args.push("ALGO", algo) if algo
        args.push("REFILL", Wire.finite(refill)) if refill
        args.push("DRAIN", Wire.finite(drain)) if drain
        @client.invoke(*args) { |r| r == "OK" }
      end

      def check(name, key, cost: nil)
        args = ["RATELIMIT.CHECK", name, key]
        args.push("COST", cost) if cost
        @client.invoke(*args) { |r| result(r) }
      end

      def peek(name, key)
        @client.invoke("RATELIMIT.PEEK", name, key) { |r| result(r) }
      end

      def reset(name, key)
        @client.invoke("RATELIMIT.RESET", name, key) { |r| r == "OK" }
      end

      def stats(name)
        @client.invoke("RATELIMIT.STATS", name) { |r| Commands::Support.pairs_to_h(r) }
      end

      def drop(name)
        @client.invoke("RATELIMIT.DROP", name) { |r| r == "OK" }
      end

      def list
        @client.invoke("RATELIMIT.LIST")
      end

      private

      def result(r)
        { allowed: r[0] == 1, remaining: r[1], retry_after_ms: r[2], limit: r[3], current: r[4] }
      end
    end

    # TS.* (time series; needs the TimeSeries license feature).
    class TS
      def initialize(client)
        @client = client
      end

      def create(key, retention: nil, labels: nil)
        args = ["TS.CREATE", key]
        args.push("RETENTION", retention) if retention
        args.push("LABELS", *labels.flat_map { |k, v| [k, v] }) if labels && !labels.empty?
        @client.invoke(*args) { |r| r == "OK" }
      end

      def add(key, value, timestamp: "*")
        @client.invoke("TS.ADD", key, timestamp, Wire.finite(value))
      end

      def range(key, from_ms, to_ms, count: nil)
        args = ["TS.RANGE", key, from_ms, to_ms]
        args.push("COUNT", count) if count
        @client.invoke(*args) { |r| r.map { |(ts, v)| [ts, Wire.parse_float(v)] } }
      end

      def agg(key, from_ms, to_ms, bucket_ms, agg_type)
        @client.invoke("TS.AGG", key, from_ms, to_ms, bucket_ms, agg_type) { |r| r.map { |(ts, v)| [ts, Wire.parse_float(v)] } }
      end

      def info(key)
        @client.invoke("TS.INFO", key) { |r| Commands::Support.pairs_to_h(r, float_keys: %i[lastValue]) }
      end

      def delete(key)
        @client.invoke("TS.DELETE", key) { |r| r == "OK" }
      end

      def retention(key, retention_ms)
        @client.invoke("TS.RETENTION", key, retention_ms) { |r| r == "OK" }
      end

      def downsample(src_key, dest_key, agg_type, bucket_ms)
        @client.invoke("TS.DOWNSAMPLE", src_key, dest_key, agg_type, bucket_ms) { |r| r == "OK" }
      end

      def list(label: nil, value: nil)
        args = ["TS.LIST"]
        args.push("LABEL", label, value) if label
        @client.invoke(*args)
      end
    end

    # FEATURE.* (feature store; needs the FeatureStore license feature).
    class Feature
      def initialize(client)
        @client = client
      end

      # +schema+: a Hash {name => type} or a flat [name, type, ...] list.
      def create(group, description, schema)
        @client.invoke("FEATURE.CREATE", group, description, "SCHEMA", *flatten_kv(schema)) { |r| r == "OK" }
      end

      def set(group, entity, values)
        @client.invoke("FEATURE.SET", group, entity, *flatten_kv(values)) { |r| r == "OK" }
      end

      # FEATURE.SET with an explicit stamp: +unix_ms+ is the time (Unix
      # milliseconds, within 100 years of now) the entity is stamped with.
      def setat(group, entity, unix_ms, values)
        @client.invoke("FEATURE.SETAT", group, entity, unix_ms, *flatten_kv(values)) { |r| r == "OK" }
      end

      def get(group, entity, features = nil)
        args = ["FEATURE.GET", group, entity]
        args.concat(Array(features)) if features
        @client.invoke(*args) { |r| result(r) }
      end

      def batch(group, entities, features: nil)
        args = ["FEATURE.BATCH", group, *entities]
        args.push("FEATURES", *features) if features
        @client.invoke(*args) { |r| r.map { |row| result(row) } }
      end

      def schema(group)
        @client.invoke("FEATURE.SCHEMA", group)
      end

      def list
        @client.invoke("FEATURE.LIST")
      end

      def drop(group)
        @client.invoke("FEATURE.DROP", group) { |r| r == "OK" }
      end

      def stats(group)
        @client.invoke("FEATURE.STATS", group) { |r| Commands::Support.pairs_to_h(r) }
      end

      private

      def flatten_kv(hash_or_pairs)
        hash_or_pairs.is_a?(Hash) ? hash_or_pairs.flatten(1) : hash_or_pairs.flatten
      end

      def result(row)
        return nil if row.nil?

        flat, updated_at_ms, freshness_ms = row
        { values: flat.each_slice(2).to_h, updated_at_ms: updated_at_ms, freshness_ms: freshness_ms }
      end
    end
  end
end
