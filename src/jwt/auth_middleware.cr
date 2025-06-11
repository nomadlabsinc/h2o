require "./decoder"
require "./types"

module JWT
  class AuthMiddleware
    getter secret : String
    getter algorithm : Algorithm
    getter issuer : String?
    getter audience : String | Array(String) | Nil
    getter leeway : Time::Span

    def initialize(@secret : String, @algorithm : Algorithm = Algorithm::HS256,
                   @issuer : String? = nil, @audience : String | Array(String) | Nil = nil,
                   @leeway : Time::Span = 0.seconds)
    end

    def authenticate(authorization_header : String?) : Token
      unless authorization_header
        raise VerificationError.new("Missing Authorization header")
      end

      token_string = extract_bearer_token(authorization_header)
      token = Decoder.decode_and_verify(
        token_string,
        secret: @secret,
        algorithm: @algorithm,
        leeway: @leeway
      )

      validate_claims(token)
      token
    end

    def authenticate_optional(authorization_header : String?) : Token?
      return nil unless authorization_header

      begin
        authenticate(authorization_header)
      rescue
        nil
      end
    end

    private def extract_bearer_token(header : String) : String
      parts = header.split(' ', 2)

      unless parts.size == 2 && parts[0].downcase == "bearer"
        raise VerificationError.new("Invalid Authorization header format. Expected 'Bearer <token>'")
      end

      parts[1]
    end

    private def validate_claims(token : Token) : Nil
      payload = token.payload

      if expected_issuer = @issuer
        unless payload.issuer == expected_issuer
          raise VerificationError.new("Invalid issuer. Expected '#{expected_issuer}', got '#{payload.issuer}'")
        end
      end

      if expected_audience = @audience
        case expected_audience
        when String
          unless payload.audience == expected_audience
            raise VerificationError.new("Invalid audience. Expected '#{expected_audience}', got '#{payload.audience}'")
          end
        when Array(String)
          case actual_audience = payload.audience
          when String
            unless actual_audience.in?(expected_audience)
              raise VerificationError.new("Invalid audience. Expected one of #{expected_audience}, got '#{actual_audience}'")
            end
          when Array(String)
            unless expected_audience.any? { |aud| actual_audience.includes?(aud) }
              raise VerificationError.new("Invalid audience. Expected overlap with #{expected_audience}, got #{actual_audience}")
            end
          else
            raise VerificationError.new("Invalid audience. Expected audience claim")
          end
        end
      end
    end
  end

  class RequestAuthenticator
    getter middleware : AuthMiddleware

    def initialize(@middleware : AuthMiddleware)
    end

    def add_auth_header(headers : HTTP::Headers, token : String) : Nil
      headers["Authorization"] = "Bearer #{token}"
    end

    def extract_user_id(token : Token) : String?
      token.payload.subject
    end

    def extract_roles(token : Token) : Array(String)
      if roles_claim = token.payload["roles"]?
        case roles_claim
        when .as_a?
          roles_claim.as_a.map(&.as_s)
        when .as_s?
          [roles_claim.as_s]
        else
          [] of String
        end
      else
        [] of String
      end
    end

    def extract_permissions(token : Token) : Array(String)
      if perms_claim = token.payload["permissions"]?
        case perms_claim
        when .as_a?
          perms_claim.as_a.map(&.as_s)
        when .as_s?
          [perms_claim.as_s]
        else
          [] of String
        end
      else
        [] of String
      end
    end

    def has_role?(token : Token, role : String) : Bool
      extract_roles(token).includes?(role)
    end

    def has_permission?(token : Token, permission : String) : Bool
      extract_permissions(token).includes?(permission)
    end
  end
end
