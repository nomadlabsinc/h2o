require "../h2o"
require "./auth_middleware"

module JWT
  module ClientIntegration
    def self.add_auth_support(client_class : T.class) : Nil forall T
      client_class.property jwt_authenticator : JWT::RequestAuthenticator?

      client_class.def_delegator jwt_authenticator, add_auth_header
      client_class.def_delegator jwt_authenticator, extract_user_id
      client_class.def_delegator jwt_authenticator, extract_roles
      client_class.def_delegator jwt_authenticator, extract_permissions
      client_class.def_delegator jwt_authenticator, has_role?
      client_class.def_delegator jwt_authenticator, has_permission?
    end
  end

  module AuthenticatedClient
    macro included
      property jwt_authenticator : JWT::RequestAuthenticator?

      def configure_jwt_auth(secret : String, algorithm : JWT::Algorithm = JWT::Algorithm::HS256,
                             issuer : String? = nil, audience : String | Array(String) | Nil = nil,
                             leeway : Time::Span = 0.seconds) : Nil
        middleware = JWT::AuthMiddleware.new(secret, algorithm, issuer, audience, leeway)
        @jwt_authenticator = JWT::RequestAuthenticator.new(middleware)
      end

      def set_bearer_token(token : String) : Nil
        if auth = @jwt_authenticator
          @default_headers ||= HTTP::Headers.new
          auth.add_auth_header(@default_headers.not_nil!, token)
        else
          raise ArgumentError.new("JWT authentication not configured. Call configure_jwt_auth first.")
        end
      end

      def validate_token(authorization_header : String?) : JWT::Token
        if auth = @jwt_authenticator
          auth.middleware.authenticate(authorization_header)
        else
          raise ArgumentError.new("JWT authentication not configured. Call configure_jwt_auth first.")
        end
      end

      def validate_token_optional(authorization_header : String?) : JWT::Token?
        if auth = @jwt_authenticator
          auth.middleware.authenticate_optional(authorization_header)
        else
          nil
        end
      end

      def extract_user_info(token : JWT::Token) : NamedTuple(user_id: String?, roles: Array(String), permissions: Array(String))
        if auth = @jwt_authenticator
          {
            user_id:     auth.extract_user_id(token),
            roles:       auth.extract_roles(token),
            permissions: auth.extract_permissions(token),
          }
        else
          {user_id: nil, roles: [] of String, permissions: [] of String}
        end
      end

      def has_role?(token : JWT::Token, role : String) : Bool
        if auth = @jwt_authenticator
          auth.has_role?(token, role)
        else
          false
        end
      end

      def has_permission?(token : JWT::Token, permission : String) : Bool
        if auth = @jwt_authenticator
          auth.has_permission?(token, permission)
        else
          false
        end
      end
    end
  end
end
