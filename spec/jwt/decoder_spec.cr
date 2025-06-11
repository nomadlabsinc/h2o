require "../spec_helper"
require "../../src/jwt"

describe JWT::Decoder do
  describe ".decode" do
    it "decodes a valid JWT token" do
      token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

      decoded = JWT::Decoder.decode(token, verify: false)

      decoded.header.algorithm.should eq("HS256")
      decoded.header.type.should eq("JWT")
      decoded.payload.subject.should eq("1234567890")
      decoded.payload.extra_claims["name"].as_s.should eq("John Doe")
      decoded.payload.issued_at.should eq(1516239022)
    end

    it "raises DecodeError for invalid JWT format" do
      expect_raises(JWT::DecodeError, "Invalid JWT format: expected 3 parts, got 2") do
        JWT::Decoder.decode("invalid.token")
      end
    end

    it "raises DecodeError for invalid base64 encoding" do
      expect_raises(JWT::DecodeError, "Invalid header") do
        JWT::Decoder.decode("invalid!!!.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature")
      end
    end

    it "raises DecodeError for invalid JSON in header" do
      invalid_header = Base64.strict_encode("not json").tr("+/", "-_").rstrip('=')
      expect_raises(JWT::DecodeError, "Invalid header") do
        JWT::Decoder.decode("#{invalid_header}.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature")
      end
    end

    it "raises DecodeError for invalid JSON in payload" do
      header = Base64.strict_encode(%Q[{"alg":"HS256","typ":"JWT"}]).tr("+/", "-_").rstrip('=')
      invalid_payload = Base64.strict_encode("not json").tr("+/", "-_").rstrip('=')
      expect_raises(JWT::DecodeError, "Invalid payload") do
        JWT::Decoder.decode("#{header}.#{invalid_payload}.signature")
      end
    end
  end

  describe ".decode_and_verify" do
    it "verifies and decodes a valid HMAC token" do
      secret = "secret"
      payload = JWT::Payload.new(
        subject: "user123",
        issued_at: Time.utc.to_unix,
        expires_at: (Time.utc + 1.hour).to_unix
      )

      token = JWT::Encoder.encode(payload, secret, JWT::Algorithm::HS256)
      decoded = JWT::Decoder.decode_and_verify(token, secret: secret)

      decoded.payload.subject.should eq("user123")
    end

    it "raises VerificationError for invalid signature" do
      secret = "secret"
      wrong_secret = "wrong_secret"
      payload = JWT::Payload.new(subject: "user123")

      token = JWT::Encoder.encode(payload, secret, JWT::Algorithm::HS256)

      expect_raises(JWT::VerificationError, "Signature verification failed") do
        JWT::Decoder.decode_and_verify(token, secret: wrong_secret)
      end
    end

    it "raises ExpiredTokenError for expired token" do
      secret = "secret"
      payload = JWT::Payload.new(
        subject: "user123",
        expires_at: (Time.utc - 1.hour).to_unix
      )

      token = JWT::Encoder.encode(payload, secret, JWT::Algorithm::HS256)

      expect_raises(JWT::ExpiredTokenError, "Token has expired") do
        JWT::Decoder.decode_and_verify(token, secret: secret)
      end
    end

    it "raises PrematureTokenError for premature token" do
      secret = "secret"
      payload = JWT::Payload.new(
        subject: "user123",
        not_before: (Time.utc + 1.hour).to_unix
      )

      token = JWT::Encoder.encode(payload, secret, JWT::Algorithm::HS256)

      expect_raises(JWT::PrematureTokenError, "Token is not yet valid") do
        JWT::Decoder.decode_and_verify(token, secret: secret)
      end
    end

    it "respects leeway for expiration" do
      secret = "secret"
      payload = JWT::Payload.new(
        subject: "user123",
        expires_at: (Time.utc - 30.seconds).to_unix
      )

      token = JWT::Encoder.encode(payload, secret, JWT::Algorithm::HS256)
      decoded = JWT::Decoder.decode_and_verify(token, secret: secret, leeway: 1.minute)

      decoded.payload.subject.should eq("user123")
    end

    it "raises VerificationError for algorithm mismatch" do
      secret = "secret"
      payload = JWT::Payload.new(subject: "user123")

      token = JWT::Encoder.encode(payload, secret, JWT::Algorithm::HS256)

      expect_raises(JWT::VerificationError, "Algorithm mismatch: expected HS512, got HS256") do
        JWT::Decoder.decode_and_verify(token, secret: secret, algorithm: JWT::Algorithm::HS512)
      end
    end

    it "handles none algorithm correctly" do
      header_b64 = Base64.strict_encode(%Q[{"alg":"none","typ":"JWT"}]).tr("+/", "-_").rstrip('=')
      payload_b64 = Base64.strict_encode(%Q[{"sub":"user123"}]).tr("+/", "-_").rstrip('=')
      token = "#{header_b64}.#{payload_b64}."

      decoded = JWT::Decoder.decode_and_verify(token, verify_expiration: false, verify_not_before: false)
      decoded.payload.subject.should eq("user123")
      decoded.algorithm.should eq(JWT::Algorithm::None)
    end

    it "raises VerificationError for none algorithm with non-empty signature" do
      header_b64 = Base64.strict_encode(%Q[{"alg":"none","typ":"JWT"}]).tr("+/", "-_").rstrip('=')
      payload_b64 = Base64.strict_encode(%Q[{"sub":"user123"}]).tr("+/", "-_").rstrip('=')
      token = "#{header_b64}.#{payload_b64}.nonempty"

      expect_raises(JWT::VerificationError, "None algorithm must have empty signature") do
        JWT::Decoder.decode_and_verify(token)
      end
    end
  end
end
