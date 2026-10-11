# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Commands
    # Small reply-shaping helpers shared by more than one command module.
    # Plain module functions (not mixed in) so every command module can
    # call them without fighting over method resolution order.
    module Support
      module_function

      # RESP3 sends a native boolean for some replies; RESP2 sends the
      # integer 0/1 for the same semantics. Normalizes either to a Ruby bool.
      def truthy(reply)
        reply == 1 || reply == true
      end

      # A member/score (or field/value, ...) reply comes back as a flat
      # array [m1, s1, m2, s2, ...] in RESP2, or already paired up as
      # [[m1, s1], [m2, s2], ...] in RESP3. Normalizes to the paired form,
      # coercing each pair's second element with +value+ (Float() by
      # default, since scores are the common case).
      def pairify(reply, &value)
        value ||= ->(v) { Wire.parse_float(v) }
        return [] if reply.nil?

        if !reply.empty? && reply.first.is_a?(Array)
          reply.map { |(k, v)| [k, value.call(v)] }
        else
          reply.each_slice(2).map { |(k, v)| [k, value.call(v)] }
        end
      end

      # Builds a Hash out of a HotKV fixed schema STATS/INFO reply, parsed
      # BY FIELD NAME rather than positionally:
      # a flat array of N pairs (name, value, name, value, ...) under
      # RESP2, or a native map (already a Hash, string keyed) under RESP3
      # (HELLO 3), which HotKV sends for these replies either way.
      # +float_keys+ names the symbol keys whose value should be coerced
      # with Float() instead of left as the server sent it (already an
      # Integer for RESP `:` replies).
      #
      # A missing field is simply absent from the returned Hash (callers
      # building a typed Struct fall back to its own defaults); an
      # unrecognized field whose value cannot be parsed as a number (a
      # server addition this SDK does not know how to coerce) keeps its
      # raw value instead of raising. This is what keeps every STATS/INFO
      # reply forward compatible with a server that adds fields.
      def pairs_to_h(reply, float_keys: [])
        h = {}
        if reply.is_a?(Hash)
          reply.each { |k, v| h[k.to_sym] = v }
        else
          (reply || []).each_slice(2) { |(k, v)| h[k.to_sym] = v }
        end
        float_keys.each do |k|
          next unless h.key?(k)

          begin
            h[k] = Wire.parse_float(h[k])
          rescue ArgumentError, TypeError
            nil # keep the raw value; an unknown/malformed field must never break decoding
          end
        end
        h
      end
    end
  end
end
