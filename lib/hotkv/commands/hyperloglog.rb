# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Commands
    # HyperLogLog commands.
    module HyperLogLog
      def pfadd(key, *elements)
        invoke("PFADD", key, *elements.flatten) { |r| r == 1 }
      end

      def pfcount(*keys)
        invoke("PFCOUNT", *keys.flatten)
      end

      def pfmerge(destination, *source_keys)
        invoke("PFMERGE", destination, *source_keys.flatten) { |r| r == "OK" }
      end
    end
  end
end
