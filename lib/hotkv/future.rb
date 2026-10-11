# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

module HotKV
  # Placeholder for the typed result of a command queued inside a pipeline
  # or transaction. Every typed command method (get, hgetall, zrange, ...)
  # is written once, in terms of #invoke, and works unchanged whether
  # #invoke runs the command immediately (HotKV::Client) or queues it and
  # hands back a Future to be resolved once the batch runs
  # (HotKV::Pipeline, HotKV::Transaction). Not part of the public API:
  # Pipeline#execute and Transaction#exec always resolve every Future
  # before returning, so callers only ever see plain values or, for a
  # command that itself failed, the HotKV::Error instance in its place.
  class Future
    def initialize(&transform)
      @transform = transform
      @resolved = false
      @value = nil
    end

    # +raw+ is the decoded reply for this command, or a HotKV::Error::ServerError
    # instance if the command itself failed. The transform block (the same
    # block a typed command method passes to #invoke) never runs on an
    # error reply, so it can assume a well formed raw value.
    def resolve(raw)
      @value = if raw.is_a?(Error::ServerError)
                 raw
               else
                 @transform ? @transform.call(raw) : raw
               end
      @resolved = true
      self
    rescue StandardError => e
      @value = e
      @resolved = true
      self
    end

    def resolve_error(err)
      @value = err
      @resolved = true
      self
    end

    def resolved?
      @resolved
    end

    def value
      raise Error::Base, "future has not been resolved yet" unless @resolved

      @value
    end
  end
end
