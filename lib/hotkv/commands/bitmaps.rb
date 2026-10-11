# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Commands
    # Bitmap commands.
    module Bitmaps
      def setbit(key, offset, value)
        invoke("SETBIT", key, offset, value)
      end

      def getbit(key, offset)
        invoke("GETBIT", key, offset)
      end

      # :bit_mode selects BIT range indexing (byte indexing is the default).
      def bitcount(key, start = nil, stop = nil, bit_mode: false)
        args = ["BITCOUNT", key]
        if start
          args.push(start, stop)
          args.push("BIT") if bit_mode
        end
        invoke(*args)
      end

      def bitpos(key, bit, start = nil, stop = nil, bit_mode: false)
        args = ["BITPOS", key, bit]
        if start
          args.push(start)
          args.push(stop) if stop
          args.push("BIT") if bit_mode
        end
        invoke(*args)
      end

      def bitop(operation, destination, *source_keys)
        invoke("BITOP", operation, destination, *source_keys.flatten)
      end

      # Raw escape hatch for BITFIELD: pass the GET/SET/INCRBY/OVERFLOW
      # sub-operations exactly as the command syntax lists them, e.g.
      # bitfield("k", "INCRBY", "u8", 0, 10, "GET", "u8", 0).
      def bitfield(key, *operations)
        invoke("BITFIELD", key, *operations.flatten)
      end

      def bitfield_ro(key, *operations)
        invoke("BITFIELD_RO", key, *operations.flatten)
      end
    end
  end
end
