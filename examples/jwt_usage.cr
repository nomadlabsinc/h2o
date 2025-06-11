require "../src/h2o"

# Example demonstrating JWT authentication with H2O client
client = H2O::Client.new

# Configure JWT authentication
secret = "your-secret-key"
client.configure_jwt_auth(
  secret: secret,
  algorithm: JWT::Algorithm::HS256,
  issuer: "your-app",
  audience: "api-service"
)

# Create and encode a JWT token
payload = JWT::Payload.new(
  issuer: "your-app",
  subject: "user123",
  audience: "api-service",
  expires_at: (Time.utc + 24.hours).to_unix,
  issued_at: Time.utc.to_unix,
  extra_claims: {
    "role"        => JSON::Any.new("admin"),
    "permissions" => JSON::Any.new(["read", "write"].map { |s| JSON::Any.new(s) }),
  }
)

token = JWT::Encoder.encode(payload, secret)
puts "Generated JWT token: #{token[0..50]}..."

# Set the bearer token for all requests
client.set_bearer_token(token)

# Example: Make authenticated requests
# response = client.get("https://api.example.com/protected")

# Example: Validate incoming JWT tokens
auth_header = "Bearer #{token}"
begin
  validated_token = client.validate_token(auth_header)
  puts "Token validation successful!"
  puts "User ID: #{client.extract_user_info(validated_token)[:user_id]}"
  puts "Roles: #{client.extract_user_info(validated_token)[:roles]}"
  puts "Has admin role: #{client.has_role?(validated_token, "admin")}"
rescue e : JWT::VerificationError
  puts "Token validation failed: #{e.message}"
end

client.close
