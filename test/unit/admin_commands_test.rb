# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"
require_relative "support/recording_client"

# Exact wire arguments of the administrative and other typed commands that
# cannot safely be run against a server in use (they would change server
# wide state), checked against the documented command syntax. Not run
# against a live server; the live tests in test/integration cover the rest.
class AdminCommandsTest < HotKVUnitTest
  def rc(reply = "OK")
    c = RecordingClient.new(reply: reply)
    c.extend(HotKV::Commands::All)
    c
  end

  def wire(call)
    call.map { |a| HotKV::RESP.to_wire_string(a) }
  end

  def test_audit_rotate_and_export
    c = rc
    assert_equal true, c.audit.rotate
    assert_equal %w[AUDIT.ROTATE], wire(c.last_call)
    c.audit.export("/tmp/x.csv", format: "csv")
    assert_equal %w[AUDIT.EXPORT /tmp/x.csv FORMAT csv], wire(c.last_call)
  end

  def test_encryption_rotate_and_verify
    c = rc
    assert_equal true, c.encryption.rotate("/etc/hotkv/new.key")
    assert_equal %w[ENCRYPTION.ROTATE /etc/hotkv/new.key], wire(c.last_call)
    assert_equal true, rc(1).encryption.verify("/f")
    assert_equal false, rc(0).encryption.verify("/f")
  end

  def test_replication_control
    c = rc
    assert_equal true, c.replication.pause
    assert_equal %w[REPLICATION.PAUSE], wire(c.last_call)
    c.replication.resume
    assert_equal %w[REPLICATION.RESUME], wire(c.last_call)
    c.replication.failover
    assert_equal %w[REPLICATION.FAILOVER], wire(c.last_call)
  end

  def test_iam_user_assign_session_kill_auth_and_role_create
    c = rc
    c.iam.user_assign("alice", "analyst")
    assert_equal %w[IAM.USER.ASSIGN alice analyst], wire(c.last_call)
    c.iam.session_kill(7)
    assert_equal %w[IAM.SESSION.KILL 7], wire(c.last_call)
    c.iam.auth("local", "alice", "pw")
    assert_equal %w[IAM.AUTH local alice pw], wire(c.last_call)
    c.iam.role_create("analyst", "read,write", key_prefixes: %w[a: b:], rate_limit: 1000, memory_quota: 5)
    assert_equal %w[IAM.ROLE.CREATE analyst read,write KEY_PREFIXES a:,b: RATE_LIMIT 1000 MEMORY_QUOTA 5],
                 wire(c.last_call)
  end

  def test_tenant_create_arguments
    c = rc
    c.tenant.create("t1", "Team One", max_memory: 10, max_keys: 20, max_connections: 3, max_commands_sec: 4,
                                      max_databases: 5, max_egress: 6)
    expected = ["TENANT.CREATE", "t1", "Team One", "MAX_MEMORY", "10", "MAX_KEYS", "20", "MAX_CONNECTIONS", "3",
                "MAX_COMMANDS_SEC", "4", "MAX_DATABASES", "5", "MAX_EGRESS", "6"]
    assert_equal expected, wire(c.last_call)
  end

  def test_feature_setat
    c = rc
    c.feature.setat("g", "e", 1_700_000_000_000, { "age" => 3, "score" => 1.0e-05 })
    assert_equal %w[FEATURE.SETAT g e 1700000000000 age 3 score 0.00001], wire(c.last_call)
  end

  def test_client_connection_commands
    c = rc
    c.client_pause(5000, "WRITE")
    assert_equal %w[CLIENT PAUSE 5000 WRITE], wire(c.last_call)
    c.client_unblock(9, "ERROR")
    assert_equal %w[CLIENT UNBLOCK 9 ERROR], wire(c.last_call)
  end

  def test_cluster_refuses_replica_reads_instead_of_ignoring_the_option
    assert_raises(HotKV::Error::ArgumentError) { HotKV::Cluster.new(urls: ["hotkv://127.0.0.1:1"], readonly: true) }
    assert_raises(HotKV::Error::ArgumentError) { HotKV::Cluster.new(urls: ["hotkv://127.0.0.1:1"], read_from: :replica) }
  end
end
