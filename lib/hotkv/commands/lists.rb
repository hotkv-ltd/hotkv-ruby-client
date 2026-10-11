# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Commands
    # List commands.
    module Lists
      def lpush(key, *values)
        invoke("LPUSH", key, *values.flatten)
      end

      def rpush(key, *values)
        invoke("RPUSH", key, *values.flatten)
      end

      def lpushx(key, *values)
        invoke("LPUSHX", key, *values.flatten)
      end

      def rpushx(key, *values)
        invoke("RPUSHX", key, *values.flatten)
      end

      # Without :count, returns the popped element or nil. With :count,
      # returns an Array of popped elements (possibly empty) or nil when
      # the key does not exist.
      def lpop(key, count = nil)
        count ? invoke("LPOP", key, count) : invoke("LPOP", key)
      end

      def rpop(key, count = nil)
        count ? invoke("RPOP", key, count) : invoke("RPOP", key)
      end

      def llen(key)
        invoke("LLEN", key)
      end

      def lrange(key, start, stop)
        invoke("LRANGE", key, start, stop)
      end

      def lindex(key, index)
        invoke("LINDEX", key, index)
      end

      def lset(key, index, value)
        invoke("LSET", key, index, value) { |r| r == "OK" }
      end

      def linsert(key, where, pivot, value)
        invoke("LINSERT", key, where, pivot, value)
      end

      def lrem(key, count, value)
        invoke("LREM", key, count, value)
      end

      def ltrim(key, start, stop)
        invoke("LTRIM", key, start, stop) { |r| r == "OK" }
      end

      def rpoplpush(source, destination)
        invoke("RPOPLPUSH", source, destination)
      end

      def lmove(source, destination, wherefrom, whereto)
        invoke("LMOVE", source, destination, wherefrom, whereto)
      end

      def lpos(key, element, rank: nil, count: nil, maxlen: nil)
        args = ["LPOS", key, element]
        args.push("RANK", rank) if rank
        args.push("COUNT", count) if count
        args.push("MAXLEN", maxlen) if maxlen
        invoke(*args)
      end

      # -> [key, values] on success, or nil when every source list was empty.
      def lmpop(keys, where, count: nil)
        args = ["LMPOP", keys.length, *keys, where]
        args.push("COUNT", count) if count
        invoke(*args)
      end

      def blpop(*keys, timeout: 0)
        invoke("BLPOP", *keys.flatten, timeout)
      end

      def brpop(*keys, timeout: 0)
        invoke("BRPOP", *keys.flatten, timeout)
      end

      def blmove(source, destination, wherefrom, whereto, timeout: 0)
        invoke("BLMOVE", source, destination, wherefrom, whereto, timeout)
      end

      # Pops from the first non-empty list of +keys+ (LMPOP) or waits up to
      # +timeout+ seconds (BLMPOP). +where+ is "LEFT" or "RIGHT". Returns
      # [key, [elements]] or nil on timeout.
      def blmpop(keys, where, timeout: 0, count: nil)
        args = ["BLMPOP", timeout, keys.length, *keys, where]
        args.push("COUNT", count) if count
        invoke(*args)
      end

      # Deprecated blocking RPOPLPUSH.
      def brpoplpush(source, destination, timeout: 0)
        invoke("BRPOPLPUSH", source, destination, timeout)
      end
    end
  end
end
