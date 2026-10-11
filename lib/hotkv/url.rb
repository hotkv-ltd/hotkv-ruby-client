# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require "uri"

module HotKV
  # Parses HotKV connection URLs into the option hash HotKV::Client#initialize
  # understands. Accepts the native `hotkv://` / `hotkvs://` (TLS) schemes and,
  # for drop in migration from other clients, `redis://` / `rediss://` and the
  # unix socket forms `hotkv+unix://` / `redis+unix://`.
  module URL
    TLS_SCHEMES = %w[hotkvs rediss].freeze
    PLAIN_SCHEMES = %w[hotkv redis].freeze
    UNIX_SCHEMES = %w[hotkv+unix redis+unix].freeze
    DEFAULT_PORT = 6379

    module_function

    # Returns a Hash of connection options parsed out of +url+, using only
    # the keys that were present in the URL. HotKV::Client merges this under
    # its explicit keyword options, so an explicit keyword always wins.
    def parse(url)
      raise Error::ArgumentError, "url must be a String, got #{url.class}" unless url.is_a?(String)

      uri = begin
        URI.parse(url)
      rescue URI::InvalidURIError => e
        raise Error::ArgumentError, "invalid HotKV URL #{url.inspect}: #{e.message}"
      end
      scheme = uri.scheme&.downcase
      opts = {}

      if UNIX_SCHEMES.include?(scheme)
        path = uri.path
        path = uri.opaque if path.nil? || path.empty?
        raise Error::ArgumentError, "#{scheme}:// URL must include a socket path" if path.nil? || path.empty?

        opts[:path] = path
      elsif TLS_SCHEMES.include?(scheme) || PLAIN_SCHEMES.include?(scheme)
        opts[:ssl] = TLS_SCHEMES.include?(scheme)
        opts[:host] = (uri.host && !uri.host.empty?) ? uri.host : "127.0.0.1"
        opts[:port] = uri.port || DEFAULT_PORT
      else
        raise Error::ArgumentError,
              "unsupported HotKV URL scheme #{uri.scheme.inspect}, expected hotkv://, hotkvs://, " \
              "redis://, rediss:// or a +unix variant"
      end

      apply_userinfo!(opts, uri.userinfo)
      apply_path_db!(opts, uri.path) unless UNIX_SCHEMES.include?(scheme)
      apply_query!(opts, uri.query)
      opts
    end

    def apply_userinfo!(opts, userinfo)
      return unless userinfo

      if userinfo.include?(":")
        user, pass = userinfo.split(":", 2)
      else
        user, pass = userinfo, nil
      end
      opts[:username] = URI.decode_www_form_component(user) if user && !user.empty?
      opts[:password] = URI.decode_www_form_component(pass) if pass
    end
    private_class_method :apply_userinfo!

    def apply_path_db!(opts, path)
      return if path.nil?

      db = path.sub(%r{\A/}, "")
      opts[:db] = Integer(db) unless db.empty?
    rescue ArgumentError
      raise Error::ArgumentError, "invalid database index in URL path #{path.inspect}"
    end
    private_class_method :apply_path_db!

    QUERY_BOOLEANS = %w[insecure_skip_verify skip_verify].freeze
    private_constant :QUERY_BOOLEANS

    def apply_query!(opts, query)
      return if query.nil? || query.empty?

      URI.decode_www_form(query).each do |key, value|
        case key
        when "db", "database" then opts[:db] = Integer(value)
        when "client_name", "clientname" then opts[:client_name] = value
        when "connect_timeout" then opts[:connect_timeout] = Float(value)
        when "timeout", "command_timeout", "read_timeout" then opts[:command_timeout] = Float(value)
        when "ca_file", "sslcacert" then opts[:ca_file] = value
        when "cert_file", "sslcert" then opts[:cert_file] = value
        when "key_file", "sslkey" then opts[:key_file] = value
        when "server_name", "sni" then opts[:server_name] = value
        when *QUERY_BOOLEANS then opts[:insecure_skip_verify] = %w[1 true yes].include?(value.to_s.downcase)
        end
      end
    end
    private_class_method :apply_query!
  end
end
