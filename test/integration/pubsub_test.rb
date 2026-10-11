# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class PubSubIntegrationTest < HotKVIntegrationTest
  def test_subscribe_receives_published_messages_then_unsubscribes
    channel = uniq("chan")
    received = Queue.new
    subscribed = Queue.new

    thread = Thread.new do
      @client.subscribe(channel) do |on|
        on.subscribe { |ch, _count| subscribed << ch }
        on.message do |ch, payload|
          received << [ch, payload]
          on.unsubscribe
        end
      end
    end

    pop_within(subscribed, 5) || raise("subscribe confirmation timed out")
    publisher = HotKV::Client.new(url: ENV["HOTKV_TEST_URL"])
    publisher.command("PUBLISH", channel, "hello")

    ch, payload = pop_within(received, 5) || raise("message timed out")
    assert_equal channel, ch
    assert_equal "hello", payload
    assert thread.join(5), "subscribe loop should return once unsubscribed"
  ensure
    publisher&.close
  end

  def test_psubscribe_matches_pattern
    prefix = uniq("pat")
    pattern = "#{prefix}.*"
    received = Queue.new

    thread = Thread.new do
      @client.psubscribe(pattern) do |on|
        on.psubscribe { |_pat, _count| received << :ready }
        on.pmessage do |_pat, ch, payload|
          received << [ch, payload]
          on.punsubscribe
        end
      end
    end
    pop_within(received, 5)

    publisher = HotKV::Client.new(url: ENV["HOTKV_TEST_URL"])
    publisher.command("PUBLISH", "#{prefix}.news", "world")

    ch, payload = pop_within(received, 5)
    assert_equal "#{prefix}.news", ch
    assert_equal "world", payload
    thread.join(5)
  ensure
    publisher&.close
  end

  def test_ssubscribe_receives_shard_messages
    channel = uniq("schan")
    received = Queue.new

    thread = Thread.new do
      @client.ssubscribe(channel) do |on|
        on.ssubscribe { |_ch, _count| received << [:ready] }
        on.smessage { |ch, payload| received << [:smessage, ch, payload]; on.sunsubscribe }
      end
    end
    pop_within(received, 5)

    publisher = HotKV::Client.new(url: ENV["HOTKV_TEST_URL"])
    publisher.command("SPUBLISH", channel, "shard-hello")

    frame = pop_within(received, 5)
    refute_nil frame, "never received a shard message frame"
    _kind, ch, payload = frame
    assert_equal channel, ch
    assert_equal "shard-hello", payload
    thread.join(5)
  ensure
    publisher&.close
  end
end
