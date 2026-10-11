# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require "monitor"

module HotKV
  # A bounded pool of HotKV::Connection objects, safe for concurrent use by
  # multiple threads. Connections idle for longer than +idle_timeout+
  # seconds are health checked with PING before being handed out again, and
  # discarded (not returned to the caller) if the check fails.
  class Pool
    def initialize(options, size:, idle_timeout:, pool_timeout:)
      @options = options
      @size = size
      @idle_timeout = idle_timeout
      @pool_timeout = pool_timeout
      @available = []
      @created = 0
      @monitor = Monitor.new
      @resource = @monitor.new_cond
      @shutdown = false
    end

    # Checks out a connection, yields it, and always returns it to the pool
    # (or discards it, if it turned out to be broken).
    def with_connection
      conn = checkout
      healthy = true
      begin
        yield conn
      rescue Error::ConnectionError, Error::TimeoutError
        healthy = false
        raise
      ensure
        if healthy
          checkin(conn)
        else
          conn.close
          @monitor.synchronize do
            @created -= 1
            @resource.signal
          end
        end
      end
    end

    def checkout(timeout: @pool_timeout)
      deadline = timeout ? monotonic_now + timeout : nil
      @monitor.synchronize do
        loop do
          raise Error::ConnectionError, "connection pool has been shut down" if @shutdown

          while (conn = @available.pop)
            if healthy?(conn)
              return conn
            else
              conn.close
              @created -= 1
            end
          end
          if @created < @size
            @created += 1
            break
          end
          wait_time = deadline ? deadline - monotonic_now : nil
          raise Error::ConnectionError, "timed out waiting for a pooled connection" if deadline && wait_time <= 0

          @resource.wait(wait_time)
        end
      end
      begin
        Connection.new(@options).connect
      rescue StandardError
        @monitor.synchronize do
          @created -= 1
          @resource.signal
        end
        raise
      end
    end

    def checkin(conn)
      @monitor.synchronize do
        if @shutdown || !conn.connected?
          conn.close
          @created -= 1
        else
          @available.push(conn)
        end
        @resource.signal
      end
    end

    def shutdown
      @monitor.synchronize do
        @shutdown = true
        @available.each(&:close)
        @available.clear
        @created = 0
        @resource.broadcast
      end
    end

    def size
      @monitor.synchronize { @created }
    end

    private

    def healthy?(conn)
      return false unless conn.connected?

      conn.ping if @idle_timeout && conn.idle_seconds > @idle_timeout
      true
    rescue Error::ConnectionError, Error::TimeoutError
      false
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
