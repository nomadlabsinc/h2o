require "./spec_helper"
require "../src/jwt"

describe JWT do
  it "has a complete working example" do
    secret = "my_secret_key"

    payload = JWT::Payload.new(
      issuer: "test_app",
      subject: "user123",
      audience: "api_service",
      expires_at: (Time.utc + 24.hours).to_unix,
      issued_at: Time.utc.to_unix,
      extra_claims: {
        "role"        => JSON::Any.new("admin"),
        "permissions" => JSON::Any.new(["read", "write", "delete"].map { |s| JSON::Any.new(s) }),
      }
    )

    token = JWT::Encoder.encode(payload, secret, JWT::Algorithm::HS256)

    decoded = JWT::Decoder.decode_and_verify(token, secret: secret)

    decoded.payload.issuer.should eq("test_app")
    decoded.payload.subject.should eq("user123")
    decoded.payload.audience.should eq("api_service")
    decoded.payload["role"].try(&.as_s).should eq("admin")
    decoded.payload["permissions"].try(&.as_a.map(&.as_s)).should eq(["read", "write", "delete"])
    decoded.valid?.should be_true
  end

  it "demonstrates round-trip compatibility" do
    secret = "test_secret"

    original_payload = JWT::Payload.new(
      subject: "test_user",
      issued_at: Time.utc.to_unix,
      extra_claims: {"data" => JSON::Any.new("test_value")}
    )

    token = JWT::Encoder.encode(original_payload, secret)
    decoded_token = JWT::Decoder.decode_and_verify(token, secret: secret, verify_expiration: false)

    decoded_token.payload.subject.should eq(original_payload.subject)
    decoded_token.payload.issued_at.should eq(original_payload.issued_at)
    decoded_token.payload["data"].try(&.as_s).should eq("test_value")
  end
end
