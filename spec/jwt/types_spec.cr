require "../spec_helper"
require "../../src/jwt"

describe JWT::Algorithm do
  describe ".from_string" do
    it "parses valid algorithm strings" do
      JWT::Algorithm.from_string("HS256").should eq(JWT::Algorithm::HS256)
      JWT::Algorithm.from_string("HS384").should eq(JWT::Algorithm::HS384)
      JWT::Algorithm.from_string("HS512").should eq(JWT::Algorithm::HS512)
      JWT::Algorithm.from_string("RS256").should eq(JWT::Algorithm::RS256)
      JWT::Algorithm.from_string("ES256").should eq(JWT::Algorithm::ES256)
      JWT::Algorithm.from_string("none").should eq(JWT::Algorithm::None)
    end

    it "raises ArgumentError for invalid algorithm" do
      expect_raises(ArgumentError, "Unsupported algorithm: INVALID") do
        JWT::Algorithm.from_string("INVALID")
      end
    end
  end

  describe "#to_s" do
    it "converts algorithm to string correctly" do
      JWT::Algorithm::HS256.to_s.should eq("HS256")
      JWT::Algorithm::HS384.to_s.should eq("HS384")
      JWT::Algorithm::HS512.to_s.should eq("HS512")
      JWT::Algorithm::RS256.to_s.should eq("RS256")
      JWT::Algorithm::ES256.to_s.should eq("ES256")
      JWT::Algorithm::None.to_s.should eq("none")
    end
  end
end

describe JWT::Header do
  describe "#algorithm_enum" do
    it "returns correct algorithm enum" do
      header = JWT::Header.new("HS256")
      header.algorithm_enum.should eq(JWT::Algorithm::HS256)
    end
  end

  describe "JSON serialization" do
    it "serializes and deserializes correctly" do
      header = JWT::Header.new("HS256", "JWT", "key123")
      json = header.to_json

      parsed = JWT::Header.from_json(json)
      parsed.algorithm.should eq("HS256")
      parsed.type.should eq("JWT")
      parsed.key_id.should eq("key123")
    end

    it "handles missing optional fields" do
      header = JWT::Header.new("HS256")
      json = header.to_json

      parsed = JWT::Header.from_json(json)
      parsed.algorithm.should eq("HS256")
      parsed.type.should eq("JWT")
      parsed.key_id.should be_nil
    end
  end
end

describe JWT::Payload do
  describe "#expired?" do
    it "returns true for expired token" do
      payload = JWT::Payload.new(expires_at: (Time.utc - 1.hour).to_unix)
      payload.expired?.should be_true
    end

    it "returns false for non-expired token" do
      payload = JWT::Payload.new(expires_at: (Time.utc + 1.hour).to_unix)
      payload.expired?.should be_false
    end

    it "returns false when no expiration set" do
      payload = JWT::Payload.new
      payload.expired?.should be_false
    end
  end

  describe "#premature?" do
    it "returns true for premature token" do
      payload = JWT::Payload.new(not_before: (Time.utc + 1.hour).to_unix)
      payload.premature?.should be_true
    end

    it "returns false for non-premature token" do
      payload = JWT::Payload.new(not_before: (Time.utc - 1.hour).to_unix)
      payload.premature?.should be_false
    end

    it "returns false when no not_before set" do
      payload = JWT::Payload.new
      payload.premature?.should be_false
    end
  end

  describe "extra claims access" do
    it "allows setting and getting extra claims" do
      payload = JWT::Payload.new
      payload["custom"] = JSON::Any.new("value")

      payload["custom"]?.should eq(JSON::Any.new("value"))
      payload["nonexistent"]?.should be_nil
    end
  end
end

describe JWT::Token do
  describe "#algorithm" do
    it "returns header algorithm as enum" do
      header = JWT::Header.new("HS256")
      payload = JWT::Payload.new
      token = JWT::Token.new(header, payload, Bytes.empty, "")

      token.algorithm.should eq(JWT::Algorithm::HS256)
    end
  end

  describe "#valid?" do
    it "returns true for valid token" do
      payload = JWT::Payload.new(
        expires_at: (Time.utc + 1.hour).to_unix,
        not_before: (Time.utc - 1.hour).to_unix
      )
      header = JWT::Header.new("HS256")
      token = JWT::Token.new(header, payload, Bytes.empty, "")

      token.valid?.should be_true
    end

    it "returns false for expired token" do
      payload = JWT::Payload.new(expires_at: (Time.utc - 1.hour).to_unix)
      header = JWT::Header.new("HS256")
      token = JWT::Token.new(header, payload, Bytes.empty, "")

      token.valid?.should be_false
    end

    it "returns false for premature token" do
      payload = JWT::Payload.new(not_before: (Time.utc + 1.hour).to_unix)
      header = JWT::Header.new("HS256")
      token = JWT::Token.new(header, payload, Bytes.empty, "")

      token.valid?.should be_false
    end
  end
end
