# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "lib/hotkv/version"

Gem::Specification.new do |spec|
  spec.name = "hotkv"
  spec.version = HotKV::VERSION
  spec.authors = ["HotKV Ltd"]
  spec.email = ["support@hotkv.com"]

  spec.summary = "A high-performance Ruby client for HotKV"
  spec.description = "A high-performance Ruby client for HotKV, a RESP2/RESP3-compatible in-memory data store with built-in AI and LLM-serving features."
  spec.homepage = "https://hotkv.com"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/hotkv-ltd/hotkv-ruby-client"
  spec.metadata["bug_tracker_uri"] = "https://github.com/hotkv-ltd/hotkv-ruby-client/issues"

  # An explicit list, independent of git: a clean checkout, a source tarball
  # and an unpacked gem all build the same file set (the library, the
  # README and the license; no tests, CI files or dev tooling).
  spec.files = Dir.glob("lib/**/*.rb", base: __dir__).sort +
               %w[README.md SECURITY.md LICENSE NOTICE]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bigdecimal", "~> 3.0"
  spec.add_development_dependency "minitest", "~> 5.20"
  spec.add_development_dependency "rake", "~> 13.1"

  spec.metadata["rubygems_mfa_required"] = "true"
end
