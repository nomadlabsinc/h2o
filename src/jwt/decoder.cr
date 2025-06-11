require "base64"
require "json"
require "openssl/hmac"
require "./types"

module JWT
  module Decoder
    extend self

    def decode(token : String, verify : Bool = true) : Token
      parts = token.split('.')

      unless parts.size == 3
        raise DecodeError.new("Invalid JWT format: expected 3 parts, got #{parts.size}")
      end

      header_part, payload_part, signature_part = parts

      begin
        header_json = decode_base64_url(header_part)
        header = Header.from_json(header_json)
      rescue ex : Base64::Error | JSON::ParseException
        raise DecodeError.new("Invalid header: #{ex.message}")
      end

      begin
        payload_json = decode_base64_url(payload_part)
        payload = parse_payload(payload_json)
      rescue ex : Base64::Error | JSON::ParseException
        raise DecodeError.new("Invalid payload: #{ex.message}")
      end

      begin
        signature = decode_base64_url_raw(signature_part)
      rescue ex : Base64::Error
        raise DecodeError.new("Invalid signature: #{ex.message}")
      end

      Token.new(header, payload, signature, token)
    end

    def decode_and_verify(token : String, secret : String? = nil, public_key : String? = nil,
                          algorithm : Algorithm? = nil, verify_expiration : Bool = true,
                          verify_not_before : Bool = true, leeway : Time::Span = 0.seconds) : Token
      decoded_token = decode(token, verify: false)

      if algorithm && decoded_token.algorithm != algorithm
        raise VerificationError.new("Algorithm mismatch: expected #{algorithm}, got #{decoded_token.algorithm}")
      end

      case decoded_token.algorithm
      when .hs256?, .hs384?, .hs512?
        unless secret
          raise VerificationError.new("Secret required for HMAC algorithms")
        end
        verify_hmac_signature(decoded_token, secret)
      when .rs256?, .rs384?, .rs512?, .es256?, .es384?, .es512?
        unless public_key
          raise VerificationError.new("Public key required for RSA/ECDSA algorithms")
        end
        raise VerificationError.new("RSA/ECDSA signature verification not yet implemented")
      when .none?
        unless decoded_token.signature.empty?
          raise VerificationError.new("None algorithm must have empty signature")
        end
      end

      now = Time.utc

      if verify_expiration && decoded_token.payload.expired?(now - leeway)
        raise ExpiredTokenError.new("Token has expired")
      end

      if verify_not_before && decoded_token.payload.premature?(now + leeway)
        raise PrematureTokenError.new("Token is not yet valid")
      end

      decoded_token
    end

    private def decode_base64_url(encoded : String) : String
      padded = case encoded.size % 4
               when 2
                 encoded + "=="
               when 3
                 encoded + "="
               else
                 encoded
               end

      Base64.decode_string(padded.tr("-_", "+/"))
    end

    private def decode_base64_url_raw(encoded : String) : Bytes
      padded = case encoded.size % 4
               when 2
                 encoded + "=="
               when 3
                 encoded + "="
               else
                 encoded
               end

      Base64.decode(padded.tr("-_", "+/"))
    end

    private def parse_payload(json_string : String) : Payload
      json = JSON.parse(json_string)

      unless json.as_h?
        raise DecodeError.new("Payload must be a JSON object")
      end

      payload_hash = json.as_h
      extra_claims = Hash(String, JSON::Any).new

      standard_claims = %w[iss sub aud exp nbf iat jti]

      payload_hash.each do |key, value|
        unless key.in?(standard_claims)
          extra_claims[key] = value
        end
      end

      audience = case aud = payload_hash["aud"]?
                 when JSON::Any
                   case aud.raw
                   when String
                     aud.as_s
                   when Array
                     aud.as_a.map(&.as_s)
                   else
                     raise DecodeError.new("Invalid audience claim type")
                   end
                 when String
                   aud.as_s
                 when Array
                   aud.as_a.map(&.as_s)
                 when Nil
                   nil
                 else
                   raise DecodeError.new("Invalid audience claim type")
                 end

      Payload.new(
        issuer: payload_hash["iss"]?.try(&.as_s?),
        subject: payload_hash["sub"]?.try(&.as_s?),
        audience: audience,
        expires_at: payload_hash["exp"]?.try(&.as_i64?),
        not_before: payload_hash["nbf"]?.try(&.as_i64?),
        issued_at: payload_hash["iat"]?.try(&.as_i64?),
        jwt_id: payload_hash["jti"]?.try(&.as_s?),
        extra_claims: extra_claims
      )
    end

    private def verify_hmac_signature(token : Token, secret : String) : Nil
      parts = token.raw_token.split('.')
      message = "#{parts[0]}.#{parts[1]}"

      expected_signature = case token.algorithm
                           when .hs256?
                             OpenSSL::HMAC.digest(:sha256, secret, message)
                           when .hs384?
                             OpenSSL::HMAC.digest(:sha384, secret, message)
                           when .hs512?
                             OpenSSL::HMAC.digest(:sha512, secret, message)
                           else
                             raise VerificationError.new("Invalid HMAC algorithm")
                           end

      actual_signature = decode_base64_url_raw(parts[2])

      unless expected_signature == actual_signature
        raise VerificationError.new("Signature verification failed")
      end
    end
  end
end
