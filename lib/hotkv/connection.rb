# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require "socket"
require "openssl"
require "timeout"

module HotKV
  # A single RESP2/RESP3 socket connection to one HotKV server. Handles TCP
  # and unix socket transport, TLS, HELLO 3 negotiation with RESP2 fallback,
  # authentication, database selection and per operation timeouts. Not safe
  # for concurrent use by multiple threads; HotKV::Pool is what makes the
  # client thread safe.
  class Connection
    attr_reader :resp3
    attr_accessor :last_used_at

    def initialize(options)
      @options = options
      @socket = nil
      @resp3 = false
      @last_used_at = nil
    end

    def connected?
      !@socket.nil?
    end

    # Opens the socket, negotiates the protocol and authenticates. Returns
    # self so callers can chain `Connection.new(opts).connect`.
    def connect
      @socket = open_socket
      negotiate_protocol
      select_db
      @last_used_at = now
      self
    rescue StandardError
      close
      raise
    end

    def close
      @socket&.close
    rescue IOError, SystemCallError
      nil
    ensure
      @socket = nil
    end

    # Sends one command and returns its decoded reply.
    def call(*args, raise_on_error: true)
      write_command(args)
      read_reply(raise_on_error: raise_on_error)
    end

    def write_command(args)
      with_timeout(@options[:command_timeout]) { @socket.write(RESP.encode_command(args)) }
    rescue IOError, SystemCallError, OpenSSL::SSL::SSLError => e
      close
      raise Error::ConnectionError, "write failed: #{e.message}"
    end

    def read_reply(raise_on_error: true)
      value = with_timeout(@options[:command_timeout]) { RESP.read_reply(@socket, raise_on_error: raise_on_error) }
      @last_used_at = now
      value
    rescue IOError, SystemCallError, OpenSSL::SSL::SSLError => e
      close
      raise Error::ConnectionError, "read failed: #{e.message}"
    rescue Error::ProtocolError, Error::ConnectionError
      close
      raise
    end

    # Raw IO access for pipelines/pub-sub, which read several replies for
    # a batch of commands they wrote themselves.
    def io
      @socket
    end

    def ping
      call("PING")
    end

    def idle_seconds
      return 0 if @last_used_at.nil?

      now - @last_used_at
    end

    private

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def with_timeout(seconds)
      return yield if seconds.nil? || seconds <= 0

      Timeout.timeout(seconds, Error::TimeoutError, "operation timed out after #{seconds}s") { yield }
    rescue Error::TimeoutError
      close
      raise
    end

    def open_socket
      raw = with_timeout(@options[:connect_timeout]) { open_raw_socket }
      raw.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1) if raw.is_a?(TCPSocket)
      @options[:ssl] ? wrap_tls(raw) : raw
    rescue Error::TimeoutError
      raise
    rescue SystemCallError, IOError, SocketError => e
      raise Error::ConnectionError, "connect failed: #{e.message}"
    end

    def open_raw_socket
      if @options[:path]
        UNIXSocket.new(@options[:path])
      else
        TCPSocket.new(@options[:host], @options[:port])
      end
    end

    # Wraps +raw+ in TLS. Unless :insecure_skip_verify is set the server's
    # certificate chain is verified (against :ca_file when given, else the
    # system trust store) and the certificate must match the host name, or the
    # IP address, being connected to (:server_name overrides the name checked).
    # The handshake counts against :connect_timeout.
    def wrap_tls(raw)
      ssl = nil
      host = @options[:server_name] || @options[:host]
      ssl = OpenSSL::SSL::SSLSocket.new(raw, tls_context)
      ssl.hostname = host
      ssl.sync_close = true
      with_timeout(@options[:connect_timeout]) do
        ssl.connect
        ssl.post_connection_check(host) unless @options[:insecure_skip_verify]
      end
      ssl
    rescue OpenSSL::SSL::SSLError, SystemCallError, IOError => e
      close_quietly(ssl || raw)
      raise Error::ConnectionError, "TLS handshake failed: #{e.message}"
    rescue Error::TimeoutError
      close_quietly(ssl || raw)
      raise
    end

    def tls_context
      ctx = OpenSSL::SSL::SSLContext.new
      if @options[:insecure_skip_verify]
        ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
      else
        ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
        if @options[:ca_file]
          ctx.ca_file = @options[:ca_file]
        else
          ctx.cert_store = OpenSSL::X509::Store.new.tap(&:set_default_paths)
        end
      end
      ctx.cert = OpenSSL::X509::Certificate.new(File.read(@options[:cert_file])) if @options[:cert_file]
      ctx.key = OpenSSL::PKey.read(File.read(@options[:key_file])) if @options[:key_file]
      ctx
    end

    def close_quietly(io)
      io&.close
    rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
      nil
    end

    def negotiate_protocol
      # :resp3 defaults to true (HELLO 3, falling back to RESP2 only when
      # the server rejects it); set to false to use RESP2 even against a
      # server that does support RESP3.
      if @options.fetch(:resp3, true) == false
        @resp3 = false
        legacy_handshake
        return
      end

      write_command(hello_args)
      reply = read_reply(raise_on_error: false)
      if reply.is_a?(Error::ServerError)
        raise reply unless hello_unsupported?(reply)

        @resp3 = false
        legacy_handshake
      else
        @resp3 = true
      end
    end

    def hello_args
      args = ["HELLO", "3"]
      args.push("AUTH", @options[:username] || "default", @options[:password]) if @options[:password]
      args.push("SETNAME", @options[:client_name]) if @options[:client_name]
      args
    end

    def hello_unsupported?(err)
      err.code == "NOPROTO" || (err.code == "ERR" && err.server_message =~ /unknown command/i)
    end

    def legacy_handshake
      if @options[:password]
        if @options[:username]
          call("AUTH", @options[:username], @options[:password])
        else
          call("AUTH", @options[:password])
        end
      end
      call("CLIENT", "SETNAME", @options[:client_name]) if @options[:client_name]
    end

    def select_db
      return unless @options[:db] && !@options[:db].zero?

      call("SELECT", @options[:db])
    end
  end
end
