# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  module Namespaces
    # ACL: users and their permissions (core, not licensed).
    class ACL
      def initialize(client)
        @client = client
      end

      # Creates or modifies a user. +rules+ are the ACL rule strings
      # ("on", ">password", "~pattern", "+get", ...); every rule applies or
      # none does.
      def setuser(username, *rules)
        @client.invoke("ACL", "SETUSER", username, *rules.flatten) { |r| r == "OK" }
      end

      # Hash of the user's flags, passwords (SHA-256 hex), commands, keys,
      # channels, databases and selectors; nil when the user does not exist.
      def getuser(username)
        @client.invoke("ACL", "GETUSER", username) { |r| r.nil? ? nil : hash_of(r) }
      end

      # Deletes users and disconnects their clients. Returns how many existed.
      def deluser(*usernames)
        @client.invoke("ACL", "DELUSER", *usernames.flatten)
      end

      # Every user as an ACL file line.
      def list
        @client.invoke("ACL", "LIST")
      end

      def users
        @client.invoke("ACL", "USERS")
      end

      # The user of the connection that runs it.
      def whoami
        @client.invoke("ACL", "WHOAMI")
      end

      # The categories, or the commands in +category+.
      def cat(category = nil)
        category ? @client.invoke("ACL", "CAT", category) : @client.invoke("ACL", "CAT")
      end

      # A random password of +bits+ bits (default 256) as hex.
      def genpass(bits = nil)
        bits ? @client.invoke("ACL", "GENPASS", bits) : @client.invoke("ACL", "GENPASS")
      end

      # Denied commands and failed logins (the newest +count+ entries).
      def log(count = nil)
        count ? @client.invoke("ACL", "LOG", count) : @client.invoke("ACL", "LOG")
      end

      def log_reset
        @client.invoke("ACL", "LOG", "RESET") { |r| r == "OK" }
      end

      # "OK" when +username+ may run the command, else the reason.
      def dryrun(username, *command)
        @client.invoke("ACL", "DRYRUN", username, *command.flatten)
      end

      private

      def hash_of(reply)
        reply.is_a?(Hash) ? reply : reply.each_slice(2).to_h
      end
    end

    # Multi-tenancy (TENANT.*, licensed).
    class Tenant
      def initialize(client)
        @client = client
      end

      # Creates tenant +id+ with display +name+ and optional limits.
      def create(id, name, max_memory: nil, max_keys: nil, max_connections: nil, max_commands_sec: nil,
                 max_databases: nil, max_egress: nil)
        args = ["TENANT.CREATE", id, name]
        args.push("MAX_MEMORY", max_memory) if max_memory
        args.push("MAX_KEYS", max_keys) if max_keys
        args.push("MAX_CONNECTIONS", max_connections) if max_connections
        args.push("MAX_COMMANDS_SEC", max_commands_sec) if max_commands_sec
        args.push("MAX_DATABASES", max_databases) if max_databases
        args.push("MAX_EGRESS", max_egress) if max_egress
        @client.invoke(*args) { |r| r == "OK" }
      end

      def drop(id)
        @client.invoke("TENANT.DROP", id) { |r| r == 1 || r == "OK" }
      end

      # Tenant ids.
      def list
        @client.invoke("TENANT.LIST")
      end

      # Hash with :id, :name, :state and the usage counters.
      def info(id)
        @client.invoke("TENANT.INFO", id) { |r| Commands::Support.pairs_to_h(r) }
      end

      # Hash of usage counters and limits (:memory_bytes, :memory_limit, ...).
      def stats(id)
        @client.invoke("TENANT.STATS", id) { |r| Commands::Support.pairs_to_h(r) }
      end

      def suspend(id)
        @client.invoke("TENANT.SUSPEND", id) { |r| r == "OK" }
      end

      def resume(id)
        @client.invoke("TENANT.RESUME", id) { |r| r == "OK" }
      end

      # Binds ACL user +username+ to tenant +tenant_id+.
      def bind(tenant_id, username)
        @client.invoke("TENANT.BIND", tenant_id, username) { |r| r == "OK" }
      end

      def unbind(tenant_id, username)
        @client.invoke("TENANT.UNBIND", tenant_id, username) { |r| r == 1 || r == "OK" }
      end
    end

    # Enterprise IAM roles and sessions (IAM.*, licensed).
    class IAM
      def initialize(client)
        @client = client
      end

      # +permissions+ is a comma separated String or an Array of command
      # patterns; :key_prefixes restricts the role to keys with those prefixes.
      def role_create(name, permissions, key_prefixes: nil, rate_limit: nil, memory_quota: nil)
        args = ["IAM.ROLE.CREATE", name, Array(permissions).join(",")]
        args.push("KEY_PREFIXES", Array(key_prefixes).join(",")) if key_prefixes
        args.push("RATE_LIMIT", rate_limit) if rate_limit
        args.push("MEMORY_QUOTA", memory_quota) if memory_quota
        @client.invoke(*args) { |r| r == "OK" }
      end

      def role_delete(name)
        @client.invoke("IAM.ROLE.DELETE", name) { |r| r == "OK" }
      end

      def role_list
        @client.invoke("IAM.ROLE.LIST")
      end

      # Hash with :name, :permissions (comma joined String), :rate_limit and
      # :memory_quota.
      def role_info(name)
        @client.invoke("IAM.ROLE.INFO", name) { |r| Commands::Support.pairs_to_h(r) }
      end

      def user_assign(username, rolename)
        @client.invoke("IAM.USER.ASSIGN", username, rolename) { |r| r == "OK" }
      end

      # Active sessions as an Array of Hashes (:id, :username, :commands).
      def session_list
        @client.invoke("IAM.SESSION.LIST") { |r| r.map { |s| Commands::Support.pairs_to_h(s) } }
      end

      def session_kill(session_id)
        @client.invoke("IAM.SESSION.KILL", session_id) { |r| r == "OK" }
      end

      # Authenticates +username+ against +source+ ("ldap", "oidc", "saml", or
      # anything else for local auth). Returns the session id.
      def auth(source, username, credential)
        @client.invoke("IAM.AUTH", source, username, credential)
      end
    end

    # Tamper evident audit log (AUDIT.*, licensed).
    class Audit
      def initialize(client)
        @client = client
      end

      # Hash with :total_entries, :file_size_bytes, :chain_valid (Integer
      # 0/1) and :last_sequence.
      def info
        @client.invoke("AUDIT.INFO") { |r| Commands::Support.pairs_to_h(r) }
      end

      # Verifies the whole hash chain. Returns the server's status line
      # ("OK chain verified"); raises ServerError when tampering is detected.
      def verify
        @client.invoke("AUDIT.VERIFY")
      end

      # Writes the log to +file+ on the server (+format+ "jsonl", "csv" or "cef").
      def export(file, format: nil)
        args = ["AUDIT.EXPORT", file]
        args.push("FORMAT", format) if format
        @client.invoke(*args) { |r| r == "OK" }
      end

      # Renames the current log with a timestamp suffix and starts a new one.
      def rotate
        @client.invoke("AUDIT.ROTATE") { |r| r == "OK" }
      end
    end

    # Encryption at rest (ENCRYPTION.*, licensed).
    class Encryption
      def initialize(client)
        @client = client
      end

      # Hash with :enabled (Integer 0/1), :algorithm and :provider.
      def info
        @client.invoke("ENCRYPTION.INFO") { |r| Commands::Support.pairs_to_h(r) }
      end

      # Switches snapshots to the 32 byte key in +new_key_file+ (a path on
      # the server).
      def rotate(new_key_file)
        @client.invoke("ENCRYPTION.ROTATE", new_key_file) { |r| r == "OK" }
      end

      # True when the encrypted file at +file+ (a server path) is intact.
      def verify(file)
        @client.invoke("ENCRYPTION.VERIFY", file) { |r| r == 1 }
      end
    end

    # Replication control (REPLICATION.*, licensed).
    class Replication
      def initialize(client)
        @client = client
      end

      # Hash with :role, :state, :repl_offset, :connected_replicas, ...
      def info
        @client.invoke("REPLICATION.INFO") { |r| Commands::Support.pairs_to_h(r) }
      end

      # Stops sending (primary) or applying (replica) writes.
      def pause
        @client.invoke("REPLICATION.PAUSE") { |r| r == "OK" }
      end

      def resume
        @client.invoke("REPLICATION.RESUME") { |r| r == "OK" }
      end

      # Promotes this replica to primary (without cluster mode).
      def failover
        @client.invoke("REPLICATION.FAILOVER") { |r| r == "OK" }
      end
    end
  end
end
