require "../spec_helper"
require "../../src/jwt"

describe JWT::Encoder do
  describe ".encode" do
    it "encodes a JWT token with HS256" do
      secret = "secret"
      payload = JWT::Payload.new(
        subject: "user123",
        issued_at: 1516239022_i64,
        extra_claims: {"name" => JSON::Any.new("John Doe")}
      )

      token = JWT::Encoder.encode(payload, secret, JWT::Algorithm::HS256)
      parts = token.split('.')

      parts.size.should eq(3)

      decoded = JWT::Decoder.decode(token, verify: false)
      decoded.header.algorithm.should eq("HS256")
      decoded.payload.subject.should eq("user123")
      decoded.payload.issued_at.should eq(1516239022)
      decoded.payload.extra_claims["name"].as_s.should eq("John Doe")
    end

    it "encodes a JWT token with HS512" do
      secret = "secret"
      payload = JWT::Payload.new(subject: "user123")

      token = JWT::Encoder.encode(payload, secret, JWT::Algorithm::HS512)
      decoded = JWT::Decoder.decode(token, verify: false)

      decoded.header.algorithm.should eq("HS512")
      decoded.payload.subject.should eq("user123")
    end

    it "creates verifiable signatures" do
      secret = "secret"
      payload = JWT::Payload.new(subject: "user123")

      token = JWT::Encoder.encode(payload, secret, JWT::Algorithm::HS256)

      expect_raises(JWT::VerificationError) do
        JWT::Decoder.decode_and_verify(token, secret: "wrong_secret")
      end

      decoded = JWT::Decoder.decode_and_verify(token, secret: secret, verify_expiration: false)
      decoded.payload.subject.should eq("user123")
    end

    it "handles all standard claims" do
      secret = "secret"
      now = Time.utc.to_unix
      payload = JWT::Payload.new(
        issuer: "test_issuer",
        subject: "user123",
        audience: "test_audience",
        expires_at: now + 3600,
        not_before: now,
        issued_at: now,
        jwt_id: "unique_id"
      )

      token = JWT::Encoder.encode(payload, secret, JWT::Algorithm::HS256)
      decoded = JWT::Decoder.decode(token, verify: false)

      decoded.payload.issuer.should eq("test_issuer")
      decoded.payload.subject.should eq("user123")
      decoded.payload.audience.should eq("test_audience")
      decoded.payload.expires_at.should eq(now + 3600)
      decoded.payload.not_before.should eq(now)
      decoded.payload.issued_at.should eq(now)
      decoded.payload.jwt_id.should eq("unique_id")
    end

    it "handles array audience" do
      secret = "secret"
      payload = JWT::Payload.new(
        subject: "user123",
        audience: ["audience1", "audience2"]
      )

      token = JWT::Encoder.encode(payload, secret, JWT::Algorithm::HS256)
      decoded = JWT::Decoder.decode(token, verify: false)

      if aud = decoded.payload.audience
        aud.as(Array(String)).should eq(["audience1", "audience2"])
      else
        fail "Expected audience to be present"
      end
    end
  end

  describe ".encode_with_key_id" do
    it "includes key ID in header" do
      secret = "secret"
      key_id = "key123"
      payload = JWT::Payload.new(subject: "user123")

      token = JWT::Encoder.encode_with_key_id(payload, secret, key_id, JWT::Algorithm::HS256)
      decoded = JWT::Decoder.decode(token, verify: false)

      decoded.header.key_id.should eq(key_id)
      decoded.payload.subject.should eq("user123")
    end
  end
end
