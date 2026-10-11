# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  # Thread safe HotKV client: a bounded connection pool in front of the
  # typed command methods (every family in Commands::All), pipelines,
  # transactions, pub/sub and the raw #command/#execute escape hatch.
  #
  #   client = HotKV::Client.new(url: "hotkv://localhost:6379")
  #   client.set("k", "v")
  #   client.get("k") # => "v"
  #   client.close
  class Client
    include Commands::All

    DEFAULTS = {
      host: "127.0.0.1",
      port: 6379,
      path: nil,
      username: nil,
      password: nil,
      db: 0,
      client_name: nil,
      connect_timeout: 5.0,
      command_timeout: nil,
      pool_size: 5,
      idle_timeout: 300,
      pool_timeout: 5.0,
      ssl: false,
      insecure_skip_verify: false,
      ca_file: nil,
      cert_file: nil,
      key_file: nil,
      server_name: nil
    }.freeze

    # Best effort allowlist of read only commands safe to retry once after
    # a connection loss. Never includes a write (the container
    # commands CONFIG, CLIENT and SCRIPT are included only because their
    # state changing subcommands are idempotent).
    READONLY_COMMANDS = %w[
      GET MGET STRLEN EXISTS TYPE TTL PTTL EXPIRETIME PEXPIRETIME GETRANGE GETBIT
      BITCOUNT BITPOS LLEN LRANGE LINDEX LPOS SMEMBERS SISMEMBER SMISMEMBER SCARD SINTER SUNION
      SDIFF SINTERCARD SRANDMEMBER HGET HMGET HGETALL HKEYS HVALS HLEN HSTRLEN HEXISTS HRANDFIELD
      HTTL HPTTL HEXPIRETIME HPEXPIRETIME ZSCORE ZMSCORE ZCARD ZRANK ZREVRANK ZCOUNT ZLEXCOUNT
      ZRANGE ZRANGEBYSCORE ZRANGEBYLEX ZREVRANGE ZREVRANGEBYSCORE ZREVRANGEBYLEX ZRANDMEMBER
      ZUNION ZINTER ZDIFF ZINTERCARD KEYS SCAN HSCAN SSCAN ZSCAN RANDOMKEY DUMP OBJECT DBSIZE
      XRANGE XREVRANGE XLEN XREAD XINFO XPENDING GEOPOS GEODIST GEOHASH GEOSEARCH PFCOUNT PING
      ECHO TIME INFO CONFIG LASTSAVE CLIENT SCRIPT COMMAND
      LCS DIGEST SUBSTR SORT_RO GEORADIUS_RO GEORADIUSBYMEMBER_RO EVAL_RO EVALSHA_RO FCALL_RO ROLE
      BF.EXISTS BF.MEXISTS BF.CARD BF.INFO CMS.QUERY CMS.INFO TOPK.QUERY TOPK.COUNT TOPK.LIST TOPK.INFO
      VSIM.GET VSIM.SEARCH VSIM.INFO
      TAG.GET TAG.MEMBERS TAG.INTER TAG.COUNT TAG.EXISTS NTTL HOTKEYS
      OBSERVE
    ].freeze
    private_constant :READONLY_COMMANDS

    # +url+ ("hotkv://", "hotkvs://", or a redis:// equivalent) supplies
    # any options it encodes; explicit keyword options always win over
    # whatever the URL carried for the same setting.
    def initialize(url: nil, **options)
      merged = url ? URL.parse(url).merge(options) : options
      @options = DEFAULTS.merge(merged)
      @pool = Pool.new(@options, size: @options[:pool_size], idle_timeout: @options[:idle_timeout],
                                  pool_timeout: @options[:pool_timeout])
    end

    # Runs a command immediately and returns its decoded reply.
    def invoke(*args)
      raw = send_command(args)
      block_given? ? yield(raw) : raw
    end

    # Generic escape hatch: sends any command as given.
    def command(*args)
      invoke(*args)
    end
    alias_method :execute, :command

    # Batches every command queued inside the block into one round trip.
    # See HotKV::Pipeline.
    def pipelined
      raise Error::ArgumentError, "pipelined requires a block" unless block_given?

      @pool.with_connection do |conn|
        pipeline = Pipeline.new(conn)
        yield pipeline
        pipeline.execute
      end
    end

    # Runs a MULTI/EXEC transaction. See HotKV::Transaction. Returns the
    # Array of results, or nil if the transaction was aborted.
    def multi
      raise Error::ArgumentError, "multi requires a block" unless block_given?

      @pool.with_connection do |conn|
        conn.call("MULTI")
        tx = Transaction.new(conn)
        begin
          yield tx
        rescue StandardError
          conn.call("DISCARD", raise_on_error: false)
          raise
        end
        tx.exec
      end
    end

    # Watches +keys+ for changes, on one connection held for the whole
    # block. The yielded HotKV::WatchSession runs ordinary commands
    # immediately (to decide what to do) and offers #multi to start the
    # actual transaction once you are ready. UNWATCH is sent automatically
    # if the block never calls #multi.
    def watch(*keys)
      raise Error::ArgumentError, "watch requires a block" unless block_given?

      flat_keys = keys.flatten
      @pool.with_connection do |conn|
        conn.call("WATCH", *flat_keys) unless flat_keys.empty?
        session = WatchSession.new(conn)
        begin
          yield session
        ensure
          conn.call("UNWATCH", raise_on_error: false) unless session.multi_started?
        end
      end
    end

    # Subscribes to +channels+ on a dedicated (non pooled) connection and
    # blocks the calling thread, dispatching frames to the callbacks
    # registered on the HotKV::PubSub yielded to the block, until every
    # subscription ends. See HotKV::PubSub.
    def subscribe(*channels, &block)
      pubsub_loop("SUBSCRIBE", channels.flatten, &block)
    end

    def psubscribe(*patterns, &block)
      pubsub_loop("PSUBSCRIBE", patterns.flatten, &block)
    end

    def ssubscribe(*channels, &block)
      pubsub_loop("SSUBSCRIBE", channels.flatten, &block)
    end

    # Closes every pooled connection. The client can keep being used
    # afterward; new connections are opened on demand.
    def close
      @pool.shutdown
    end

    private

    def send_command(args)
      attempts = 0
      begin
        @pool.with_connection { |conn| conn.call(*args) }
      rescue Error::ConnectionError, Error::TimeoutError
        attempts += 1
        retry if attempts == 1 && READONLY_COMMANDS.include?(args[0].to_s.upcase)
        raise
      end
    end

    CONFIRM_KINDS = %w[subscribe unsubscribe psubscribe punsubscribe ssubscribe sunsubscribe].freeze
    private_constant :CONFIRM_KINDS

    def pubsub_loop(wire_cmd, targets)
      raise Error::ArgumentError, "#{wire_cmd} requires a block" unless block_given?
      raise Error::ArgumentError, "#{wire_cmd} needs at least one channel or pattern" if targets.empty?

      conn = Connection.new(@options).connect
      on = PubSub.new.bind(conn)
      yield on
      conn.write_command([wire_cmd, *targets])
      count = -1
      begin
        count = read_pubsub_frame(conn, on, count) while count != 0
      ensure
        conn.close
      end
      nil
    end

    def read_pubsub_frame(conn, on, count)
      frame = RESP.read_reply(conn.io, raise_on_error: false)
      kind = frame[0].to_s
      case kind
      when "message" then on.dispatch(:message, frame[1], frame[2])
      when "pmessage" then on.dispatch(:pmessage, frame[1], frame[2], frame[3])
      when "smessage" then on.dispatch(:smessage, frame[1], frame[2])
      else
        if CONFIRM_KINDS.include?(kind)
          on.dispatch(kind.to_sym, frame[1], frame[2])
          count = frame[2]
        end
      end
      count
    end
  end
end
