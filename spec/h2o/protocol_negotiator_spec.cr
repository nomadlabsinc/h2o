require "../spec_helper"

describe H2O::ProtocolNegotiator do
  after_each do
    GlobalStateHelper.clear_all_caches
  end

  describe "#initialize" do
    it "creates negotiator with default settings" do
      negotiator = H2O::ProtocolNegotiator.new
      negotiator.should_not be_nil
    end

    it "creates negotiator with h2 prior knowledge enabled" do
      negotiator = H2O::ProtocolNegotiator.new(h2_prior_knowledge: true)
      negotiator.should_not be_nil
    end

    it "creates negotiator with custom cache TTL" do
      negotiator = H2O::ProtocolNegotiator.new(cache_ttl: 30.minutes)
      negotiator.should_not be_nil
    end
  end

  describe "#negotiate_protocol" do
    it "returns h2 when h2_prior_knowledge is enabled" do
      negotiator = H2O::ProtocolNegotiator.new(h2_prior_knowledge: true)
      protocol = negotiator.negotiate_protocol("example.com", 443)
      protocol.should eq("h2")
    end

    it "negotiates protocol for HTTPS hosts" do
      negotiator = H2O::ProtocolNegotiator.new
      protocol = negotiator.negotiate_protocol("example.com", 443)
      protocol.should be_a(String)
      ["h2", "http/1.1"].should contain(protocol)
    end

    it "uses cached protocol when available" do
      negotiator = H2O::ProtocolNegotiator.new

      # Force cache a protocol
      negotiator.force_protocol("example.com", 443, "http/1.1")

      # Should return cached value
      protocol = negotiator.negotiate_protocol("example.com", 443)
      protocol.should eq("http/1.1")
    end

    it "handles non-TLS ports" do
      negotiator = H2O::ProtocolNegotiator.new
      protocol = negotiator.negotiate_protocol("example.com", 80)
      protocol.should eq("http/1.1")
    end
  end

  describe "#create_connection" do
    it "creates H2::Client for h2 protocol" do
      negotiator = H2O::ProtocolNegotiator.new(h2_prior_knowledge: true)
      connection = negotiator.create_connection("example.com", 443, true, false)
      connection.should be_a(H2O::H2::Client)
      connection.close
    end

    it "creates H1::Client for http/1.1 protocol" do
      negotiator = H2O::ProtocolNegotiator.new
      negotiator.force_protocol("example.com", 443, "http/1.1")

      connection = negotiator.create_connection("example.com", 443, true, false)
      connection.should be_a(H2O::H1::Client)
      connection.close
    end

    it "defaults to H2::Client for unknown protocols" do
      negotiator = H2O::ProtocolNegotiator.new
      negotiator.force_protocol("example.com", 443, "unknown-protocol")

      connection = negotiator.create_connection("example.com", 443, true, false)
      connection.should be_a(H2O::H2::Client)
      connection.close
    end
  end

  describe "#supports_http2?" do
    it "returns true when protocol is h2" do
      negotiator = H2O::ProtocolNegotiator.new(h2_prior_knowledge: true)
      result = negotiator.supports_http2?("example.com", 443)
      result.should be_true
    end

    it "returns false when protocol is http/1.1" do
      negotiator = H2O::ProtocolNegotiator.new
      negotiator.force_protocol("example.com", 443, "http/1.1")

      result = negotiator.supports_http2?("example.com", 443)
      result.should be_false
    end
  end

  describe "#force_protocol" do
    it "forces protocol for specific host and port" do
      negotiator = H2O::ProtocolNegotiator.new

      negotiator.force_protocol("example.com", 443, "http/1.1", 0.8)

      protocol = negotiator.negotiate_protocol("example.com", 443)
      protocol.should eq("http/1.1")
    end

    it "allows different protocols for different ports" do
      negotiator = H2O::ProtocolNegotiator.new

      negotiator.force_protocol("example.com", 443, "h2")
      negotiator.force_protocol("example.com", 8443, "http/1.1")

      negotiator.negotiate_protocol("example.com", 443).should eq("h2")
      negotiator.negotiate_protocol("example.com", 8443).should eq("http/1.1")
    end
  end

  describe "#clear_cache" do
    it "clears all cached protocol entries" do
      negotiator = H2O::ProtocolNegotiator.new

      negotiator.force_protocol("example.com", 443, "h2")
      negotiator.force_protocol("test.com", 443, "http/1.1")

      negotiator.clear_cache

      stats = negotiator.statistics
      stats[:total_cached_hosts].should eq(0)
    end
  end

  describe "#cleanup_expired_cache" do
    it "removes expired cache entries" do
      negotiator = H2O::ProtocolNegotiator.new(cache_ttl: 1.millisecond)

      negotiator.force_protocol("example.com", 443, "h2")

      sleep(5.milliseconds)

      negotiator.cleanup_expired_cache

      stats = negotiator.statistics
      stats[:total_cached_hosts].should eq(0)
    end

    it "keeps non-expired cache entries" do
      negotiator = H2O::ProtocolNegotiator.new(cache_ttl: 1.hour)

      negotiator.force_protocol("example.com", 443, "h2")

      negotiator.cleanup_expired_cache

      stats = negotiator.statistics
      stats[:total_cached_hosts].should eq(1)
    end
  end

  describe "#statistics" do
    it "returns correct statistics for empty cache" do
      negotiator = H2O::ProtocolNegotiator.new

      stats = negotiator.statistics

      stats[:total_cached_hosts].should eq(0)
      stats[:h2_hosts].should eq(0)
      stats[:h1_hosts].should eq(0)
      stats[:h2_ratio].should eq(0.0)
      stats[:avg_confidence].should eq(0.0)
    end

    it "returns correct statistics with cached entries" do
      negotiator = H2O::ProtocolNegotiator.new

      negotiator.force_protocol("h2.example.com", 443, "h2", 0.9)
      negotiator.force_protocol("h1.example.com", 443, "http/1.1", 0.8)
      negotiator.force_protocol("h2-2.example.com", 443, "h2", 1.0)

      stats = negotiator.statistics

      stats[:total_cached_hosts].should eq(3)
      stats[:h2_hosts].should eq(2)
      stats[:h1_hosts].should eq(1)
      stats[:h2_ratio].should be_close(0.67, 0.01)
      stats[:avg_confidence].should be_close(0.9, 0.01)
    end
  end

  describe "#cached_protocols" do
    it "returns empty hash when no protocols are cached" do
      negotiator = H2O::ProtocolNegotiator.new

      protocols = negotiator.cached_protocols
      protocols.should be_empty
    end

    it "returns all cached protocols" do
      negotiator = H2O::ProtocolNegotiator.new

      negotiator.force_protocol("example.com", 443, "h2")
      negotiator.force_protocol("test.com", 8443, "http/1.1")

      protocols = negotiator.cached_protocols

      protocols.size.should eq(2)
      protocols["example.com:443"].should eq("h2")
      protocols["test.com:8443"].should eq("http/1.1")
    end
  end

  describe "#protocol_cached?" do
    it "returns false when protocol is not cached" do
      negotiator = H2O::ProtocolNegotiator.new

      result = negotiator.protocol_cached?("example.com", 443)
      result.should be_false
    end

    it "returns true when protocol is cached and not expired" do
      negotiator = H2O::ProtocolNegotiator.new(cache_ttl: 1.hour)

      negotiator.force_protocol("example.com", 443, "h2")

      result = negotiator.protocol_cached?("example.com", 443)
      result.should be_true
    end

    it "returns false when protocol is cached but expired" do
      negotiator = H2O::ProtocolNegotiator.new(cache_ttl: 1.millisecond)

      negotiator.force_protocol("example.com", 443, "h2")

      sleep(5.milliseconds)

      result = negotiator.protocol_cached?("example.com", 443)
      result.should be_false
    end
  end

  describe "cache expiration" do
    it "automatically expires old cache entries during negotiation" do
      negotiator = H2O::ProtocolNegotiator.new(cache_ttl: 1.millisecond)

      negotiator.force_protocol("example.com", 443, "http/1.1")

      # Verify it's cached
      negotiator.protocol_cached?("example.com", 443).should be_true

      sleep(5.milliseconds)

      # This should clean up the expired entry and re-negotiate
      protocol = negotiator.negotiate_protocol("example.com", 443)
      protocol.should be_a(String)

      # The old entry should be gone
      negotiator.protocol_cached?("example.com", 443).should be_true # New entry created
    end
  end

  describe "integration with different host types" do
    it "handles IPv4 addresses" do
      negotiator = H2O::ProtocolNegotiator.new

      protocol = negotiator.negotiate_protocol("127.0.0.1", 443)
      protocol.should be_a(String)
      ["h2", "http/1.1"].should contain(protocol)
    end

    it "handles different port numbers" do
      negotiator = H2O::ProtocolNegotiator.new

      # HTTPS port
      protocol_443 = negotiator.negotiate_protocol("example.com", 443)
      protocol_443.should be_a(String)

      # HTTP port
      protocol_80 = negotiator.negotiate_protocol("example.com", 80)
      protocol_80.should eq("http/1.1")

      # Custom HTTPS port
      protocol_8443 = negotiator.negotiate_protocol("example.com", 8443)
      protocol_8443.should be_a(String)
    end
  end
end
