# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Commands
    # SCAN family: one-shot cursor calls plus Enumerator based iterators
    # that page through an entire key space, hash, set or sorted set.
    module Scan
      # -> [next_cursor, keys]. next_cursor is "0" once the scan completes.
      def scan(cursor = "0", match: nil, count: nil, type: nil)
        args = ["SCAN", cursor]
        args.push("MATCH", match) if match
        args.push("COUNT", count) if count
        args.push("TYPE", type) if type
        invoke(*args)
      end

      # Enumerator over every key, paging with SCAN until exhausted.
      def scan_each(match: nil, count: nil, type: nil, &block)
        return to_enum(:scan_each, match: match, count: count, type: type) unless block

        each_scan_page(:scan, [], match: match, count: count, type: type) { |page| page.each(&block) }
      end

      def hscan(key, cursor = "0", match: nil, count: nil, novalues: false)
        args = ["HSCAN", key, cursor]
        args.push("MATCH", match) if match
        args.push("COUNT", count) if count
        args.push("NOVALUES") if novalues
        invoke(*args)
      end

      def hscan_each(key, match: nil, count: nil, &block)
        return to_enum(:hscan_each, key, match: match, count: count) unless block

        each_scan_page(:hscan, [key], match: match, count: count) { |page| page.each_slice(2) { |(f, v)| yield f, v } }
      end

      def sscan(key, cursor = "0", match: nil, count: nil)
        args = ["SSCAN", key, cursor]
        args.push("MATCH", match) if match
        args.push("COUNT", count) if count
        invoke(*args)
      end

      def sscan_each(key, match: nil, count: nil, &block)
        return to_enum(:sscan_each, key, match: match, count: count) unless block

        each_scan_page(:sscan, [key], match: match, count: count) { |page| page.each(&block) }
      end

      def zscan(key, cursor = "0", match: nil, count: nil)
        args = ["ZSCAN", key, cursor]
        args.push("MATCH", match) if match
        args.push("COUNT", count) if count
        invoke(*args)
      end

      def zscan_each(key, match: nil, count: nil, &block)
        return to_enum(:zscan_each, key, match: match, count: count) unless block

        each_scan_page(:zscan, [key], match: match, count: count) do |page|
          page.each_slice(2) { |(m, s)| yield m, Wire.parse_float(s) }
        end
      end

      private

      def each_scan_page(method, prefix_args, match:, count:, type: nil, novalues: nil)
        cursor = "0"
        loop do
          kwargs = { match: match, count: count }
          kwargs[:type] = type if method == :scan
          kwargs[:novalues] = novalues if method == :hscan && !novalues.nil?
          cursor, page = public_send(method, *prefix_args, cursor, **kwargs)
          yield page
          break if cursor == "0"
        end
      end
    end
  end
end
