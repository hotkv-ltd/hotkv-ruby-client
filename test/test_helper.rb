# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "hotkv"
require "minitest/autorun"
require "timeout"

# Base class for tests that need no server at all.
class HotKVUnitTest < Minitest::Test
end

# Base class for tests that need a live HotKV server, reached through
# HOTKV_TEST_URL. Skips itself (never fails) when that variable is unset,
# so `rake test:unit` (or plain `ruby -Ilib -Itest`) proves the unit suite
# passes standalone.
class HotKVIntegrationTest < Minitest::Test
  def setup
    skip "HOTKV_TEST_URL not set, skipping integration test" unless ENV["HOTKV_TEST_URL"]
    @client = HotKV::Client.new(url: ENV["HOTKV_TEST_URL"], **client_options)
    @cleanup_keys = []
  end

  def teardown
    return unless @client

    @client.del(*@cleanup_keys) unless @cleanup_keys.empty?
    @client.close
  end

  # Queue#pop(timeout:) only exists from Ruby 3.2; this works on every
  # supported Ruby. Returns nil when nothing arrived within +seconds+.
  def pop_within(queue, seconds)
    Timeout.timeout(seconds) { queue.pop }
  rescue Timeout::Error
    nil
  end

  # Registers +keys+ for deletion in #teardown and returns them (a single
  # key if one was given).
  def track(*keys)
    @cleanup_keys.concat(keys.flatten)
    keys.length == 1 ? keys.first : keys
  end

  # A key/namespace/session id unique to this test run, under a prefix
  # tests can recognize in server side listings.
  def uniq(label)
    "hotkv-rbtest:#{label}:#{Process.pid}:#{monotonic_id}"
  end

  # Runs the block and skips the test (instead of failing it) if the
  # server replies NOLICENSE, i.e. the feature is not included in the
  # license the server was started with.
  def skip_unless_licensed
    yield
  rescue HotKV::Error::NotLicensedError => e
    skip "server license does not enable this feature: #{e.message}"
  end

  private

  # HOTKV_TEST_RESP3=0 runs the whole integration suite over RESP2 (the
  # client negotiates RESP3 with HELLO 3 by default).
  def client_options
    ENV["HOTKV_TEST_RESP3"] == "0" ? { resp3: false } : {}
  end

  def monotonic_id
    @@monotonic_counter ||= 0
    @@monotonic_counter += 1
    "#{(Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i}-#{@@monotonic_counter}"
  end
end
