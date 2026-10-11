# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "hotkv/version"
require_relative "hotkv/errors"
require_relative "hotkv/url"
require_relative "hotkv/wire"
require_relative "hotkv/resp"
require_relative "hotkv/connection"
require_relative "hotkv/pool"
require_relative "hotkv/future"
require_relative "hotkv/usage"
require_relative "hotkv/llm_price"
require_relative "hotkv/commands/all"
require_relative "hotkv/pipeline"
require_relative "hotkv/transaction"
require_relative "hotkv/pubsub"
require_relative "hotkv/cluster/crc16"
require_relative "hotkv/cluster"
require_relative "hotkv/client"
require_relative "hotkv/ai/call_result"
require_relative "hotkv/ai/prompt_cache"
require_relative "hotkv/ai/semantic_cache"

# Official HotKV Ruby SDK. Start with HotKV::Client for a single server,
# or HotKV::Cluster for a HotKV Cluster deployment.
module HotKV
end
