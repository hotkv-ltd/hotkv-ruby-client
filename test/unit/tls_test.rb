# Copyright (c) 2026 HotKV Ltd
# Licensed under the Apache License, Version 2.0. See LICENSE in the project root.

require_relative "../test_helper"
require_relative "support/fake_server"
require "tempfile"

# TLS behavior of the client against a local TLS server with certificates
# made on the fly: the chain is verified against :ca_file (or the system
# store without one), the certificate must match the host or IP connected to
# (or :server_name), :insecure_skip_verify turns both off, a client
# certificate is presented for mutual TLS, and the handshake honors
# :connect_timeout.
class TLSTest < HotKVUnitTest
  def setup
    skip "the OpenSSL extension is not available" unless defined?(OpenSSL::X509::Certificate)
    @ca_key, @ca = make_ca("hotkv-test-ca")
    @files = []
    @servers = []
  end

  def teardown
    (@servers || []).each(&:stop)
    (@files || []).each(&:close!)
  end

  def make_ca(cn)
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    ef = OpenSSL::X509::ExtensionFactory.new(cert, cert)
    cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
    cert.add_extension(ef.create_extension("keyUsage", "keyCertSign, cRLSign", true))
    cert.sign(key, "SHA256")
    [key, cert]
  end

  # A leaf certificate signed by the test CA; +san+ like "IP:127.0.0.1,DNS:localhost".
  def issue(cn, san)
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = rand(2..1_000_000)
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer = @ca.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    ef = OpenSSL::X509::ExtensionFactory.new(@ca, cert)
    cert.add_extension(ef.create_extension("subjectAltName", san)) if san
    cert.add_extension(ef.create_extension("keyUsage", "digitalSignature, keyEncipherment", true))
    cert.sign(@ca_key, "SHA256")
    [key, cert]
  end

  def pem_file(content)
    file = Tempfile.new(["hotkv-tls", ".pem"])
    file.write(content)
    file.flush
    @files << file
    file.path
  end

  def tls_server(san: "IP:127.0.0.1,DNS:localhost", require_client_cert: false)
    key, cert = issue("server", san)
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.cert = cert
    ctx.key = key
    if require_client_cert
      store = OpenSSL::X509::Store.new
      store.add_cert(@ca)
      ctx.cert_store = store
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    end
    server = FakeServer.new(ssl_context: ctx) { |_req, _| "+PONG\r\n" }
    @servers << server
    server
  end

  def client_for(server, **options)
    HotKV::Client.new(url: "hotkvs://127.0.0.1:#{server.port}", connect_timeout: 5.0, command_timeout: 5.0, **options)
  end

  def test_verified_against_the_ca_and_the_ip_address
    server = tls_server
    client = client_for(server, ca_file: pem_file(@ca.to_pem))
    assert_equal "PONG", client.ping
    client.close
  end

  def test_server_name_overrides_the_name_checked
    server = tls_server
    client = client_for(server, ca_file: pem_file(@ca.to_pem), server_name: "localhost")
    assert_equal "PONG", client.ping
    client.close
  end

  def test_a_certificate_for_another_host_is_refused
    server = tls_server
    client = client_for(server, ca_file: pem_file(@ca.to_pem), server_name: "wrong.example.com")
    err = assert_raises(HotKV::Error::ConnectionError) { client.ping }
    assert_match(/TLS handshake failed/, err.message)
    client.close
  end

  def test_a_certificate_without_the_ip_is_refused_when_connecting_by_ip
    server = tls_server(san: "DNS:other.example.com")
    client = client_for(server, ca_file: pem_file(@ca.to_pem))
    assert_raises(HotKV::Error::ConnectionError) { client.ping }
    client.close
  end

  def test_an_untrusted_ca_is_refused_without_a_ca_file
    server = tls_server # signed by a CA that is not in the system store
    client = client_for(server)
    err = assert_raises(HotKV::Error::ConnectionError) { client.ping }
    assert_match(/TLS handshake failed/, err.message)
    client.close
  end

  def test_a_different_ca_file_is_refused
    server = tls_server
    _other_key, other_ca = make_ca("some-other-ca")
    client = client_for(server, ca_file: pem_file(other_ca.to_pem))
    assert_raises(HotKV::Error::ConnectionError) { client.ping }
    client.close
  end

  def test_insecure_skip_verify_accepts_an_untrusted_certificate_for_another_host
    server = tls_server(san: "DNS:other.example.com")
    client = client_for(server, insecure_skip_verify: true)
    assert_equal "PONG", client.ping
    client.close
  end

  def test_mutual_tls_presents_the_client_certificate
    server = tls_server(require_client_cert: true)
    key, cert = issue("client", nil)
    ca_file = pem_file(@ca.to_pem)
    with_cert = client_for(server, ca_file: ca_file, cert_file: pem_file(cert.to_pem), key_file: pem_file(key.to_pem))
    assert_equal "PONG", with_cert.ping
    with_cert.close
    without = client_for(server, ca_file: ca_file)
    assert_raises(HotKV::Error::ConnectionError) { without.ping }
    without.close
  end

  def test_the_handshake_honors_connect_timeout
    silent = TCPServer.new("127.0.0.1", 0) # accepts the TCP connection, never answers the handshake
    port = silent.addr[1]
    client = HotKV::Client.new(url: "hotkvs://127.0.0.1:#{port}", insecure_skip_verify: true, connect_timeout: 0.5)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(HotKV::Error::TimeoutError) { client.ping }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3.0
    client.close
  ensure
    silent&.close
  end
end
