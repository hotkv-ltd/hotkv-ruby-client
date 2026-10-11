# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Commands
    # Server and connection commands.
    module Server
      def ping(message = nil)
        message ? invoke("PING", message) : invoke("PING")
      end

      def echo(message)
        invoke("ECHO", message)
      end

      def info(section = nil)
        section ? invoke("INFO", section) : invoke("INFO")
      end

      def dbsize
        invoke("DBSIZE")
      end

      def flushdb(async: false)
        args = ["FLUSHDB"]
        args.push(async ? "ASYNC" : "SYNC")
        invoke(*args) { |r| r == "OK" }
      end

      def flushall(async: false)
        args = ["FLUSHALL"]
        args.push(async ? "ASYNC" : "SYNC")
        invoke(*args) { |r| r == "OK" }
      end

      def time
        invoke("TIME") { |r| [Integer(r[0]), Integer(r[1])] }
      end

      def lastsave
        invoke("LASTSAVE")
      end

      def config_get(parameter)
        invoke("CONFIG", "GET", parameter) { |r| r.is_a?(Hash) ? r : r.each_slice(2).to_h }
      end

      def config_set(parameter, value)
        invoke("CONFIG", "SET", parameter, value) { |r| r == "OK" }
      end

      def config_resetstat
        invoke("CONFIG", "RESETSTAT") { |r| r == "OK" }
      end

      def client_setname(name)
        invoke("CLIENT", "SETNAME", name) { |r| r == "OK" }
      end

      def client_getname
        invoke("CLIENT", "GETNAME")
      end

      def client_id
        invoke("CLIENT", "ID")
      end

      def client_info
        invoke("CLIENT", "INFO")
      end

      def client_list
        invoke("CLIENT", "LIST")
      end

      def select(db)
        invoke("SELECT", db) { |r| r == "OK" }
      end

      def swapdb(index1, index2)
        invoke("SWAPDB", index1, index2) { |r| r == "OK" }
      end

      # Replication role: ["master", offset, [[host, port, offset], ...]] or
      # ["slave", host, port, state, offset].
      def role
        invoke("ROLE")
      end

      # Saves a snapshot now, blocking the server until done.
      def save
        invoke("SAVE") { |r| r == "OK" }
      end

      # Saves a snapshot in the background. Returns the status line.
      def bgsave(schedule: false)
        schedule ? invoke("BGSAVE", "SCHEDULE") : invoke("BGSAVE")
      end

      # Rewrites the append-only file in the background. Returns the status line.
      def bgrewriteaof
        invoke("BGREWRITEAOF")
      end

      # Slow log entries (the newest +count+, default 10).
      def slowlog_get(count = nil)
        count ? invoke("SLOWLOG", "GET", count) : invoke("SLOWLOG", "GET")
      end

      def slowlog_len
        invoke("SLOWLOG", "LEN")
      end

      def slowlog_reset
        invoke("SLOWLOG", "RESET") { |r| r == "OK" }
      end

      # Bytes used by the value at +key+ (nil if missing); :samples limits
      # the nested elements sampled.
      def memory_usage(key, samples: nil)
        samples ? invoke("MEMORY", "USAGE", key, "SAMPLES", samples) : invoke("MEMORY", "USAGE", key)
      end

      # Number of commands the server knows.
      def command_count
        invoke("COMMAND", "COUNT")
      end

      # The keys +command+ (a full command line as separate arguments) touches.
      def command_getkeys(*command)
        invoke("COMMAND", "GETKEYS", *command.flatten)
      end

      # Suspends client command processing for +milliseconds+ on the whole
      # server. +mode+ is "WRITE" or "ALL". Lift it with #client_unpause.
      def client_pause(milliseconds, mode = nil)
        mode ? invoke("CLIENT", "PAUSE", milliseconds, mode) { |r| r == "OK" } : invoke("CLIENT", "PAUSE", milliseconds) { |r| r == "OK" }
      end

      def client_unpause
        invoke("CLIENT", "UNPAUSE") { |r| r == "OK" }
      end

      # Marks the pooled connection that runs it as exempt from (or subject
      # to) client eviction. +enabled+ true/false. Applies to one pooled
      # connection only, so it is mostly useful on a pool_size 1 client.
      def client_no_evict(enabled)
        invoke("CLIENT", "NO-EVICT", enabled ? "ON" : "OFF") { |r| r == "OK" }
      end

      # As #client_no_evict, for the LRU/LFU touch on reads.
      def client_no_touch(enabled)
        invoke("CLIENT", "NO-TOUCH", enabled ? "ON" : "OFF") { |r| r == "OK" }
      end

      # CLIENT SETINFO LIB-NAME / LIB-VER on the pooled connection that runs it.
      def client_setinfo(attribute, value)
        invoke("CLIENT", "SETINFO", attribute, value) { |r| r == "OK" }
      end

      # Unblocks the client blocked with id +client_id+. +reason+ is
      # "TIMEOUT" or "ERROR". Returns true when a client was unblocked.
      def client_unblock(client_id, reason = nil)
        args = ["CLIENT", "UNBLOCK", client_id]
        args.push(reason) if reason
        invoke(*args) { |r| r == 1 }
      end

      # Closes the connection with id +client_id+. Returns the number closed.
      def client_kill_id(client_id)
        invoke("CLIENT", "KILL", "ID", client_id)
      end
    end
  end
end
