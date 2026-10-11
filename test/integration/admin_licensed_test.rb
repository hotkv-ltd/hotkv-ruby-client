# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"

# Typed methods for the licensed administrative families (TENANT, IAM,
# AUDIT, ENCRYPTION, REPLICATION) and FEATURE.SETAT. Skipped cleanly (not
# failed) when the server is not licensed for them. Commands that change
# server-wide state (AUDIT.ROTATE, ENCRYPTION.ROTATE, REPLICATION.PAUSE/
# RESUME/FAILOVER, IAM.USER.ASSIGN/AUTH/SESSION.KILL) are covered by wire
# argument unit tests only, in test/unit/admin_commands_test.rb.
class AdminLicensedIntegrationTest < HotKVIntegrationTest
  def test_tenant_lifecycle
    skip_unless_licensed do
      id = "rbt#{Process.pid}#{rand(100_000)}"
      begin
        assert_equal true, @client.tenant.create(id, "Ruby test tenant", max_keys: 100, max_memory: 1_048_576)
        assert_includes @client.tenant.list, id
        info = @client.tenant.info(id)
        assert_equal id, info[:id]
        assert_equal "Ruby test tenant", info[:name]
        assert_equal "active", info[:state]
        stats = @client.tenant.stats(id)
        assert_equal 100, stats[:key_limit]
        assert_equal 1_048_576, stats[:memory_limit]
        assert_equal true, @client.tenant.suspend(id)
        assert_equal "suspended", @client.tenant.info(id)[:state]
        assert_equal true, @client.tenant.resume(id)
        assert_equal "active", @client.tenant.info(id)[:state]
        user = "rbtu#{Process.pid}"
        assert_equal true, @client.tenant.bind(id, user)
        assert_equal true, @client.tenant.unbind(id, user)
      ensure
        dropped = @client.tenant.drop(id)
      end
      assert_equal true, dropped
      assert_equal false, @client.tenant.drop(id)
      refute_includes @client.tenant.list, id
    end
  end

  def test_iam_role_lifecycle
    skip_unless_licensed do
      role = "rbrole#{Process.pid}#{rand(100_000)}"
      begin
        assert_equal true, @client.iam.role_create(role, %w[read write], key_prefixes: %w[a: b:], rate_limit: 500)
        assert_includes @client.iam.role_list, role
        info = @client.iam.role_info(role)
        assert_equal role, info[:name]
        assert_equal "read,write", info[:permissions]
        assert_equal 500, info[:rate_limit]
        assert_equal 0, info[:memory_quota]
        assert_kind_of Array, @client.iam.session_list
      ensure
        @client.iam.role_delete(role)
      end
      refute_includes @client.iam.role_list, role
    end
  end

  def test_audit_info_verify_export
    skip_unless_licensed do
      info = @client.audit.info
      assert_kind_of Integer, info[:total_entries]
      assert_includes [0, 1], info[:chain_valid]
      assert_match(/chain verified/, @client.audit.verify)
      path = "/tmp/rb-audit-export-#{Process.pid}-#{rand(100_000)}.jsonl"
      assert_equal true, @client.audit.export(path, format: "jsonl")
    end
  end

  def test_encryption_info
    skip_unless_licensed do
      info = @client.encryption.info
      assert_includes [0, 1], info[:enabled]
      assert_kind_of String, info[:algorithm]
      assert_kind_of String, info[:provider]
    end
  end

  def test_replication_info
    skip_unless_licensed do
      info = @client.replication.info
      assert_includes %w[primary replica master slave], info[:role]
      assert_kind_of Integer, info[:repl_offset]
      assert_kind_of Integer, info[:connected_replicas]
    end
  end

  def test_feature_setat_stamps_the_entity
    skip_unless_licensed do
      group = uniq("featsetat").tr(":.", "--")
      begin
        assert_equal true, @client.feature.create(group, "setat group", { "age" => "int64" })
        stamp = ((Time.now.to_f - 3600) * 1000).to_i
        assert_equal true, @client.feature.setat(group, "e1", stamp, { "age" => 41 })
        got = @client.feature.get(group, "e1")
        assert_equal 41, got[:values]["age"]
        assert_equal stamp, got[:updated_at_ms]
        assert_raises(HotKV::Error::ServerError) { @client.feature.setat(group, "e1", -5, { "age" => 1 }) }
      ensure
        @client.feature.drop(group)
      end
    end
  end
end
