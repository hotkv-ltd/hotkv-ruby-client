# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Commands
    # String commands: GET/SET and friends.
    module Strings
      # Fetches the value of +key+, or nil when it does not exist.
      def get(key)
        invoke("GET", key)
      end

      # Sets +key+ to +value+. Options mirror the SET command: :ex/:px
      # (relative TTL, seconds/milliseconds), :exat/:pxat (absolute TTL,
      # unix seconds/milliseconds), :keepttl (keep the current TTL),
      # :nx/:xx (only set if absent/present), :get (return the previous
      # value instead of "OK"). :ifeq/:ifne compare the current string value
      # and :ifdeq/:ifdne its digest (see #digest); the write is skipped when
      # the condition fails. Returns "OK", the previous value (with :get), or
      # nil when :nx/:xx/:if* prevented the write.
      def set(key, value, ex: nil, px: nil, exat: nil, pxat: nil, keepttl: false, nx: false, xx: false, get: false,
              ifeq: nil, ifne: nil, ifdeq: nil, ifdne: nil)
        args = ["SET", key, value]
        args.push("EX", ex) if ex
        args.push("PX", px) if px
        args.push("EXAT", exat) if exat
        args.push("PXAT", pxat) if pxat
        args.push("KEEPTTL") if keepttl
        args.push("NX") if nx
        args.push("XX") if xx
        args.push("IFEQ", ifeq) unless ifeq.nil?
        args.push("IFNE", ifne) unless ifne.nil?
        args.push("IFDEQ", ifdeq) unless ifdeq.nil?
        args.push("IFDNE", ifdne) unless ifdne.nil?
        args.push("GET") if get
        invoke(*args)
      end

      def setnx(key, value)
        invoke("SETNX", key, value) { |r| r == 1 }
      end

      def setex(key, seconds, value)
        invoke("SETEX", key, seconds, value)
      end

      def psetex(key, milliseconds, value)
        invoke("PSETEX", key, milliseconds, value)
      end

      def getset(key, value)
        invoke("GETSET", key, value)
      end

      def getdel(key)
        invoke("GETDEL", key)
      end

      def getex(key, ex: nil, px: nil, exat: nil, pxat: nil, persist: false)
        args = ["GETEX", key]
        args.push("EX", ex) if ex
        args.push("PX", px) if px
        args.push("EXAT", exat) if exat
        args.push("PXAT", pxat) if pxat
        args.push("PERSIST") if persist
        invoke(*args)
      end

      def append(key, value)
        invoke("APPEND", key, value)
      end

      def strlen(key)
        invoke("STRLEN", key)
      end

      def incr(key)
        invoke("INCR", key)
      end

      def decr(key)
        invoke("DECR", key)
      end

      def incrby(key, amount)
        invoke("INCRBY", key, amount)
      end

      def decrby(key, amount)
        invoke("DECRBY", key, amount)
      end

      def incrbyfloat(key, amount)
        invoke("INCRBYFLOAT", key, Wire.finite(amount)) { |r| Wire.parse_float(r) }
      end

      def mget(*keys)
        invoke("MGET", *keys.flatten)
      end

      # Accepts either a Hash or an already flat [key, value, key, value...]
      # list.
      def mset(hash_or_pairs)
        invoke("MSET", *flatten_pairs(hash_or_pairs)) { |r| r == "OK" }
      end

      def msetnx(hash_or_pairs)
        invoke("MSETNX", *flatten_pairs(hash_or_pairs)) { |r| r == 1 }
      end

      def getrange(key, start, stop)
        invoke("GETRANGE", key, start, stop)
      end

      def setrange(key, offset, value)
        invoke("SETRANGE", key, offset, value)
      end

      # Deprecated alias of #getrange.
      def substr(key, start, stop)
        invoke("SUBSTR", key, start, stop)
      end

      # Longest common subsequence of two string keys. Without options returns
      # the subsequence; :len returns its length; :idx returns a Hash
      # {"matches" => [[[a_start, a_end], [b_start, b_end], (len)], ...],
      # "len" => n} (the match positions, with :withmatchlen the lengths;
      # :minmatchlen drops shorter matches).
      def lcs(key1, key2, len: false, idx: false, minmatchlen: nil, withmatchlen: false)
        args = ["LCS", key1, key2]
        args.push("LEN") if len
        args.push("IDX") if idx
        args.push("MINMATCHLEN", minmatchlen) if minmatchlen
        args.push("WITHMATCHLEN") if withmatchlen
        invoke(*args) { |r| idx && r.is_a?(Array) ? r.each_slice(2).to_h : r }
      end

      # Sets several keys in one step with one TTL (MSETEX). +pairs+
      # is a Hash or a flat [key, value, ...] list. Options: :nx/:xx (all or
      # none), and one of :ex/:px/:exat/:pxat/:keepttl. Returns true when the
      # keys were set, false when :nx/:xx prevented it.
      def msetex(pairs, nx: false, xx: false, ex: nil, px: nil, exat: nil, pxat: nil, keepttl: false)
        flat = flatten_pairs(pairs)
        args = ["MSETEX", flat.length / 2, *flat]
        args.push("NX") if nx
        args.push("XX") if xx
        args.push("EX", ex) if ex
        args.push("PX", px) if px
        args.push("EXAT", exat) if exat
        args.push("PXAT", pxat) if pxat
        args.push("KEEPTTL") if keepttl
        invoke(*args) { |r| r == 1 }
      end

      # Deletes +key+, or only when its string value meets a condition
      # (:ifeq/:ifne value, :ifdeq/:ifdne digest). Returns true when deleted.
      def delex(key, ifeq: nil, ifne: nil, ifdeq: nil, ifdne: nil)
        args = ["DELEX", key]
        args.push("IFEQ", ifeq) unless ifeq.nil?
        args.push("IFNE", ifne) unless ifne.nil?
        args.push("IFDEQ", ifdeq) unless ifdeq.nil?
        args.push("IFDNE", ifdne) unless ifdne.nil?
        invoke(*args) { |r| r == 1 }
      end

      # The XXH3-64 digest of the string at +key+ as 16 hex digits, or nil.
      def digest(key)
        invoke("DIGEST", key)
      end

      private

      def flatten_pairs(hash_or_pairs)
        hash_or_pairs.is_a?(Hash) ? hash_or_pairs.flatten(1) : hash_or_pairs.flatten(1)
      end
    end
  end
end
