module H2O::HPACK
  # HPACK Dynamic Table Presets for optimized compression efficiency
  #
  # This module provides pre-configured header sets that can be loaded into
  # the HPACK dynamic table to improve compression from the very first request.
  # Useful for clients that frequently communicate with the same servers.
  module Presets
    # Common header presets for different types of applications
    alias PresetName = String
    alias PresetHeaders = Array(HeaderEntry)

    # RESTful API client presets
    REST_API_PRESET = [
      {"accept", "application/json"},
      {"content-type", "application/json"},
      {"user-agent", "h2o-client/#{H2O::VERSION}"},
      {"accept-encoding", "gzip, deflate, br"},
      {"cache-control", "no-cache"},
      {"authorization", "Bearer"},
    ]

    # Web browser simulation presets
    BROWSER_PRESET = [
      {"accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"accept-language", "en-US,en;q=0.5"},
      {"accept-encoding", "gzip, deflate, br"},
      {"user-agent", "Mozilla/5.0 (compatible; h2o-client/#{H2O::VERSION})"},
      {"dnt", "1"},
      {"upgrade-insecure-requests", "1"},
    ]

    # CDN/Static content presets
    CDN_PRESET = [
      {"accept", "*/*"},
      {"accept-encoding", "gzip, deflate, br"},
      {"cache-control", "max-age=3600"},
      {"if-none-match", "*"},
      {"if-modified-since", ""},
    ]

    # GraphQL API presets
    GRAPHQL_PRESET = [
      {"accept", "application/json"},
      {"content-type", "application/json"},
      {"accept-encoding", "gzip, deflate"},
      {"apollo-client-name", "h2o-client"},
      {"apollo-client-version", H2O::VERSION},
    ]

    # Microservices communication presets
    MICROSERVICE_PRESET = [
      {"accept", "application/json"},
      {"content-type", "application/json"},
      {"user-agent", "h2o-microservice/#{H2O::VERSION}"},
      {"x-request-id", ""},
      {"x-correlation-id", ""},
      {"x-forwarded-for", ""},
    ]

    # Registry of all available presets
    AVAILABLE_PRESETS = {
      "rest-api"     => REST_API_PRESET,
      "browser"      => BROWSER_PRESET,
      "cdn"          => CDN_PRESET,
      "graphql"      => GRAPHQL_PRESET,
      "microservice" => MICROSERVICE_PRESET,
    }

    # Preset-aware HPACK encoder with dynamic table pre-population
    class PresetEncoder < Encoder
      property preset_name : PresetName?
      property preset_applied : Bool

      def initialize(table_size : Int32 = DynamicTable::DEFAULT_SIZE,
                     huffman_encoding : Bool = true,
                     @preset_name : PresetName? = nil)
        super(table_size, huffman_encoding)
        @preset_applied = false
        apply_preset if @preset_name
      end

      # Apply a preset to pre-populate the dynamic table
      def apply_preset(preset_name : PresetName = @preset_name || "rest-api") : Nil
        preset_headers = AVAILABLE_PRESETS[preset_name]?
        return unless preset_headers

        @preset_name = preset_name

        # Add preset headers to dynamic table
        preset_headers.each do |name, value|
          # Only add headers that will benefit from indexing
          if should_index?(name, value)
            @dynamic_table.add(name, value)
          end
        end

        @preset_applied = true
      end

      # Enhanced encoding that leverages preset headers
      def encode(headers : Headers) : EncodedBytes
        result = IO::Memory.new

        headers.each do |name, value|
          encode_header_with_preset(result, name, value)
        end

        result.to_slice
      end

      # Get compression statistics for monitoring preset effectiveness
      def compression_stats : NamedTuple(hits: Int32, misses: Int32, ratio: Float64)
        hits = @dynamic_table.size
        # Simplified stats - just report current table utilization
        total = @dynamic_table.max_size
        ratio = total > 0 ? hits.to_f / total.to_f : 0.0

        {hits: hits, misses: (total - hits), ratio: ratio}
      end

      private def encode_header_with_preset(io : IO, name : String, value : String) : Nil
        # First check dynamic table (including preset entries)
        if index = @dynamic_table.find_name_value(name, value)
          encode_indexed_header(io, index)
          return
        end

        # Check for name-only matches in dynamic table
        if name_index = @dynamic_table.find_name(name)
          encode_literal_with_incremental_indexing_indexed_name(io, name_index, value)
          @dynamic_table.add(name, value) if should_index?(name, value)
          return
        end

        # Fall back to standard encoding
        encode_header_simple(io, name, value)
      end

      # Check if header should be indexed considering preset context
      private def should_index?(name : String, value : String) : Bool
        # Don't index sensitive headers
        return false if name.in?(["authorization", "cookie", "set-cookie"])

        # Don't index pseudo-headers (HTTP/2 specific)
        return false if name.starts_with?(":")

        # Don't index very large values
        return false if value.bytesize > 1024

        # Index headers that are likely to repeat
        return true if name.in?(["accept", "user-agent", "accept-encoding", "content-type"])

        # Index custom headers for microservices
        return true if name.starts_with?("x-") && value.bytesize < 256

        # Default to indexing for other reasonable headers
        value.bytesize < 128
      end
    end

    # Factory methods for common encoder configurations
    module Factory
      # Create encoder optimized for REST API clients
      def self.rest_api_encoder(table_size : Int32 = DynamicTable::DEFAULT_SIZE) : PresetEncoder
        PresetEncoder.new(table_size, huffman_encoding: true, preset_name: "rest-api")
      end

      # Create encoder optimized for browser-like requests
      def self.browser_encoder(table_size : Int32 = DynamicTable::DEFAULT_SIZE) : PresetEncoder
        PresetEncoder.new(table_size, huffman_encoding: true, preset_name: "browser")
      end

      # Create encoder optimized for CDN/static content
      def self.cdn_encoder(table_size : Int32 = DynamicTable::DEFAULT_SIZE) : PresetEncoder
        PresetEncoder.new(table_size, huffman_encoding: true, preset_name: "cdn")
      end

      # Create encoder optimized for GraphQL APIs
      def self.graphql_encoder(table_size : Int32 = DynamicTable::DEFAULT_SIZE) : PresetEncoder
        PresetEncoder.new(table_size, huffman_encoding: true, preset_name: "graphql")
      end

      # Create encoder optimized for microservice communication
      def self.microservice_encoder(table_size : Int32 = DynamicTable::DEFAULT_SIZE) : PresetEncoder
        PresetEncoder.new(table_size, huffman_encoding: true, preset_name: "microservice")
      end

      # Create custom encoder with user-defined preset
      def self.custom_encoder(preset_headers : PresetHeaders, table_size : Int32 = DynamicTable::DEFAULT_SIZE) : PresetEncoder
        encoder = PresetEncoder.new(table_size, huffman_encoding: true)

        # Manually populate dynamic table with custom headers
        preset_headers.each do |name, value|
          # Use a simple heuristic for indexing since we can't access private method
          if should_index_header?(name, value)
            encoder.dynamic_table.add(name, value)
          end
        end

        encoder.preset_applied = true
        encoder
      end

      # Helper method for custom encoder indexing decisions
      private def self.should_index_header?(name : String, value : String) : Bool
        # Don't index sensitive headers
        return false if name.in?(["authorization", "cookie", "set-cookie"])

        # Don't index pseudo-headers (HTTP/2 specific)
        return false if name.starts_with?(":")

        # Don't index very large values
        return false if value.bytesize > 1024

        # Index headers that are likely to repeat
        return true if name.in?(["accept", "user-agent", "accept-encoding", "content-type"])

        # Index custom headers for microservices
        return true if name.starts_with?("x-") && value.bytesize < 256

        # Default to indexing for other reasonable headers
        value.bytesize < 128
      end
    end

    # Preset selection helper based on usage patterns
    module Selector
      # Analyze headers to suggest optimal preset
      def self.suggest_preset(sample_headers : Array(Headers)) : PresetName
        return "rest-api" if sample_headers.empty?

        # Count header patterns
        content_type_json = 0
        has_user_agent = 0
        has_accept_html = 0
        has_apollo = 0
        has_x_headers = 0

        sample_headers.each do |headers|
          content_type_json += 1 if headers["content-type"]?.try(&.includes?("json"))
          has_user_agent += 1 if headers["user-agent"]?
          has_accept_html += 1 if headers["accept"]?.try(&.includes?("text/html"))
          has_apollo += 1 if headers.any? { |k, _| k.starts_with?("apollo-") }
          has_x_headers += 1 if headers.any? { |k, _| k.starts_with?("x-") }
        end

        total = sample_headers.size

        # Decision logic based on header patterns
        return "graphql" if has_apollo > (total * 0.3)
        return "browser" if has_accept_html > (total * 0.5)
        return "microservice" if has_x_headers > (total * 0.4)
        return "rest-api" if content_type_json > (total * 0.6)

        # Default fallback
        "rest-api"
      end

      # Benchmark different presets and return the most effective one
      def self.benchmark_presets(sample_headers : Array(Headers)) : NamedTuple(preset: PresetName, compression_ratio: Float64)
        best_preset = "rest-api"
        best_ratio = 0.0

        AVAILABLE_PRESETS.keys.each do |preset_name|
          encoder = PresetEncoder.new(preset_name: preset_name)

          total_original = 0
          total_compressed = 0

          sample_headers.each do |headers|
            # Calculate original size (rough estimate)
            original_size = headers.sum { |k, v| k.bytesize + v.bytesize + 4 } # +4 for separators

            # Encode with preset
            compressed = encoder.encode(headers)

            total_original += original_size
            total_compressed += compressed.size
          end

          ratio = total_original > 0 ? (total_original - total_compressed).to_f / total_original : 0.0

          if ratio > best_ratio
            best_ratio = ratio
            best_preset = preset_name
          end
        end

        {preset: best_preset, compression_ratio: best_ratio}
      end
    end
  end
end
