require "../spec_helper"
require "../../src/h2o"
require "../../src/jwt"

describe JWT::AuthenticatedClient do
  describe "JWT integration with H2O::Client" do
    it "configures JWT authentication" do
      client = H2O::Client.new
      secret = "test_secret"

      client.configure_jwt_auth(secret)
      client.jwt_authenticator.should_not be_nil
    end

    it "sets bearer token in default headers" do
      client = H2O::Client.new
      secret = "test_secret"

      client.configure_jwt_auth(secret)

      payload = JWT::Payload.new(
        subject: "user123",
        expires_at: (Time.utc + 1.hour).to_unix
      )
      token = JWT::Encoder.encode(payload, secret)

      client.set_bearer_token(token)

      client.default_headers.should_not be_nil
      client.default_headers.not_nil!["Authorization"].should eq("Bearer #{token}")
    end

    it "validates tokens correctly" do
      client = H2O::Client.new
      secret = "test_secret"

      client.configure_jwt_auth(secret)

      payload = JWT::Payload.new(
        subject: "user123",
        expires_at: (Time.utc + 1.hour).to_unix
      )
      token = JWT::Encoder.encode(payload, secret)
      auth_header = "Bearer #{token}"

      validated_token = client.validate_token(auth_header)
      validated_token.payload.subject.should eq("user123")
    end

    it "raises error when JWT not configured for token validation" do
      client = H2O::Client.new

      expect_raises(ArgumentError, "JWT authentication not configured") do
        client.validate_token("Bearer token")
      end
    end

    it "raises error when JWT not configured for setting bearer token" do
      client = H2O::Client.new

      expect_raises(ArgumentError, "JWT authentication not configured") do
        client.set_bearer_token("token")
      end
    end

    it "extracts user information correctly" do
      client = H2O::Client.new
      secret = "test_secret"

      client.configure_jwt_auth(secret)

      payload = JWT::Payload.new(
        subject: "user123",
        extra_claims: {
          "roles"       => JSON::Any.new(["admin", "user"].map { |s| JSON::Any.new(s) }),
          "permissions" => JSON::Any.new(["read", "write"].map { |s| JSON::Any.new(s) }),
        }
      )

      header = JWT::Header.new("HS256")
      token = JWT::Token.new(header, payload, Bytes.empty, "")

      user_info = client.extract_user_info(token)
      user_info[:user_id].should eq("user123")
      user_info[:roles].should eq(["admin", "user"])
      user_info[:permissions].should eq(["read", "write"])
    end

    it "checks roles correctly" do
      client = H2O::Client.new
      secret = "test_secret"

      client.configure_jwt_auth(secret)

      payload = JWT::Payload.new(
        extra_claims: {"roles" => JSON::Any.new(["admin", "user"].map { |s| JSON::Any.new(s) })}
      )

      header = JWT::Header.new("HS256")
      token = JWT::Token.new(header, payload, Bytes.empty, "")

      client.has_role?(token, "admin").should be_true
      client.has_role?(token, "moderator").should be_false
    end

    it "checks permissions correctly" do
      client = H2O::Client.new
      secret = "test_secret"

      client.configure_jwt_auth(secret)

      payload = JWT::Payload.new(
        extra_claims: {"permissions" => JSON::Any.new(["read", "write"].map { |s| JSON::Any.new(s) })}
      )

      header = JWT::Header.new("HS256")
      token = JWT::Token.new(header, payload, Bytes.empty, "")

      client.has_permission?(token, "read").should be_true
      client.has_permission?(token, "delete").should be_false
    end

    it "handles optional token validation gracefully" do
      client = H2O::Client.new
      secret = "test_secret"

      client.configure_jwt_auth(secret)

      # Valid token
      payload = JWT::Payload.new(
        subject: "user123",
        expires_at: (Time.utc + 1.hour).to_unix
      )
      token = JWT::Encoder.encode(payload, secret)
      auth_header = "Bearer #{token}"

      result = client.validate_token_optional(auth_header)
      result.should_not be_nil
      result.not_nil!.payload.subject.should eq("user123")

      # Invalid token
      result = client.validate_token_optional("Bearer invalid.token")
      result.should be_nil

      # Missing header
      result = client.validate_token_optional(nil)
      result.should be_nil
    end

    it "returns empty info when JWT not configured" do
      client = H2O::Client.new

      payload = JWT::Payload.new(subject: "user123")
      header = JWT::Header.new("HS256")
      token = JWT::Token.new(header, payload, Bytes.empty, "")

      user_info = client.extract_user_info(token)
      user_info[:user_id].should be_nil
      user_info[:roles].should be_empty
      user_info[:permissions].should be_empty

      client.has_role?(token, "admin").should be_false
      client.has_permission?(token, "read").should be_false
    end
  end
end
