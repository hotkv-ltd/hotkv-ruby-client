# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Commands
    # Hash commands, including the per field expiry (HEXPIRE/HTTL) family.
    module Hashes
      # Accepts a Hash, or a flat [field, value, field, value, ...] list.
      def hset(key, hash_or_pairs)
        invoke("HSET", key, *flatten_pairs(hash_or_pairs))
      end

      def hsetnx(key, field, value)
        invoke("HSETNX", key, field, value) { |r| r == 1 }
      end

      def hget(key, field)
        invoke("HGET", key, field)
      end

      def hmget(key, *fields)
        invoke("HMGET", key, *fields.flatten)
      end

      # Normalizes to a Hash regardless of whether the server replied with
      # a RESP3 map or a RESP2 flat array.
      def hgetall(key)
        invoke("HGETALL", key) { |r| r.is_a?(Hash) ? r : r.each_slice(2).to_h }
      end

      def hdel(key, *fields)
        invoke("HDEL", key, *fields.flatten)
      end

      def hexists(key, field)
        invoke("HEXISTS", key, field) { |r| r == 1 }
      end

      def hlen(key)
        invoke("HLEN", key)
      end

      def hkeys(key)
        invoke("HKEYS", key)
      end

      def hvals(key)
        invoke("HVALS", key)
      end

      def hincrby(key, field, amount)
        invoke("HINCRBY", key, field, amount)
      end

      def hincrbyfloat(key, field, amount)
        invoke("HINCRBYFLOAT", key, field, Wire.finite(amount)) { |r| Wire.parse_float(r) }
      end

      def hstrlen(key, field)
        invoke("HSTRLEN", key, field)
      end

      def hrandfield(key, count = nil, withvalues: false)
        return invoke("HRANDFIELD", key) if count.nil?

        args = ["HRANDFIELD", key, count]
        args.push("WITHVALUES") if withvalues
        invoke(*args) { |r| withvalues ? Support.pairify(r) { |v| v } : r }
      end

      # Field level TTL (seconds). Returns one status Integer per field: 1
      # set, 0 condition not met, -2 no such field/key.
      def hexpire(key, seconds, *fields, nx: false, xx: false, gt: false, lt: false)
        invoke(*hfield_ttl_args("HEXPIRE", key, seconds, fields.flatten, nx, xx, gt, lt))
      end

      def hpexpire(key, milliseconds, *fields, nx: false, xx: false, gt: false, lt: false)
        invoke(*hfield_ttl_args("HPEXPIRE", key, milliseconds, fields.flatten, nx, xx, gt, lt))
      end

      def hexpireat(key, unix_seconds, *fields, nx: false, xx: false, gt: false, lt: false)
        invoke(*hfield_ttl_args("HEXPIREAT", key, unix_seconds, fields.flatten, nx, xx, gt, lt))
      end

      def hpexpireat(key, unix_milliseconds, *fields, nx: false, xx: false, gt: false, lt: false)
        invoke(*hfield_ttl_args("HPEXPIREAT", key, unix_milliseconds, fields.flatten, nx, xx, gt, lt))
      end

      def httl(key, *fields)
        invoke("HTTL", key, "FIELDS", fields.flatten.length, *fields.flatten)
      end

      def hpttl(key, *fields)
        invoke("HPTTL", key, "FIELDS", fields.flatten.length, *fields.flatten)
      end

      def hexpiretime(key, *fields)
        invoke("HEXPIRETIME", key, "FIELDS", fields.flatten.length, *fields.flatten)
      end

      def hpexpiretime(key, *fields)
        invoke("HPEXPIRETIME", key, "FIELDS", fields.flatten.length, *fields.flatten)
      end

      def hpersist(key, *fields)
        invoke("HPERSIST", key, "FIELDS", fields.flatten.length, *fields.flatten)
      end

      # Deprecated form of #hset that replies OK. Returns true.
      def hmset(key, hash_or_pairs)
        invoke("HMSET", key, *flatten_pairs(hash_or_pairs)) { |r| r == "OK" }
      end

      # Gets the values of +fields+ and deletes them atomically (HGETDEL). Returns the values in order, nil for a missing field.
      def hgetdel(key, *fields)
        flat = fields.flatten
        invoke("HGETDEL", key, "FIELDS", flat.length, *flat)
      end

      # Gets the values of +fields+ and sets (:ex/:px/:exat/:pxat) or removes
      # (:persist) their TTLs (HGETEX).
      def hgetex(key, *fields, ex: nil, px: nil, exat: nil, pxat: nil, persist: false)
        flat = fields.flatten
        args = ["HGETEX", key]
        args.push("EX", ex) if ex
        args.push("PX", px) if px
        args.push("EXAT", exat) if exat
        args.push("PXAT", pxat) if pxat
        args.push("PERSIST") if persist
        args.push("FIELDS", flat.length, *flat)
        invoke(*args)
      end

      # Sets fields, all or none, with an optional TTL (HSETEX).
      # +hash_or_pairs+ is a Hash or a flat [field, value, ...] list. :fnx
      # sets only when none of the fields exists, :fxx only when all do; TTL
      # is one of :ex/:px/:exat/:pxat/:keepttl. Returns true when set.
      def hsetex(key, hash_or_pairs, fnx: false, fxx: false, ex: nil, px: nil, exat: nil, pxat: nil, keepttl: false)
        flat = flatten_pairs(hash_or_pairs)
        args = ["HSETEX", key]
        args.push("FNX") if fnx
        args.push("FXX") if fxx
        args.push("EX", ex) if ex
        args.push("PX", px) if px
        args.push("EXAT", exat) if exat
        args.push("PXAT", pxat) if pxat
        args.push("KEEPTTL") if keepttl
        args.push("FIELDS", flat.length / 2, *flat)
        invoke(*args) { |r| r == 1 }
      end

      private

      def flatten_pairs(hash_or_pairs)
        hash_or_pairs.is_a?(Hash) ? hash_or_pairs.flatten(1) : hash_or_pairs.flatten(1)
      end

      def hfield_ttl_args(cmd, key, ttl, fields, nx, xx, gt, lt)
        args = [cmd, key, ttl]
        args.push("NX") if nx
        args.push("XX") if xx
        args.push("GT") if gt
        args.push("LT") if lt
        args.push("FIELDS", fields.length, *fields)
        args
      end
    end
  end
end
