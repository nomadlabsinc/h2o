require "base64"
require "json"
require "openssl/hmac"
require "./types"

module JWT
  module Encoder
    extend self

    def encode(payload : Payload, secret : String, algorithm : Algorithm = Algorithm::HS256,
               header_claims : Hash(String, JSON::Any) = Hash(String, JSON::Any).new) : String
      header = Header.new(algorithm.to_s, "JWT")

      header_json = header.to_json
      payload_json = build_payload_json(payload)

      encoded_header = encode_base64_url(header_json)
      encoded_payload = encode_base64_url(payload_json)

      message = "#{encoded_header}.#{encoded_payload}"
      signature = generate_signature(message, secret, algorithm)
      encoded_signature = encode_base64_url_raw(signature)

      "#{message}.#{encoded_signature}"
    end

    def encode_with_key_id(payload : Payload, secret : String, key_id : String,
                           algorithm : Algorithm = Algorithm::HS256) : String
      header = Header.new(algorithm.to_s, "JWT", key_id)

      header_json = header.to_json
      payload_json = build_payload_json(payload)

      encoded_header = encode_base64_url(header_json)
      encoded_payload = encode_base64_url(payload_json)

      message = "#{encoded_header}.#{encoded_payload}"
      signature = generate_signature(message, secret, algorithm)
      encoded_signature = encode_base64_url_raw(signature)

      "#{message}.#{encoded_signature}"
    end

    private def encode_base64_url(data : String) : String
      Base64.strict_encode(data).tr("+/", "-_").rstrip('=')
    end

    private def encode_base64_url_raw(data : Bytes) : String
      Base64.strict_encode(data).tr("+/", "-_").rstrip('=')
    end

    private def build_payload_json(payload : Payload) : String
      json_builder = JSON.build do |json|
        json.object do
          if issuer = payload.issuer
            json.field "iss", issuer
          end

          if subject = payload.subject
            json.field "sub", subject
          end

          if audience = payload.audience
            json.field "aud", audience
          end

          if expires_at = payload.expires_at
            json.field "exp", expires_at
          end

          if not_before = payload.not_before
            json.field "nbf", not_before
          end

          if issued_at = payload.issued_at
            json.field "iat", issued_at
          end

          if jwt_id = payload.jwt_id
            json.field "jti", jwt_id
          end

          payload.extra_claims.each do |key, value|
            json.field key, value
          end
        end
      end

      json_builder
    end

    private def generate_signature(message : String, secret : String, algorithm : Algorithm) : Bytes
      case algorithm
      when .hs256?
        OpenSSL::HMAC.digest(:sha256, secret, message)
      when .hs384?
        OpenSSL::HMAC.digest(:sha384, secret, message)
      when .hs512?
        OpenSSL::HMAC.digest(:sha512, secret, message)
      when .none?
        Bytes.empty
      else
        raise ArgumentError.new("Unsupported algorithm for encoding: #{algorithm}")
      end
    end
  end
end
