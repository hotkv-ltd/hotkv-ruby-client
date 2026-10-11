# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../namespaces/admin"

module HotKV
  module Commands
    # Accessors for the administrative command families: ACL (core) and the
    # licensed TENANT, IAM, AUDIT, ENCRYPTION and REPLICATION families.
    module Admin
      def acl
        @hotkv_ns_acl ||= Namespaces::ACL.new(self)
      end

      def tenant
        @hotkv_ns_tenant ||= Namespaces::Tenant.new(self)
      end

      def iam
        @hotkv_ns_iam ||= Namespaces::IAM.new(self)
      end

      def audit
        @hotkv_ns_audit ||= Namespaces::Audit.new(self)
      end

      def encryption
        @hotkv_ns_encryption ||= Namespaces::Encryption.new(self)
      end

      def replication
        @hotkv_ns_replication ||= Namespaces::Replication.new(self)
      end
    end
  end
end
