require "../spec_helper"
require "../../src/jwt"

describe JWT::AuthMiddleware do
  describe "#authenticate" do
    it "successfully authenticates valid bearer token" do
      secret = "test_secret"
      middleware = JWT::AuthMiddleware.new(secret)

      payload = JWT::Payload.new(
        subject: "user123",
        issued_at: Time.utc.to_unix,
        expires_at: (Time.utc + 1.hour).to_unix
      )

      token = JWT::Encoder.encode(payload, secret)
      auth_header = "Bearer #{token}"

      authenticated_token = middleware.authenticate(auth_header)
      authenticated_token.payload.subject.should eq("user123")
    end

    it "raises VerificationError for missing authorization header" do
      middleware = JWT::AuthMiddleware.new("secret")

      expect_raises(JWT::VerificationError, "Missing Authorization header") do
        middleware.authenticate(nil)
      end
    end

    it "raises VerificationError for invalid authorization header format" do
      middleware = JWT::AuthMiddleware.new("secret")

      expect_raises(JWT::VerificationError, "Invalid Authorization header format") do
        middleware.authenticate("Invalid header")
      end
    end

    it "raises VerificationError for invalid bearer token" do
      middleware = JWT::AuthMiddleware.new("secret")

      expect_raises(JWT::DecodeError | JWT::VerificationError) do
        middleware.authenticate("Bearer invalid.token.here")
      end
    end

    it "validates issuer claim when configured" do
      secret = "test_secret"
      expected_issuer = "test_app"
      middleware = JWT::AuthMiddleware.new(secret, issuer: expected_issuer)

      payload = JWT::Payload.new(
        issuer: expected_issuer,
        subject: "user123",
        expires_at: (Time.utc + 1.hour).to_unix
      )

      token = JWT::Encoder.encode(payload, secret)
      auth_header = "Bearer #{token}"

      authenticated_token = middleware.authenticate(auth_header)
      authenticated_token.payload.issuer.should eq(expected_issuer)
    end

    it "raises VerificationError for invalid issuer" do
      secret = "test_secret"
      expected_issuer = "test_app"
      middleware = JWT::AuthMiddleware.new(secret, issuer: expected_issuer)

      payload = JWT::Payload.new(
        issuer: "wrong_issuer",
        subject: "user123",
        expires_at: (Time.utc + 1.hour).to_unix
      )

      token = JWT::Encoder.encode(payload, secret)
      auth_header = "Bearer #{token}"

      expect_raises(JWT::VerificationError, "Invalid issuer") do
        middleware.authenticate(auth_header)
      end
    end

    it "validates string audience when configured" do
      secret = "test_secret"
      expected_audience = "api_service"
      middleware = JWT::AuthMiddleware.new(secret, audience: expected_audience)

      payload = JWT::Payload.new(
        audience: expected_audience,
        subject: "user123",
        expires_at: (Time.utc + 1.hour).to_unix
      )

      token = JWT::Encoder.encode(payload, secret)
      auth_header = "Bearer #{token}"

      authenticated_token = middleware.authenticate(auth_header)
      authenticated_token.payload.audience.should eq(expected_audience)
    end

    it "validates array audience when configured" do
      secret = "test_secret"
      expected_audiences = ["api_service", "web_app"]
      middleware = JWT::AuthMiddleware.new(secret, audience: expected_audiences)

      payload = JWT::Payload.new(
        audience: "api_service",
        subject: "user123",
        expires_at: (Time.utc + 1.hour).to_unix
      )

      token = JWT::Encoder.encode(payload, secret)
      auth_header = "Bearer #{token}"

      authenticated_token = middleware.authenticate(auth_header)
      authenticated_token.payload.audience.should eq("api_service")
    end
  end

  describe "#authenticate_optional" do
    it "returns nil for missing authorization header" do
      middleware = JWT::AuthMiddleware.new("secret")

      result = middleware.authenticate_optional(nil)
      result.should be_nil
    end

    it "returns nil for invalid token" do
      middleware = JWT::AuthMiddleware.new("secret")

      result = middleware.authenticate_optional("Bearer invalid.token")
      result.should be_nil
    end

    it "returns token for valid authorization" do
      secret = "test_secret"
      middleware = JWT::AuthMiddleware.new(secret)

      payload = JWT::Payload.new(
        subject: "user123",
        expires_at: (Time.utc + 1.hour).to_unix
      )

      token = JWT::Encoder.encode(payload, secret)
      auth_header = "Bearer #{token}"

      result = middleware.authenticate_optional(auth_header)
      result.should_not be_nil
      result.not_nil!.payload.subject.should eq("user123")
    end
  end
end

describe JWT::RequestAuthenticator do
  describe "#add_auth_header" do
    it "adds bearer token to headers" do
      middleware = JWT::AuthMiddleware.new("secret")
      authenticator = JWT::RequestAuthenticator.new(middleware)

      headers = HTTP::Headers.new
      token = "example.jwt.token"

      authenticator.add_auth_header(headers, token)
      headers["Authorization"].should eq("Bearer #{token}")
    end
  end

  describe "#extract_user_id" do
    it "extracts user ID from token subject" do
      middleware = JWT::AuthMiddleware.new("secret")
      authenticator = JWT::RequestAuthenticator.new(middleware)

      payload = JWT::Payload.new(subject: "user123")
      header = JWT::Header.new("HS256")
      token = JWT::Token.new(header, payload, Bytes.empty, "")

      user_id = authenticator.extract_user_id(token)
      user_id.should eq("user123")
    end
  end

  describe "#extract_roles" do
    it "extracts roles from array claim" do
      middleware = JWT::AuthMiddleware.new("secret")
      authenticator = JWT::RequestAuthenticator.new(middleware)

      payload = JWT::Payload.new(
        extra_claims: {"roles" => JSON::Any.new(["admin", "user"].map { |s| JSON::Any.new(s) })}
      )
      header = JWT::Header.new("HS256")
      token = JWT::Token.new(header, payload, Bytes.empty, "")

      roles = authenticator.extract_roles(token)
      roles.should eq(["admin", "user"])
    end

    it "extracts roles from string claim" do
      middleware = JWT::AuthMiddleware.new("secret")
      authenticator = JWT::RequestAuthenticator.new(middleware)

      payload = JWT::Payload.new(
        extra_claims: {"roles" => JSON::Any.new("admin")}
      )
      header = JWT::Header.new("HS256")
      token = JWT::Token.new(header, payload, Bytes.empty, "")

      roles = authenticator.extract_roles(token)
      roles.should eq(["admin"])
    end

    it "returns empty array when no roles claim" do
      middleware = JWT::AuthMiddleware.new("secret")
      authenticator = JWT::RequestAuthenticator.new(middleware)

      payload = JWT::Payload.new
      header = JWT::Header.new("HS256")
      token = JWT::Token.new(header, payload, Bytes.empty, "")

      roles = authenticator.extract_roles(token)
      roles.should be_empty
    end
  end

  describe "#has_role?" do
    it "returns true when user has the role" do
      middleware = JWT::AuthMiddleware.new("secret")
      authenticator = JWT::RequestAuthenticator.new(middleware)

      payload = JWT::Payload.new(
        extra_claims: {"roles" => JSON::Any.new(["admin", "user"].map { |s| JSON::Any.new(s) })}
      )
      header = JWT::Header.new("HS256")
      token = JWT::Token.new(header, payload, Bytes.empty, "")

      authenticator.has_role?(token, "admin").should be_true
      authenticator.has_role?(token, "moderator").should be_false
    end
  end
end
