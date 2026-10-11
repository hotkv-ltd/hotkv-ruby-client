# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Commands
    # Generic key space and expiry commands.
    module Keys
      def del(*keys)
        invoke("DEL", *keys.flatten)
      end

      def unlink(*keys)
        invoke("UNLINK", *keys.flatten)
      end

      def exists(*keys)
        invoke("EXISTS", *keys.flatten)
      end

      def type(key)
        invoke("TYPE", key)
      end

      # Sets a relative TTL, in seconds. :nx/:xx/:gt/:lt mirror EXPIRE's
      # write condition flags.
      def expire(key, seconds, nx: false, xx: false, gt: false, lt: false)
        invoke(*expire_args("EXPIRE", key, seconds, nx, xx, gt, lt)) { |r| r == 1 }
      end

      def pexpire(key, milliseconds, nx: false, xx: false, gt: false, lt: false)
        invoke(*expire_args("PEXPIRE", key, milliseconds, nx, xx, gt, lt)) { |r| r == 1 }
      end

      def expireat(key, unix_seconds, nx: false, xx: false, gt: false, lt: false)
        invoke(*expire_args("EXPIREAT", key, unix_seconds, nx, xx, gt, lt)) { |r| r == 1 }
      end

      def pexpireat(key, unix_milliseconds, nx: false, xx: false, gt: false, lt: false)
        invoke(*expire_args("PEXPIREAT", key, unix_milliseconds, nx, xx, gt, lt)) { |r| r == 1 }
      end

      def ttl(key)
        invoke("TTL", key)
      end

      def pttl(key)
        invoke("PTTL", key)
      end

      def expiretime(key)
        invoke("EXPIRETIME", key)
      end

      def pexpiretime(key)
        invoke("PEXPIRETIME", key)
      end

      def persist(key)
        invoke("PERSIST", key) { |r| r == 1 }
      end

      def rename(key, new_key)
        invoke("RENAME", key, new_key) { |r| r == "OK" }
      end

      def renamenx(key, new_key)
        invoke("RENAMENX", key, new_key) { |r| r == 1 }
      end

      def keys(pattern = "*")
        invoke("KEYS", pattern)
      end

      def randomkey
        invoke("RANDOMKEY")
      end

      def dump(key)
        invoke("DUMP", key)
      end

      def restore(key, ttl, serialized_value, replace: false, absttl: false, idletime: nil, freq: nil)
        args = ["RESTORE", key, ttl, serialized_value]
        args.push("REPLACE") if replace
        args.push("ABSTTL") if absttl
        args.push("IDLETIME", idletime) if idletime
        args.push("FREQ", freq) if freq
        invoke(*args) { |r| r == "OK" }
      end

      def copy(source, destination, db: nil, replace: false)
        args = ["COPY", source, destination]
        args.push("DB", db) if db
        args.push("REPLACE") if replace
        invoke(*args) { |r| r == 1 }
      end

      def move(key, db)
        invoke("MOVE", key, db) { |r| r == 1 }
      end

      def touch(*keys)
        invoke("TOUCH", *keys.flatten)
      end

      def object_encoding(key)
        invoke("OBJECT", "ENCODING", key)
      end

      def object_refcount(key)
        invoke("OBJECT", "REFCOUNT", key)
      end

      def object_idletime(key)
        invoke("OBJECT", "IDLETIME", key)
      end

      def object_freq(key)
        invoke("OBJECT", "FREQ", key)
      end

      # SORT of a list, set or sorted set. :by is a pattern ("nosort" skips
      # sorting), :limit an [offset, count] pair, :get a pattern or Array of
      # patterns, :order "ASC"/"DESC", :alpha sorts lexicographically, :store
      # a destination key (then the reply is the stored element count).
      def sort(key, by: nil, limit: nil, get: nil, order: nil, alpha: false, store: nil)
        invoke(*sort_args("SORT", key, by, limit, get, order, alpha), *(store ? ["STORE", store] : []))
      end

      # Read-only SORT (no :store).
      def sort_ro(key, by: nil, limit: nil, get: nil, order: nil, alpha: false)
        invoke(*sort_args("SORT_RO", key, by, limit, get, order, alpha))
      end

      # Blocks until +numreplicas+ replicas acknowledge this connection's
      # writes or +timeout+ milliseconds pass. Returns the replica count.
      def wait(numreplicas, timeout)
        invoke("WAIT", numreplicas, timeout)
      end

      # WAITAOF: waits until writes are fsynced to the local AOF
      # (+numlocal+ 0 or 1) and to +numreplicas+ replicas' AOFs. Returns
      # [local_acks, replica_acks].
      def waitaof(numlocal, numreplicas, timeout)
        invoke("WAITAOF", numlocal, numreplicas, timeout)
      end

      private

      def sort_args(cmd, key, by, limit, get, order, alpha)
        args = [cmd, key]
        args.push("BY", by) unless by.nil?
        args.push("LIMIT", limit[0], limit[1]) if limit
        Array(get).each { |pattern| args.push("GET", pattern) }
        args.push(order.to_s.upcase) if order
        args.push("ALPHA") if alpha
        args
      end

      def expire_args(cmd, key, ttl, nx, xx, gt, lt)
        args = [cmd, key, ttl]
        args.push("NX") if nx
        args.push("XX") if xx
        args.push("GT") if gt
        args.push("LT") if lt
        args
      end
    end
  end
end
