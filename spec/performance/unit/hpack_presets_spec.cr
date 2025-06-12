require "../../spec_helper"

describe H2O::HPACK::Presets do
  describe "PresetEncoder" do
    it "applies REST API presets correctly" do
      encoder = H2O::HPACK::Presets::PresetEncoder.new(preset_name: "rest-api")

      encoder.preset_applied.should be_true
      encoder.preset_name.should eq("rest-api")

      # Should have preset headers in dynamic table
      encoder.dynamic_table.size.should be > 0
    end

    it "encodes headers with preset optimization" do
      encoder = H2O::HPACK::Presets::PresetEncoder.new(preset_name: "rest-api")

      # These headers should benefit from preset optimization
      headers = H2O::Headers{
        "accept"       => "application/json",
        "content-type" => "application/json",
        "user-agent"   => "h2o-client/#{H2O::VERSION}",
      }

      encoded = encoder.encode(headers)

      # Should produce more compact encoding due to preset hits
      encoded.size.should be < 200 # Rough estimate for compact encoding

      # Check compression stats
      stats = encoder.compression_stats
      stats[:hits].should be > 0
      stats[:ratio].should be > 0.0
    end

    it "falls back gracefully for unknown presets" do
      encoder = H2O::HPACK::Presets::PresetEncoder.new(preset_name: "unknown-preset")

      # Should still work, just without preset optimization
      headers = H2O::Headers{"test" => "value"}
      encoded = encoder.encode(headers)

      encoded.should_not be_nil
      encoded.size.should be > 0
    end

    it "provides compression statistics" do
      encoder = H2O::HPACK::Presets::PresetEncoder.new(preset_name: "rest-api")

      # Encode some headers multiple times
      headers = H2O::Headers{"accept" => "application/json"}
      3.times { encoder.encode(headers) }

      stats = encoder.compression_stats
      stats[:hits].should be >= 0
      stats[:misses].should be >= 0
      stats[:ratio].should be >= 0.0
      stats[:ratio].should be <= 1.0
    end
  end

  describe "Factory methods" do
    it "creates REST API encoder" do
      encoder = H2O::HPACK::Presets::Factory.rest_api_encoder

      encoder.preset_name.should eq("rest-api")
      encoder.preset_applied.should be_true
      encoder.huffman_encoding.should be_true
    end

    it "creates browser encoder" do
      encoder = H2O::HPACK::Presets::Factory.browser_encoder

      encoder.preset_name.should eq("browser")
      encoder.preset_applied.should be_true
    end

    it "creates CDN encoder" do
      encoder = H2O::HPACK::Presets::Factory.cdn_encoder

      encoder.preset_name.should eq("cdn")
      encoder.preset_applied.should be_true
    end

    it "creates GraphQL encoder" do
      encoder = H2O::HPACK::Presets::Factory.graphql_encoder

      encoder.preset_name.should eq("graphql")
      encoder.preset_applied.should be_true
    end

    it "creates microservice encoder" do
      encoder = H2O::HPACK::Presets::Factory.microservice_encoder

      encoder.preset_name.should eq("microservice")
      encoder.preset_applied.should be_true
    end

    it "creates custom encoder with user-defined headers" do
      custom_headers = [
        {"x-api-key", "secret"},
        {"x-version", "1.0"},
      ]

      encoder = H2O::HPACK::Presets::Factory.custom_encoder(custom_headers)

      encoder.preset_applied.should be_true
      encoder.dynamic_table.size.should be > 0
    end
  end

  describe "Preset selection" do
    it "suggests REST API preset for JSON-heavy traffic" do
      sample_headers = [
        H2O::Headers{"content-type" => "application/json", "accept" => "application/json"},
        H2O::Headers{"content-type" => "application/json", "method" => "POST"},
        H2O::Headers{"accept" => "application/json", "authorization" => "Bearer token"},
      ]

      suggestion = H2O::HPACK::Presets::Selector.suggest_preset(sample_headers)
      suggestion.should eq("rest-api")
    end

    it "suggests browser preset for HTML traffic" do
      sample_headers = [
        H2O::Headers{"accept" => "text/html,application/xhtml+xml", "user-agent" => "Mozilla/5.0"},
        H2O::Headers{"accept" => "text/html", "accept-language" => "en-US"},
      ]

      suggestion = H2O::HPACK::Presets::Selector.suggest_preset(sample_headers)
      suggestion.should eq("browser")
    end

    it "suggests GraphQL preset for Apollo traffic" do
      sample_headers = [
        H2O::Headers{"apollo-client-name" => "my-app", "content-type" => "application/json"},
        H2O::Headers{"apollo-client-version" => "1.0", "accept" => "application/json"},
      ]

      suggestion = H2O::HPACK::Presets::Selector.suggest_preset(sample_headers)
      suggestion.should eq("graphql")
    end

    it "suggests microservice preset for X-header traffic" do
      sample_headers = [
        H2O::Headers{"x-request-id" => "123", "x-service" => "api"},
        H2O::Headers{"x-correlation-id" => "456", "content-type" => "application/json"},
        H2O::Headers{"x-forwarded-for" => "127.0.0.1", "x-trace-id" => "789"},
      ]

      suggestion = H2O::HPACK::Presets::Selector.suggest_preset(sample_headers)
      suggestion.should eq("microservice")
    end

    it "defaults to REST API for empty input" do
      suggestion = H2O::HPACK::Presets::Selector.suggest_preset([] of H2O::Headers)
      suggestion.should eq("rest-api")
    end
  end

  describe "Preset benchmarking" do
    it "benchmarks presets and selects the best one" do
      sample_headers = [
        H2O::Headers{"accept" => "application/json", "content-type" => "application/json"},
        H2O::Headers{"user-agent" => "test-client", "accept-encoding" => "gzip"},
      ]

      result = H2O::HPACK::Presets::Selector.benchmark_presets(sample_headers)

      result[:preset].should be_a(String)
      result[:compression_ratio].should be >= 0.0
      result[:compression_ratio].should be <= 1.0

      # Should pick a reasonable preset
      H2O::HPACK::Presets::AVAILABLE_PRESETS.keys.includes?(result[:preset]).should be_true
    end

    it "handles single header benchmark" do
      sample_headers = [H2O::Headers{"test" => "value"}]

      result = H2O::HPACK::Presets::Selector.benchmark_presets(sample_headers)

      result[:preset].should_not be_nil
      result[:compression_ratio].should be >= 0.0
    end
  end

  describe "Available presets validation" do
    it "contains all expected presets" do
      expected_presets = ["rest-api", "browser", "cdn", "graphql", "microservice"]

      expected_presets.each do |preset_name|
        H2O::HPACK::Presets::AVAILABLE_PRESETS.has_key?(preset_name).should be_true
        preset = H2O::HPACK::Presets::AVAILABLE_PRESETS[preset_name]
        preset.should be_a(Array(H2O::HPACK::HeaderEntry))
        preset.should_not be_empty
      end
    end

    it "has well-formed preset headers" do
      H2O::HPACK::Presets::AVAILABLE_PRESETS.each do |_, headers|
        headers.each do |header_name, header_value|
          header_name.should be_a(String)
          header_value.should be_a(String)
          header_name.should_not be_empty
          # header_value can be empty for placeholder headers
        end
      end
    end
  end

  describe "Performance characteristics" do
    it "shows improvement with preset usage" do
      # Test without preset
      regular_encoder = H2O::HPACK::Encoder.new

      # Test with preset
      preset_encoder = H2O::HPACK::Presets::Factory.rest_api_encoder

      # Common headers that should benefit from presets
      test_headers = H2O::Headers{
        "accept"       => "application/json",
        "content-type" => "application/json",
        "user-agent"   => "h2o-client/#{H2O::VERSION}",
      }

      regular_encoded = regular_encoder.encode(test_headers)
      preset_encoded = preset_encoder.encode(test_headers)

      # Preset encoding should be more compact for repeated headers
      preset_encoded.size.should be <= regular_encoded.size
    end
  end
end
