# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  class Cluster
    # CRC16/XMODEM (poly 0x1021, init 0, no reflection, no final xor) and the
    # cluster key slot algorithm built on it: hash only the part of a
    # key between the first "{" and the next non-empty "}", when present.
    module CRC16
      SLOT_COUNT = 16_384

      module_function

      def crc16(bytes)
        crc = 0
        bytes.b.each_byte do |byte|
          crc = (crc ^ (byte << 8)) & 0xFFFF
          8.times do
            crc = ((crc & 0x8000) != 0) ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF
          end
        end
        crc
      end

      def key_slot(key)
        crc16(hash_tag(key)) % SLOT_COUNT
      end

      # Returns the substring of +key+ that participates in hashing: the
      # text strictly between the first "{" and the next "}" after it, or
      # the whole key when there is no such non-empty tag.
      def hash_tag(key)
        s = key.index("{")
        return key unless s

        e = key.index("}", s + 1)
        return key if e.nil? || e == s + 1

        key[(s + 1)...e]
      end
    end
  end
end
