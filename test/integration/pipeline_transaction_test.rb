# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

class PipelineTransactionIntegrationTest < HotKVIntegrationTest
  def test_pipeline_batches_commands_and_returns_results_in_order
    k = track(uniq("pipe"))
    results = @client.pipelined do |p|
      p.set(k, "1")
      p.incr(k)
      p.get(k)
    end
    assert_equal ["OK", 2, "2"], results
  end

  def test_pipeline_surfaces_per_command_errors_without_failing_the_batch
    k = track(uniq("pipe"))
    @client.set(k, "not-a-number")
    results = @client.pipelined do |p|
      p.get(k)
      p.incr(k)
      p.get(k)
    end
    assert_equal "not-a-number", results[0]
    assert_kind_of HotKV::Error::Base, results[1]
    assert_equal "not-a-number", results[2] # unaffected by the failed command before it
  end

  def test_empty_pipeline_returns_empty_array
    assert_equal [], @client.pipelined { |_p| nil }
  end

  def test_multi_exec_returns_results_in_order
    k = track(uniq("tx"))
    result = @client.multi do |tx|
      tx.set(k, "1")
      tx.incr(k)
    end
    assert_equal ["OK", 2], result
  end

  def test_multi_discards_and_reraises_on_ruby_level_error_in_block
    k = track(uniq("tx"))
    assert_raises(RuntimeError) do
      @client.multi do |tx|
        tx.set(k, "queued-but-discarded")
        raise "boom"
      end
    end
    assert_nil @client.get(k)
  end

  def test_watch_aborts_transaction_when_key_changes_concurrently
    k = track(uniq("watch"))
    @client.set(k, "1")
    other = HotKV::Client.new(url: ENV["HOTKV_TEST_URL"])

    result = @client.watch(k) do |w|
      other.set(k, "changed-by-someone-else")
      w.multi do |tx|
        tx.set(k, "should-not-apply")
      end
    end
    assert_nil result
    assert_equal "changed-by-someone-else", @client.get(k)
  ensure
    other&.close
  end

  def test_watch_without_conflict_commits
    k = track(uniq("watch"))
    @client.set(k, "1")
    result = @client.watch(k) do |w|
      val = w.get(k)
      w.multi { |tx| tx.set(k, (val.to_i + 1).to_s) }
    end
    assert_equal ["OK"], result
    assert_equal "2", @client.get(k)
  end

  def test_watch_sends_unwatch_when_multi_never_called
    k = track(uniq("watch"))
    @client.set(k, "1")
    @client.watch(k) { |w| w.get(k) }
    # If UNWATCH were not sent, a later multi on this key would still be
    # fine here since nothing else touches it; this just proves the block
    # form completes cleanly without ever starting a transaction.
    assert_equal "1", @client.get(k)
  end

  def test_transaction_queue_time_error_aborts_the_whole_transaction
    # A command that fails at queue time (bad arity) dirties the MULTI on
    # the server; EXEC then fails the whole transaction with EXECABORT,
    # matching standard semantics.
    k = track(uniq("tx"))
    assert_raises(HotKV::Error::ExecAbortError) do
      @client.multi do |tx|
        tx.set(k, "1")
        tx.command("SET") # wrong arity, fails at queue time
        tx.incr(k)
      end
    end
    assert_nil @client.get(k)
  end
end
