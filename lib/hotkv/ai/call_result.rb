# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module AI
    # Shared by PromptCache/SemanticCache: the block given to #get_or_call
    # may return either just the response, or a [response, usage] pair, so
    # a real model call can report its actual token usage only once it has
    # run.
    module CallResult
      module_function

      # Detected by the second element's type alone (never just "is a
      # 2 element Array"), so it stays unambiguous no matter what the
      # response itself looks like.
      def split_usage(result)
        if result.is_a?(Array) && result.length == 2 && result[1].is_a?(TokenUsage)
          result
        else
          [result, nil]
        end
      end
    end
  end
end
