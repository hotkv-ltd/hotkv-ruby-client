# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Commands
    # Set commands.
    module Sets
      def sadd(key, *members)
        invoke("SADD", key, *members.flatten)
      end

      def srem(key, *members)
        invoke("SREM", key, *members.flatten)
      end

      def smembers(key)
        invoke("SMEMBERS", key)
      end

      def sismember(key, member)
        invoke("SISMEMBER", key, member) { |r| Support.truthy(r) }
      end

      def smismember(key, *members)
        invoke("SMISMEMBER", key, *members.flatten) { |r| r.map { |m| Support.truthy(m) } }
      end

      def scard(key)
        invoke("SCARD", key)
      end

      def spop(key, count = nil)
        count ? invoke("SPOP", key, count) : invoke("SPOP", key)
      end

      def srandmember(key, count = nil)
        count ? invoke("SRANDMEMBER", key, count) : invoke("SRANDMEMBER", key)
      end

      def sinter(*keys)
        invoke("SINTER", *keys.flatten)
      end

      def sunion(*keys)
        invoke("SUNION", *keys.flatten)
      end

      def sdiff(*keys)
        invoke("SDIFF", *keys.flatten)
      end

      def sintercard(keys, limit: nil)
        args = ["SINTERCARD", keys.length, *keys]
        args.push("LIMIT", limit) if limit
        invoke(*args)
      end

      def sinterstore(destination, *keys)
        invoke("SINTERSTORE", destination, *keys.flatten)
      end

      def sunionstore(destination, *keys)
        invoke("SUNIONSTORE", destination, *keys.flatten)
      end

      def sdiffstore(destination, *keys)
        invoke("SDIFFSTORE", destination, *keys.flatten)
      end

      def smove(source, destination, member)
        invoke("SMOVE", source, destination, member) { |r| r == 1 }
      end
    end
  end
end
