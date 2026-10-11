# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../namespaces/probabilistic"

module HotKV
  module Commands
    # Bloom filter, Count-Min Sketch and Top-K accessors.
    module Probabilistic
      def bf
        @hotkv_ns_bf ||= Namespaces::BF.new(self)
      end

      def cms
        @hotkv_ns_cms ||= Namespaces::CMS.new(self)
      end

      def topk
        @hotkv_ns_topk ||= Namespaces::TopK.new(self)
      end
    end
  end
end
