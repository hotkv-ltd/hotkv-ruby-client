# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Error
    # Root of every error the SDK raises.
    class Base < StandardError
    end

    # Could not establish, or lost, a connection to a server.
    class ConnectionError < Base
    end

    # A connect, read, write or command timeout elapsed.
    class TimeoutError < Base
    end

    # The server sent bytes that do not form a valid RESP2/RESP3 reply.
    class ProtocolError < Base
    end

    # The URL, option hash or command arguments given to the client are invalid.
    class ArgumentError < Base
    end

    # Base class for every `-ERR`/`-<CODE> ...` and RESP3 blob error (`!`)
    # reply the server sends back for a command. `code` is the leading
    # error token (e.g. "WRONGTYPE", "NOLICENSE", "ERR"); `server_message`
    # is the full text the server sent.
    class ServerError < Base
      attr_reader :code, :server_message

      def initialize(code, server_message)
        @code = code
        @server_message = server_message
        super(server_message)
      end

      # Parses a raw error line (without the leading "-"/"!" type byte and
      # without the trailing CRLF) into the most specific ServerError
      # subclass known for its leading code word.
      def self.from_message(message)
        code, = message.split(" ", 2)
        code ||= ""
        klass = CODES[code] || CommandError
        if klass <= ClusterRedirectError
          klass.parse(code, message)
        else
          klass.new(code, message)
        end
      end
    end

    # Generic `-ERR ...` (and any other unrecognized code) reply.
    class CommandError < ServerError
    end

    # `WRONGTYPE Operation against a key holding the wrong kind of value`
    class WrongTypeError < ServerError
    end

    # `NOAUTH Authentication required.`
    class NoAuthError < ServerError
    end

    # `WRONGPASS invalid username-password pair`
    class WrongPassError < ServerError
    end

    # An enterprise/HotKV command whose license feature is not included
    # in the currently loaded license. Distinct from every other server
    # error so callers (and tests) can detect and skip on it.
    class NotLicensedError < ServerError
    end

    # `READONLY You can't write against a read only replica.`
    class ReadOnlyError < ServerError
    end

    # `EXECABORT Transaction discarded because of a previous error.`
    class ExecAbortError < ServerError
    end

    # `NOSCRIPT No matching script.` Used internally to trigger EVAL fallback.
    class NoScriptError < ServerError
    end

    # `CLUSTERDOWN The cluster is down.`
    class ClusterDownError < ServerError
    end

    # `TRYAGAIN` transient cluster error, safe to retry shortly.
    class TryAgainError < ServerError
    end

    # `CROSSSLOT Keys in request don't hash to the same slot.`
    class CrossSlotError < ServerError
    end

    # Base for the two cluster redirection replies, MOVED and ASK. Carries
    # the parsed hash slot and destination address.
    class ClusterRedirectError < ServerError
      attr_reader :slot, :host, :port

      def initialize(code, server_message, slot, host, port)
        @slot = slot
        @host = host
        @port = port
        super(code, server_message)
      end

      def self.parse(code, message)
        # "<CODE> <slot> <host>:<port>"
        _, slot, hostport = message.split(" ")
        host, port = hostport.to_s.rpartition(":").values_at(0, 2)
        new(code, message, slot.to_i, host, port.to_i)
      end
    end

    # `MOVED <slot> <host>:<port>`: the slot now permanently lives elsewhere.
    class MovedError < ClusterRedirectError
    end

    # `ASK <slot> <host>:<port>`: the slot is mid migration, retry once
    # against the target node after sending it ASKING.
    class AskError < ClusterRedirectError
    end

    CODES = {
      "WRONGTYPE" => WrongTypeError,
      "NOAUTH" => NoAuthError,
      "WRONGPASS" => WrongPassError,
      "NOLICENSE" => NotLicensedError,
      "READONLY" => ReadOnlyError,
      "EXECABORT" => ExecAbortError,
      "NOSCRIPT" => NoScriptError,
      "CLUSTERDOWN" => ClusterDownError,
      "TRYAGAIN" => TryAgainError,
      "CROSSSLOT" => CrossSlotError,
      "MOVED" => MovedError,
      "ASK" => AskError
    }.freeze
    private_constant :CODES
  end
end
