# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Commands
    # Stream commands (XADD, consumer groups, claiming, trimming, XINFO).
    module Streams
      # +fields+ is a Hash or a flat [field, value, ...] list.
      #
      # Idempotent append: :idmp is a [producer, iid] pair, and the
      # same pair within the stream's IDMP-DURATION adds nothing and returns
      # the original entry id; :idmpauto is a producer name whose id is derived
      # from the fields. Both need id "*".
      def xadd(key, fields, id: "*", maxlen: nil, minid: nil, approx: true, nomkstream: false, limit: nil,
               idmp: nil, idmpauto: nil)
        args = ["XADD", key]
        args.push("NOMKSTREAM") if nomkstream
        args.push("IDMP", idmp[0], idmp[1]) if idmp
        args.push("IDMPAUTO", idmpauto) if idmpauto
        args.concat(trim_clause(maxlen, minid, approx, limit))
        args.push(id)
        args.concat(fields.is_a?(Hash) ? fields.flatten(1) : fields.flatten)
        invoke(*args)
      end

      # -> Array of [id, {field => value}] entries, oldest first.
      def xrange(key, start = "-", stop = "+", count: nil)
        args = ["XRANGE", key, start, stop]
        args.push("COUNT", count) if count
        invoke(*args) { |r| entries_to_pairs(r) }
      end

      def xrevrange(key, stop = "+", start = "-", count: nil)
        args = ["XREVRANGE", key, stop, start]
        args.push("COUNT", count) if count
        invoke(*args) { |r| entries_to_pairs(r) }
      end

      def xlen(key)
        invoke("XLEN", key)
      end

      def xdel(key, *ids)
        invoke("XDEL", key, *ids.flatten)
      end

      def xtrim(key, maxlen: nil, minid: nil, approx: true, limit: nil)
        invoke("XTRIM", key, *trim_clause(maxlen, minid, approx, limit))
      end

      # +keys+/+ids+ are parallel Arrays. -> Hash {stream_key => entries},
      # entries shaped like #xrange's result, or nil on timeout/no data.
      def xread(keys:, ids:, count: nil, block: nil)
        args = ["XREAD"]
        args.push("COUNT", count) if count
        args.push("BLOCK", block) if block
        args.push("STREAMS", *keys, *ids)
        invoke(*args) { |r| streams_to_h(r) }
      end

      def xreadgroup(group, consumer, keys:, ids:, count: nil, block: nil, noack: false)
        args = ["XREADGROUP", "GROUP", group, consumer]
        args.push("COUNT", count) if count
        args.push("BLOCK", block) if block
        args.push("NOACK") if noack
        args.push("STREAMS", *keys, *ids)
        invoke(*args) { |r| streams_to_h(r) }
      end

      def xack(key, group, *ids)
        invoke("XACK", key, group, *ids.flatten)
      end

      def xgroup_create(key, group, id = "$", mkstream: false)
        args = ["XGROUP", "CREATE", key, group, id]
        args.push("MKSTREAM") if mkstream
        invoke(*args) { |r| r == "OK" }
      end

      def xgroup_destroy(key, group)
        invoke("XGROUP", "DESTROY", key, group) { |r| r == 1 }
      end

      def xgroup_createconsumer(key, group, consumer)
        invoke("XGROUP", "CREATECONSUMER", key, group, consumer) { |r| r == 1 }
      end

      def xgroup_delconsumer(key, group, consumer)
        invoke("XGROUP", "DELCONSUMER", key, group, consumer)
      end

      def xgroup_setid(key, group, id = "$")
        invoke("XGROUP", "SETID", key, group, id) { |r| r == "OK" }
      end

      # No :start/:stop/:count -> summary Hash {count:, min_id:, max_id:,
      # consumers: [[name, pending_count], ...]}. With them -> an Array of
      # {id:, consumer:, idle_ms:, deliveries:} Hashes (the extended form).
      def xpending(key, group, start: nil, stop: nil, count: nil, consumer: nil, idle: nil)
        if start.nil? && stop.nil? && count.nil?
          invoke("XPENDING", key, group) { |r| pending_summary(r) }
        else
          args = ["XPENDING", key, group]
          args.push("IDLE", idle) if idle
          args.push(start || "-", stop || "+", count || 10)
          args.push(consumer) if consumer
          invoke(*args) { |r| pending_detail(r) }
        end
      end

      def xclaim(key, group, consumer, min_idle_time, *ids, idle: nil, time: nil, retrycount: nil, force: false,
                 justid: false)
        args = ["XCLAIM", key, group, consumer, min_idle_time, *ids.flatten]
        args.push("IDLE", idle) if idle
        args.push("TIME", time) if time
        args.push("RETRYCOUNT", retrycount) if retrycount
        args.push("FORCE") if force
        args.push("JUSTID") if justid
        invoke(*args) { |r| justid ? r : entries_to_pairs(r) }
      end

      # -> {cursor:, entries:, deleted:}. +entries+ is shaped like #xrange's
      # result unless :justid, in which case it is a plain Array of ids.
      def xautoclaim(key, group, consumer, min_idle_time, start = "0", count: nil, justid: false)
        args = ["XAUTOCLAIM", key, group, consumer, min_idle_time, start]
        args.push("COUNT", count) if count
        args.push("JUSTID") if justid
        invoke(*args) do |r|
          cursor, claimed, deleted = r
          { cursor: cursor, entries: justid ? claimed : entries_to_pairs(claimed), deleted: deleted || [] }
        end
      end

      def xinfo_stream(key)
        invoke("XINFO", "STREAM", key) { |r| to_h_any(r) }
      end

      def xinfo_groups(key)
        invoke("XINFO", "GROUPS", key) { |r| r.map { |g| to_h_any(g) } }
      end

      def xinfo_consumers(key, group)
        invoke("XINFO", "CONSUMERS", key, group) { |r| r.map { |c| to_h_any(c) } }
      end

      # Sets the last delivered id of +key+ (and optionally the entries added /
      # max deleted id counters).
      def xsetid(key, last_id, entriesadded: nil, maxdeletedid: nil)
        args = ["XSETID", key, last_id]
        args.push("ENTRIESADDED", entriesadded) if entriesadded
        args.push("MAXDELETEDID", maxdeletedid) if maxdeletedid
        invoke(*args) { |r| r == "OK" }
      end

      # Sets how long (:idmp_duration seconds) and how many (:idmp_maxsize)
      # idempotent ids a stream keeps per producer (XCFGSET).
      def xcfgset(key, idmp_duration: nil, idmp_maxsize: nil)
        args = ["XCFGSET", key]
        args.push("IDMP-DURATION", idmp_duration) if idmp_duration
        args.push("IDMP-MAXSIZE", idmp_maxsize) if idmp_maxsize
        invoke(*args) { |r| r == "OK" }
      end

      private

      def trim_clause(maxlen, minid, approx, limit)
        args = []
        if maxlen
          args.push("MAXLEN", approx ? "~" : "=", maxlen)
        elsif minid
          args.push("MINID", approx ? "~" : "=", minid)
        end
        args.push("LIMIT", limit) if limit && !args.empty?
        args
      end

      def entries_to_pairs(entries)
        return [] if entries.nil?

        entries.map { |(id, flat)| [id, flat.nil? ? nil : to_h_any(flat)] }
      end

      def streams_to_h(reply)
        return nil if reply.nil?

        pairs = reply.is_a?(Hash) ? reply.to_a : reply
        pairs.to_h { |(name, entries)| [name, entries_to_pairs(entries)] }
      end

      def to_h_any(r)
        r.is_a?(Hash) ? r : r.each_slice(2).to_h
      end

      def pending_summary(r)
        return { count: 0, min_id: nil, max_id: nil, consumers: [] } if r.nil? || r[0] == 0

        count, min_id, max_id, consumers = r
        { count: count, min_id: min_id, max_id: max_id,
          consumers: (consumers || []).map { |(name, pending)| [name, pending.to_i] } }
      end

      def pending_detail(r)
        (r || []).map { |(id, consumer, idle_ms, deliveries)| { id: id, consumer: consumer, idle_ms: idle_ms, deliveries: deliveries } }
      end
    end
  end
end
