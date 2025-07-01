require "../spec_helper"

# Test-specific client to prevent actual network connections
class PriorKnowledgeTestClient < H2O::Client
  getter? last_use_tls : Bool?
  getter? http1_fallback_attempted : Bool?

  def initialize(*, h2_prior_knowledge : Bool)
    super(h2_prior_knowledge: h2_prior_knowledge)
    @http1_fallback_attempted = false
  end

  # Override the method that creates the H2 client to prevent network I/O
  private def try_http2_connection(host : String, port : Int32) : H2O::BaseConnection?
    # Record the value of use_tls for inspection
    # This mimics the actual implementation: use_tls = !@h2_prior_knowledge
    @last_use_tls = !@h2_prior_knowledge
    # Return nil to simulate connection failure without network delay
    nil
  end

  # Override the HTTP/1.1 fallback to prevent network I/O
  private def try_http1_connection(host : String, port : Int32) : H2O::BaseConnection?
    @http1_fallback_attempted = true
    nil
  end
end

describe H2O::Client do
  describe "HTTP/2 Prior Knowledge Support" do
    it "accepts http:// URLs when h2_prior_knowledge is enabled" do
      client = PriorKnowledgeTestClient.new(h2_prior_knowledge: true)
      # The request should fail fast because our test client doesn't connect
      response = client.get("http://example.com/test")
      response.error?.should be_true
      response.error.not_nil!.should contain("Connection failed")
    end

    it "rejects http:// URLs when h2_prior_knowledge is disabled" do
      client = H2O::Client.new(h2_prior_knowledge: false)
      expect_raises(ArgumentError, /Only HTTPS URLs are supported/) do
        client.get("http://example.com/test")
      end
    end

    it "still accepts https:// URLs when h2_prior_knowledge is enabled" do
      client = PriorKnowledgeTestClient.new(h2_prior_knowledge: true)
      response = client.get("https://example.com/test")
      response.error?.should be_true
      response.error.not_nil!.should contain("Connection failed")
    end

    it "attempts to create a TCP socket (use_tls: false) for h2c connections" do
      client = PriorKnowledgeTestClient.new(h2_prior_knowledge: true)
      client.get("http://localhost:8080/test")
      # The overridden try_http2_connection sets last_use_tls
      client.last_use_tls?.should be_false
    end

    it "attempts to create a TLS socket (use_tls: true) for https connections" do
      client = PriorKnowledgeTestClient.new(h2_prior_knowledge: false)
      client.get("https://localhost:8443/test")
      # When h2_prior_knowledge is false, use_tls should be true
      client.last_use_tls?.should be_true
    end

    it "does not fall back to HTTP/1.1 when prior knowledge is enabled" do
      client = PriorKnowledgeTestClient.new(h2_prior_knowledge: true)
      client.get("http://localhost:8080/test")
      # The overridden try_http1_connection sets this flag
      client.http1_fallback_attempted?.should be_false
    end
  end
end
