# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  # Server side MULTI/EXEC transaction. Every command queued inside the
  # block given to HotKV::Client#multi (or HotKV::WatchSession#multi) is
  # sent to the server immediately and queued there; #exec runs EXEC and
  # resolves every queued command's Future from the resulting array.
  #
  #   result = client.multi do |tx|
  #     tx.set("a", "1")
  #     tx.incr("a")
  #   end
  #   result # => ["OK", 2], or nil if a watched key changed first
  class Transaction
    include Commands::All

    def initialize(connection)
      @connection = connection
      @queue = []
    end

    def command(*args, &transform)
      invoke(*args, &transform)
    end
    alias_method :call, :command

    # Sends +args+ to the server right away (MULTI is already active), so a
    # bad command is caught as soon as it is queued, exactly like the
    # server itself does.
    def invoke(*args, &transform)
      @connection.write_command(args)
      reply = @connection.read_reply(raise_on_error: false)
      future = Future.new(&transform)
      if reply.is_a?(Error::ServerError)
        future.resolve_error(reply)
        @queue << [true, future]
      else
        @queue << [false, future]
      end
      future
    end

    def size
      @queue.size
    end

    # Runs EXEC and resolves every queued Future. Returns a plain Array of
    # resolved values (or per command Error instances) in queue order, or
    # nil if the transaction was aborted because a watched key changed.
    def exec
      @connection.write_command(["EXEC"])
      raw = @connection.read_reply(raise_on_error: false)
      return nil if raw.nil?
      raise raw if raw.is_a?(Error::ServerError)

      idx = 0
      @queue.each do |(already_resolved, future)|
        next if already_resolved

        future.resolve(raw[idx])
        idx += 1
      end
      @queue.map { |(_resolved, future)| future.value }
    end
  end

  # Yielded by HotKV::Client#watch. Bound to a single connection for the
  # life of the watch block so that reads used to decide whether to
  # transact, and the eventual transaction itself, see a consistent view
  # and share the same WATCH state. Supports every typed command method
  # (run immediately against the watched connection) plus #multi to start
  # the actual MULTI/EXEC transaction.
  class WatchSession
    include Commands::All

    def initialize(connection)
      @connection = connection
      @multi_started = false
    end

    def multi_started?
      @multi_started
    end

    def invoke(*args)
      raw = @connection.call(*args, raise_on_error: false)
      raise raw if raw.is_a?(Error::ServerError)

      block_given? ? yield(raw) : raw
    end

    def command(*args)
      invoke(*args) { |raw| raw }
    end
    alias_method :call, :command

    # Starts MULTI on the watched connection, yields a Transaction to queue
    # commands on, and runs EXEC. Returns whatever Transaction#exec returns.
    def multi
      raise Error::ArgumentError, "multi requires a block" unless block_given?

      @connection.call("MULTI")
      @multi_started = true
      tx = Transaction.new(@connection)
      begin
        yield tx
      rescue StandardError
        @connection.call("DISCARD", raise_on_error: false)
        raise
      end
      tx.exec
    end
  end
end
