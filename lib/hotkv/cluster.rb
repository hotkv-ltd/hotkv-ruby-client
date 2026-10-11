# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require "monitor"

module HotKV
  # Cluster aware HotKV client. Discovers the slot map with CLUSTER SLOTS,
  # routes each command to the node that owns its key's slot (CRC16 with
  # {hash tag} support), refreshes the map and retries on MOVED, and
  # follows ASK (sending ASKING first) without updating the map for the
  # one off redirect. Exposes the same typed command methods as
  # HotKV::Client, plus the #command/#execute escape hatch.
  #
  # Against a server that is not running in cluster mode (CLUSTER SLOTS
  # comes back empty), every command is simply routed to the configured
  # seed nodes in round robin, so the same client also works against a
  # single standalone server.
  class Cluster
    include Commands::All

    DEFAULT_MAX_REDIRECTS = 8

    # +urls+: one or more "hotkv://host:port" seed addresses (or option
    # Hashes with :host/:port). Remaining keyword options are the same
    # connection options HotKV::Client accepts and apply to every node.
    def initialize(urls:, **options)
      seeds = Array(urls)
      raise Error::ArgumentError, "Cluster.new requires at least one seed url" if seeds.empty?

      @base_options = options
      @seed_addrs = seeds.map { |u| seed_addr(u) }
      @max_redirects = options[:max_redirects] || DEFAULT_MAX_REDIRECTS
      # Reading from replicas (READONLY) is not supported: every command goes
      # to the node that owns the key's slot. Refuse the option rather than
      # silently ignore it.
      if options.key?(:readonly) || options.key?(:read_from)
        raise Error::ArgumentError, "HotKV::Cluster does not support reading from replicas (:readonly / :read_from)"
      end

      @lock = Monitor.new
      @pools = {}
      @slots = {}
      @rr = 0
      refresh_slots
    end

    def invoke(*args)
      raw = dispatch(args)
      block_given? ? yield(raw) : raw
    end

    # Generic escape hatch: sends any command, routed by its first argument.
    def command(*args)
      invoke(*args)
    end
    alias_method :execute, :command

    # Forces a slot map refresh from CLUSTER SLOTS.
    def refresh!
      refresh_slots
    end

    def known_nodes
      @lock.synchronize { @slots.values.uniq }
    end

    def close
      @lock.synchronize { @pools.each_value(&:shutdown) }
    end

    private

    KEYLESS_COMMANDS = %w[
      PING ECHO INFO TIME DBSIZE FLUSHDB FLUSHALL CONFIG CLIENT CLUSTER COMMAND SELECT HELLO AUTH
      SCAN SCRIPT EVAL EVALSHA FCALL FCALL_RO MULTI EXEC DISCARD WATCH UNWATCH SUBSCRIBE PSUBSCRIBE
      SSUBSCRIBE UNSUBSCRIBE PSUNSUBSCRIBE SUNSUBSCRIBE PUBLISH PUBSUB WAIT SAVE BGSAVE BGREWRITEAOF
      SHUTDOWN DEBUG MEMORY SLOWLOG LATENCY ACL
      OBSERVE ALERTS HOTKEYS ASKING
    ].freeze

    def seed_addr(u)
      opts = u.is_a?(String) ? URL.parse(u) : u
      "#{opts[:host]}:#{opts[:port]}"
    end

    def pool_for(addr)
      @lock.synchronize do
        @pools[addr] ||= begin
          host, _, port = addr.rpartition(":")
          Pool.new(@base_options.merge(host: host, port: port.to_i),
                    size: @base_options[:pool_size] || 5,
                    idle_timeout: @base_options[:idle_timeout] || 300,
                    pool_timeout: @base_options[:pool_timeout])
        end
      end
    end

    def next_seed
      @lock.synchronize do
        addr = @seed_addrs[@rr % @seed_addrs.size]
        @rr += 1
        addr
      end
    end

    # Reloads the slot table from CLUSTER SLOTS, asking the nodes already
    # known first and the seed urls after them; the first one that answers
    # wins, so a dead node never blocks a refresh while another is up.
    def refresh_slots
      candidates = (@lock.synchronize { @slots.values.uniq } + @seed_addrs).uniq
      last_error = nil
      candidates.each do |addr|
        begin
          raw = pool_for(addr).with_connection { |c| c.call("CLUSTER", "SLOTS", raise_on_error: false) }
        rescue Error::ConnectionError, Error::TimeoutError => e
          last_error = e
          next
        end
        return store_slots(raw, addr)
      end
      raise last_error if last_error
    end

    def store_slots(raw, answering_addr)
      new_slots = {}
      unless raw.is_a?(Error::ServerError) || raw.nil? || raw.empty?
        default_host = answering_addr.rpartition(":").first
        raw.each do |range|
          start_slot, end_slot, master = range[0], range[1], range[2]
          host = master[0].to_s.empty? ? default_host : master[0]
          node_addr = "#{host}:#{master[1]}"
          (start_slot..end_slot).each { |s| new_slots[s] = node_addr }
        end
      end
      @lock.synchronize { @slots = new_slots }
    end

    def target_addr(args)
      cmd = args[0].to_s.upcase
      key = args[1]
      return next_seed if key.nil? || KEYLESS_COMMANDS.include?(cmd)

      slot = CRC16.key_slot(key.to_s)
      @lock.synchronize { @slots[slot] } || next_seed
    end

    # "host:port" a MOVED/ASK points at. An empty host means "the node that
    # answered", as in cluster mode.
    def redirect_addr(reply, answering_addr)
      host = reply.host.to_s.empty? ? answering_addr.rpartition(":").first : reply.host
      "#{host}:#{reply.port}"
    end

    def dispatch(args, redirects: 0, asking_addr: nil)
      raise Error::ClusterDownError.new("CLUSTERDOWN", "too many redirects for this command") if redirects > @max_redirects

      addr = asking_addr || target_addr(args)
      reply =
        begin
          pool_for(addr).with_connection do |conn|
            conn.call("ASKING", raise_on_error: false) if asking_addr
            conn.call(*args, raise_on_error: false)
          end
        rescue Error::ConnectionError, Error::TimeoutError
          refresh_slots
          return dispatch(args, redirects: redirects + 1)
        end

      case reply
      when Error::MovedError
        refresh_slots
        moved_to = redirect_addr(reply, addr)
        @lock.synchronize { @slots[reply.slot] = moved_to } # MOVED is authoritative for its slot
        dispatch(args, redirects: redirects + 1)
      when Error::AskError
        dispatch(args, redirects: redirects + 1, asking_addr: redirect_addr(reply, addr))
      when Error::ServerError
        raise reply
      else
        reply
      end
    end
  end
end
