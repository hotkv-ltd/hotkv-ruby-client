# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require "socket"
require "openssl"

# A tiny RESP server on 127.0.0.1 for client unit tests. Every request (an
# Array of Strings) is recorded in #requests and answered with the String the
# handler block returns (raw RESP bytes: "+OK\r\n", "-MOVED ...\r\n"). HELLO
# gets an "unknown command" error so the client falls back to RESP2.
class FakeServer
  attr_reader :port, :requests

  # +ssl_context+ (an OpenSSL::SSL::SSLContext with a certificate) makes it a TLS server.
  def initialize(ssl_context: nil, &handler)
    @handler = handler
    @requests = []
    @lock = Mutex.new
    @tcp = TCPServer.new("127.0.0.1", 0)
    @port = @tcp.addr[1]
    @server = ssl_context ? OpenSSL::SSL::SSLServer.new(@tcp, ssl_context) : @tcp
    @sockets = []
    @thread = Thread.new { accept_loop }
  end

  def addr
    "127.0.0.1:#{@port}"
  end

  def commands
    @lock.synchronize { @requests.map { |r| r.first.upcase }.reject { |c| c == "HELLO" } }
  end

  def stop
    @thread.kill
    @server.close
    @tcp.close unless @tcp.closed?
    @lock.synchronize { @sockets.each { |s| s.close rescue nil } }
  end

  def self.bulk(str)
    "$#{str.bytesize}\r\n#{str}\r\n"
  end

  private

  def accept_loop
    loop do
      client = begin
        @server.accept
      rescue OpenSSL::SSL::SSLError
        next # a failed handshake (the test expects the client to be refused)
      end
      @lock.synchronize { @sockets << client }
      Thread.new(client) { |sock| serve(sock) }
    end
  rescue IOError, SystemCallError
    nil
  end

  def serve(sock)
    while (request = read_request(sock))
      @lock.synchronize { @requests << request }
      reply = request.first.upcase == "HELLO" ? "-ERR unknown command 'HELLO'\r\n" : @handler.call(request, self)
      sock.write(reply)
    end
  rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
    nil
  ensure
    sock.close rescue nil
  end

  def read_request(sock)
    line = sock.gets("\r\n")
    return nil if line.nil?

    count = line[1..].to_i
    Array.new(count) do
      len = sock.gets("\r\n")[1..].to_i
      data = sock.read(len)
      sock.read(2)
      data
    end
  end
end
