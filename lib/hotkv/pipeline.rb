# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  # Client side command batching: every command queued inside the block
  # given to HotKV::Client#pipelined is written to the server in one burst
  # and all replies are read back in one pass, cutting round trips to one.
  # Supports every typed command method the client does (Pipeline includes
  # the same command modules), plus the raw #command escape hatch.
  #
  #   results = client.pipelined do |p|
  #     p.set("a", "1")
  #     p.incr("a")
  #   end
  #   results # => ["OK", 2]
  #
  # A command that itself fails does not abort the batch: its slot in the
  # returned array holds the HotKV::Error instance instead of a value.
  class Pipeline
    include Commands::All

    def initialize(connection)
      @connection = connection
      @queue = []
    end

    # Queues a raw command, returning a Future resolved to its decoded
    # reply (or the error) once #execute runs.
    def command(*args, &transform)
      invoke(*args, &transform)
    end
    alias_method :call, :command

    def invoke(*args, &transform)
      future = Future.new(&transform)
      @queue << [args, future]
      future
    end

    def size
      @queue.size
    end

    # Writes every queued command and reads back every reply, in order.
    # Returns a plain Array of resolved values (or per command Error
    # instances); never raises for an individual command's failure.
    def execute
      return [] if @queue.empty?

      @queue.each { |(args, _future)| @connection.write_command(args) }
      @queue.each { |(_args, future)| future.resolve(@connection.read_reply(raise_on_error: false)) }
      @queue.map { |(_args, future)| future.value }
    ensure
      @queue = []
    end
  end
end
