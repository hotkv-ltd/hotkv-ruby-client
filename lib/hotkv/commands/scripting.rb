# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require "digest"

module HotKV
  module Commands
    # Lua scripting commands.
    module Scripting
      def eval_script(script, keys: [], args: [])
        invoke("EVAL", script, keys.length, *keys, *args)
      end

      # Runs EVALSHA for +sha+ (or Digest::SHA1.hexdigest(script) when
      # :script is given instead of :sha); on NOSCRIPT, falls back to a
      # plain EVAL of :script if one was given. The fallback only fires
      # for an immediate call (HotKV::Client, inside a #watch block); a
      # queued Pipeline/Transaction call cannot inspect its own reply
      # before the batch runs, so there it behaves like a plain EVALSHA.
      def evalsha(sha = nil, script: nil, keys: [], args: [])
        sha ||= Digest::SHA1.hexdigest(script)
        invoke("EVALSHA", sha, keys.length, *keys, *args)
      rescue Error::NoScriptError
        raise unless script

        invoke("EVAL", script, keys.length, *keys, *args)
      end

      def script_load(script)
        invoke("SCRIPT", "LOAD", script)
      end

      def script_exists(*shas)
        invoke("SCRIPT", "EXISTS", *shas.flatten) { |r| r.map { |v| v == 1 } }
      end

      def script_flush
        invoke("SCRIPT", "FLUSH") { |r| r == "OK" }
      end

      # Read-only EVAL (the script may not write).
      def eval_ro(script, keys: [], args: [])
        invoke("EVAL_RO", script, keys.length, *keys, *args)
      end

      # Read-only EVALSHA.
      def evalsha_ro(sha, keys: [], args: [])
        invoke("EVALSHA_RO", sha, keys.length, *keys, *args)
      end

      # Stops a running script (NOTBUSY if none is running).
      def script_kill
        invoke("SCRIPT", "KILL") { |r| r == "OK" }
      end

      # Calls a function registered by FUNCTION LOAD.
      def fcall(function, keys: [], args: [])
        invoke("FCALL", function, keys.length, *keys, *args)
      end

      # FCALL for a function flagged no-writes.
      def fcall_ro(function, keys: [], args: [])
        invoke("FCALL_RO", function, keys.length, *keys, *args)
      end

      # Loads a function library (`#!lua name=<lib>` header). Returns the
      # library name. :replace overwrites an existing library of that name.
      def function_load(code, replace: false)
        replace ? invoke("FUNCTION", "LOAD", "REPLACE", code) : invoke("FUNCTION", "LOAD", code)
      end

      def function_delete(library)
        invoke("FUNCTION", "DELETE", library) { |r| r == "OK" }
      end

      # Libraries as an Array of Hashes ("library_name", "engine",
      # "functions" => [{"name", "description", "flags"}], plus "library_code"
      # with :withcode).
      def function_list(libraryname: nil, withcode: false)
        args = ["FUNCTION", "LIST"]
        args.push("LIBRARYNAME", libraryname) if libraryname
        args.push("WITHCODE") if withcode
        invoke(*args) { |r| r.map { |lib| lib.is_a?(Hash) ? lib : function_entry(lib) } }
      end

      # Deletes every library. +mode+ is "ASYNC" or "SYNC".
      def function_flush(mode = nil)
        mode ? invoke("FUNCTION", "FLUSH", mode) { |r| r == "OK" } : invoke("FUNCTION", "FLUSH") { |r| r == "OK" }
      end

      # Serialized libraries (binary String) for #function_restore.
      def function_dump
        invoke("FUNCTION", "DUMP")
      end

      # Restores a #function_dump payload. +policy+: "APPEND", "REPLACE" or "FLUSH".
      def function_restore(payload, policy = nil)
        args = ["FUNCTION", "RESTORE", payload]
        args.push(policy) if policy
        invoke(*args) { |r| r == "OK" }
      end

      # Hash with "running_script" and "engines".
      def function_stats
        invoke("FUNCTION", "STATS") { |r| r.is_a?(Hash) ? r : { "running_script" => r[1], "engines" => engines_hash(r[3]) } }
      end

      # Stops a running function.
      def function_kill
        invoke("FUNCTION", "KILL") { |r| r == "OK" }
      end

      private

      def function_entry(flat)
        entry = flat.each_slice(2).to_h
        entry["functions"] = entry["functions"].map { |f| f.is_a?(Hash) ? f : f.each_slice(2).to_h } if entry["functions"]
        entry
      end

      def engines_hash(flat)
        return flat if flat.is_a?(Hash)

        flat.each_slice(2).to_h { |(name, stats)| [name, stats.is_a?(Hash) ? stats : stats.each_slice(2).to_h] }
      end
    end
  end
end
