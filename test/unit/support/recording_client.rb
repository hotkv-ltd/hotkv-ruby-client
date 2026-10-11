# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

# A minimal stand-in for HotKV::Client used by command unit tests: every
# Namespaces::* class only ever calls #invoke(*args, &block) on the client
# it is given, so this records the exact argument list of each call (to
# assert new options build the right wire arguments) and, when built with
# a canned +reply+, feeds it through the block a command method passes to
# #invoke (to assert parsing of canned RESP2/RESP3 replies), all without a
# live server. Includes HotKV::Commands::Extensions so HotKV::AI::PromptCache/
# SemanticCache (which call +client.pcache+/+client.scache+/+client.llmstats+,
# not #invoke directly) work against it too.
class RecordingClient
  include HotKV::Commands::Extensions

  attr_reader :calls

  def initialize(reply: nil)
    @calls = []
    @reply = reply
  end

  def invoke(*args)
    @calls << args
    block_given? ? yield(@reply) : @reply
  end

  def last_call
    @calls.last
  end
end
