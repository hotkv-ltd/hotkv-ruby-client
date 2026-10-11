# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "support"
require_relative "strings"
require_relative "keys"
require_relative "lists"
require_relative "sets"
require_relative "hashes"
require_relative "sorted_sets"
require_relative "streams"
require_relative "geo"
require_relative "bitmaps"
require_relative "hyperloglog"
require_relative "server"
require_relative "scripting"
require_relative "scan"
require_relative "publishing"
require_relative "probabilistic"
require_relative "admin"
require_relative "../extensions"

module HotKV
  module Commands
    # Every standard command family, mixed
    # into HotKV::Client, HotKV::Cluster, HotKV::Pipeline,
    # HotKV::Transaction and HotKV::WatchSession alike. Each of these
    # classes only has to implement #invoke(*args, &transform) itself.
    module All
      include Strings
      include Keys
      include Lists
      include Sets
      include Hashes
      include SortedSets
      include Streams
      include Geo
      include Bitmaps
      include HyperLogLog
      include Server
      include Scripting
      include Scan
      include Publishing
      include Probabilistic
      include Admin
      include Extensions
    end
  end
end
