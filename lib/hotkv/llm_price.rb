# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  # One LLMSTATS.PRICE table entry (the reply of
  # Namespaces::LLMStats#price_get, and each element of #price_list).
  # Prices are USD per 1,000,000 tokens. +source+ is "default" (built
  # in), "custom" (set with #price_set) or "unpriced" (an unknown model:
  # every price 0.0, not an error).
  LLMPrice = Struct.new(
    :model, :source, :priced, :retired, :input_usd_per_mtok, :output_usd_per_mtok,
    :cache_read_usd_per_mtok, :cache_write_5m_usd_per_mtok, :cache_write_1h_usd_per_mtok,
    keyword_init: true
  ) do
    def initialize(model: "", source: "", priced: false, retired: false, input_usd_per_mtok: 0.0,
                   output_usd_per_mtok: 0.0, cache_read_usd_per_mtok: 0.0,
                   cache_write_5m_usd_per_mtok: 0.0, cache_write_1h_usd_per_mtok: 0.0)
      super
    end

    # Builds an LLMPrice from a {field_name (Symbol) => value} Hash
    # already parsed by field name (see Commands::Support.pairs_to_h, with
    # +float_keys: HotKV::LLMPrice::FLOAT_FIELDS+); unknown keys are
    # ignored, missing ones fall back to this Struct's own defaults.
    # +priced+/+retired+ arrive as the server's integer 0/1 and are
    # normalized to true/false.
    def self.from_fields(fields)
      h = fields.select { |k, _| members.include?(k) }
      h[:priced] = Commands::Support.truthy(h[:priced]) if h.key?(:priced)
      h[:retired] = Commands::Support.truthy(h[:retired]) if h.key?(:retired)
      new(**h)
    end

    # Formats +value+ as the plain decimal string LLMSTATS.PRICE SET
    # requires: digits, optional ".", 1-6 fractional digits, no sign, no
    # exponent (see Wire.usd). A String is passed through unchanged (the
    # caller's own decimal string).
    def self.format_price(value)
      Wire.usd(value)
    end
  end

  # The 5 price fields' names, i.e. the bulk string decimal fields a
  # LLMSTATS.PRICE GET/LIST reply needs Float() coerced by
  # Commands::Support.pairs_to_h. Assigned here, rather than inside the
  # Struct.new block above, because a plain constant assignment inside a
  # Struct.new block target's the block's own lexical scope (this file's
  # top level), not the Struct subclass itself.
  LLMPrice::FLOAT_FIELDS = %i[
    input_usd_per_mtok output_usd_per_mtok cache_read_usd_per_mtok cache_write_5m_usd_per_mtok
    cache_write_1h_usd_per_mtok
  ].freeze
end
