# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Commands
    # Sorted set commands, including the BYSCORE/BYLEX/REV/LIMIT ZRANGE
    # family and the RESP3 array-of-pairs WITHSCORES shape.
    module SortedSets
      # +score_members+ is a Hash {member => score}, or a flat/paired list
      # of scores and members: zadd("k", 1, "a", 2, "b") or
      # zadd("k", [1, "a"], [2, "b"]).
      def zadd(key, *score_members, nx: false, xx: false, gt: false, lt: false, ch: false, incr: false)
        args = ["ZADD", key]
        args.push("NX") if nx
        args.push("XX") if xx
        args.push("GT") if gt
        args.push("LT") if lt
        args.push("CH") if ch
        args.push("INCR") if incr
        args.concat(flatten_score_members(score_members))
        invoke(*args) { |r| incr ? (r.nil? ? nil : Wire.parse_float(r)) : r }
      end

      def zrem(key, *members)
        invoke("ZREM", key, *members.flatten)
      end

      def zscore(key, member)
        invoke("ZSCORE", key, member) { |r| r.nil? ? nil : Wire.parse_float(r) }
      end

      def zmscore(key, *members)
        invoke("ZMSCORE", key, *members.flatten) { |r| r.map { |v| v.nil? ? nil : Wire.parse_float(v) } }
      end

      def zcard(key)
        invoke("ZCARD", key)
      end

      def zcount(key, min, max)
        invoke("ZCOUNT", key, min, max)
      end

      def zincrby(key, increment, member)
        invoke("ZINCRBY", key, increment, member) { |r| Wire.parse_float(r) }
      end

      # Modern ZRANGE, covering plain index range, BYSCORE, BYLEX, REV and
      # LIMIT (an [offset, count] pair, only valid with BYSCORE/BYLEX).
      # With :with_scores, returns an Array of [member, score] pairs
      # (paired up uniformly regardless of the RESP2/RESP3 wire shape).
      def zrange(key, start, stop, byscore: false, bylex: false, rev: false, limit: nil, with_scores: false)
        args = ["ZRANGE", key, start, stop]
        args.push("BYSCORE") if byscore
        args.push("BYLEX") if bylex
        args.push("REV") if rev
        args.push("LIMIT", limit[0], limit[1]) if limit
        args.push("WITHSCORES") if with_scores
        invoke(*args) { |r| with_scores ? Support.pairify(r) : r }
      end

      def zrangestore(destination, source, start, stop, byscore: false, bylex: false, rev: false, limit: nil)
        args = ["ZRANGESTORE", destination, source, start, stop]
        args.push("BYSCORE") if byscore
        args.push("BYLEX") if bylex
        args.push("REV") if rev
        args.push("LIMIT", limit[0], limit[1]) if limit
        invoke(*args)
      end

      def zrevrange(key, start, stop, with_scores: false)
        args = ["ZREVRANGE", key, start, stop]
        args.push("WITHSCORES") if with_scores
        invoke(*args) { |r| with_scores ? Support.pairify(r) : r }
      end

      def zrangebyscore(key, min, max, with_scores: false, limit: nil)
        args = ["ZRANGEBYSCORE", key, min, max]
        args.push("LIMIT", limit[0], limit[1]) if limit
        args.push("WITHSCORES") if with_scores
        invoke(*args) { |r| with_scores ? Support.pairify(r) : r }
      end

      def zrevrangebyscore(key, max, min, with_scores: false, limit: nil)
        args = ["ZREVRANGEBYSCORE", key, max, min]
        args.push("LIMIT", limit[0], limit[1]) if limit
        args.push("WITHSCORES") if with_scores
        invoke(*args) { |r| with_scores ? Support.pairify(r) : r }
      end

      def zrangebylex(key, min, max, limit: nil)
        args = ["ZRANGEBYLEX", key, min, max]
        args.push("LIMIT", limit[0], limit[1]) if limit
        invoke(*args)
      end

      def zrevrangebylex(key, max, min, limit: nil)
        args = ["ZREVRANGEBYLEX", key, max, min]
        args.push("LIMIT", limit[0], limit[1]) if limit
        invoke(*args)
      end

      def zlexcount(key, min, max)
        invoke("ZLEXCOUNT", key, min, max)
      end

      def zrank(key, member, with_score: false)
        args = ["ZRANK", key, member]
        args.push("WITHSCORE") if with_score
        invoke(*args) { |r| with_score ? (r.nil? ? nil : [r[0], Wire.parse_float(r[1])]) : r }
      end

      def zrevrank(key, member, with_score: false)
        args = ["ZREVRANK", key, member]
        args.push("WITHSCORE") if with_score
        invoke(*args) { |r| with_score ? (r.nil? ? nil : [r[0], Wire.parse_float(r[1])]) : r }
      end

      # No :count -> a single [member, score] Array, or nil if empty.
      # With :count -> an Array of [member, score] pairs (possibly empty).
      def zpopmin(key, count = nil)
        pop("ZPOPMIN", key, count)
      end

      def zpopmax(key, count = nil)
        pop("ZPOPMAX", key, count)
      end

      def zrandmember(key, count = nil, withscores: false)
        return invoke("ZRANDMEMBER", key) if count.nil?

        args = ["ZRANDMEMBER", key, count]
        args.push("WITHSCORES") if withscores
        invoke(*args) { |r| withscores ? Support.pairify(r) : r }
      end

      def zremrangebyrank(key, start, stop)
        invoke("ZREMRANGEBYRANK", key, start, stop)
      end

      def zremrangebyscore(key, min, max)
        invoke("ZREMRANGEBYSCORE", key, min, max)
      end

      def zremrangebylex(key, min, max)
        invoke("ZREMRANGEBYLEX", key, min, max)
      end

      def zunionstore(destination, keys, weights: nil, aggregate: nil)
        invoke(*zstore_args("ZUNIONSTORE", destination, keys, weights, aggregate))
      end

      def zinterstore(destination, keys, weights: nil, aggregate: nil)
        invoke(*zstore_args("ZINTERSTORE", destination, keys, weights, aggregate))
      end

      def zdiffstore(destination, keys)
        invoke("ZDIFFSTORE", destination, keys.length, *keys)
      end

      def zunion(keys, weights: nil, aggregate: nil, with_scores: false)
        invoke(*zset_op_args("ZUNION", keys, weights, aggregate, with_scores)) do |r|
          with_scores ? Support.pairify(r) : r
        end
      end

      def zinter(keys, weights: nil, aggregate: nil, with_scores: false)
        invoke(*zset_op_args("ZINTER", keys, weights, aggregate, with_scores)) do |r|
          with_scores ? Support.pairify(r) : r
        end
      end

      def zdiff(keys, with_scores: false)
        args = ["ZDIFF", keys.length, *keys]
        args.push("WITHSCORES") if with_scores
        invoke(*args) { |r| with_scores ? Support.pairify(r) : r }
      end

      def zintercard(keys, limit: nil)
        args = ["ZINTERCARD", keys.length, *keys]
        args.push("LIMIT", limit) if limit
        invoke(*args)
      end

      # Pops from the first non-empty sorted set of +keys+ (ZMPOP). +where+ is
      # "MIN" or "MAX". Returns [key, [[member, score], ...]] or nil.
      def zmpop(keys, where, count: nil)
        args = ["ZMPOP", keys.length, *keys, where]
        args.push("COUNT", count) if count
        invoke(*args) { |r| zmpop_reply(r) }
      end

      # Blocking ZMPOP: waits up to +timeout+ seconds. Same reply as #zmpop.
      def bzmpop(keys, where, timeout: 0, count: nil)
        args = ["BZMPOP", timeout, keys.length, *keys, where]
        args.push("COUNT", count) if count
        invoke(*args) { |r| zmpop_reply(r) }
      end

      # Blocking ZPOPMIN across +keys+. Returns [key, member, score] or nil.
      def bzpopmin(*keys, timeout: 0)
        invoke("BZPOPMIN", *keys.flatten, timeout) { |r| bzpop_reply(r) }
      end

      # Blocking ZPOPMAX across +keys+. Returns [key, member, score] or nil.
      def bzpopmax(*keys, timeout: 0)
        invoke("BZPOPMAX", *keys.flatten, timeout) { |r| bzpop_reply(r) }
      end

      private

      def zmpop_reply(reply)
        return nil if reply.nil?

        key, pairs = reply
        [key, pairs.map { |(member, score)| [member, Wire.parse_float(score)] }]
      end

      def bzpop_reply(reply)
        return nil if reply.nil?

        key, member, score = reply
        [key, member, Wire.parse_float(score)]
      end

      def pop(cmd, key, count)
        if count
          invoke(cmd, key, count) { |r| Support.pairify(r) }
        else
          invoke(cmd, key) { |r| (r.nil? || r.empty?) ? nil : [r[0], Wire.parse_float(r[1])] }
        end
      end

      def flatten_score_members(args)
        if args.length == 1 && args.first.is_a?(Hash)
          args.first.flat_map { |member, score| [score, member] }
        else
          args.flatten
        end
      end

      def zstore_args(cmd, destination, keys, weights, aggregate)
        args = [cmd, destination, keys.length, *keys]
        args.push("WEIGHTS", *weights) if weights
        args.push("AGGREGATE", aggregate) if aggregate
        args
      end

      def zset_op_args(cmd, keys, weights, aggregate, with_scores)
        args = [cmd, keys.length, *keys]
        args.push("WEIGHTS", *weights) if weights
        args.push("AGGREGATE", aggregate) if aggregate
        args.push("WITHSCORES") if with_scores
        args
      end
    end
  end
end
