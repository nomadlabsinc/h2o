require "base64"
require "json"

module JWT
  enum Algorithm
    HS256
    HS384
    HS512
    RS256
    RS384
    RS512
    ES256
    ES384
    ES512
    None

    def to_s(io : IO) : Nil
      io << case self
      when .hs256?
        "HS256"
      when .hs384?
        "HS384"
      when .hs512?
        "HS512"
      when .rs256?
        "RS256"
      when .rs384?
        "RS384"
      when .rs512?
        "RS512"
      when .es256?
        "ES256"
      when .es384?
        "ES384"
      when .es512?
        "ES512"
      when .none?
        "none"
      end
    end

    def to_s : String
      case self
      when .hs256?
        "HS256"
      when .hs384?
        "HS384"
      when .hs512?
        "HS512"
      when .rs256?
        "RS256"
      when .rs384?
        "RS384"
      when .rs512?
        "RS512"
      when .es256?
        "ES256"
      when .es384?
        "ES384"
      when .es512?
        "ES512"
      when .none?
        "none"
      else
        ""
      end
    end

    def self.from_string(str : String) : Algorithm
      case str.upcase
      when "HS256"
        HS256
      when "HS384"
        HS384
      when "HS512"
        HS512
      when "RS256"
        RS256
      when "RS384"
        RS384
      when "RS512"
        RS512
      when "ES256"
        ES256
      when "ES384"
        ES384
      when "ES512"
        ES512
      when "NONE"
        None
      else
        raise ArgumentError.new("Unsupported algorithm: #{str}")
      end
    end
  end

  struct Header
    include JSON::Serializable

    @[JSON::Field(key: "alg")]
    getter algorithm : String

    @[JSON::Field(key: "typ")]
    getter type : String = "JWT"

    @[JSON::Field(key: "kid")]
    getter key_id : String?

    def initialize(@algorithm : String, @type : String = "JWT", @key_id : String? = nil)
    end

    def algorithm_enum : Algorithm
      Algorithm.from_string(@algorithm)
    end
  end

  struct Payload
    include JSON::Serializable

    @[JSON::Field(key: "iss")]
    getter issuer : String?

    @[JSON::Field(key: "sub")]
    getter subject : String?

    @[JSON::Field(key: "aud")]
    getter audience : String | Array(String) | Nil

    @[JSON::Field(key: "exp")]
    getter expires_at : Int64?

    @[JSON::Field(key: "nbf")]
    getter not_before : Int64?

    @[JSON::Field(key: "iat")]
    getter issued_at : Int64?

    @[JSON::Field(key: "jti")]
    getter jwt_id : String?

    @[JSON::Field(ignore: true)]
    getter extra_claims : Hash(String, JSON::Any) = Hash(String, JSON::Any).new

    def initialize(@issuer : String? = nil, @subject : String? = nil, @audience : String | Array(String) | Nil = nil,
                   @expires_at : Int64? = nil, @not_before : Int64? = nil, @issued_at : Int64? = nil,
                   @jwt_id : String? = nil, @extra_claims : Hash(String, JSON::Any) = Hash(String, JSON::Any).new)
    end

    def expired?(now : Time = Time.utc) : Bool
      if exp = @expires_at
        now.to_unix > exp
      else
        false
      end
    end

    def premature?(now : Time = Time.utc) : Bool
      if nbf = @not_before
        now.to_unix < nbf
      else
        false
      end
    end

    def []?(key : String) : JSON::Any?
      @extra_claims[key]?
    end

    def [](key : String) : JSON::Any
      @extra_claims[key]
    end

    def []=(key : String, value : JSON::Any) : Nil
      @extra_claims[key] = value
    end
  end

  struct Token
    getter header : Header
    getter payload : Payload
    getter signature : Bytes
    getter raw_token : String

    def initialize(@header : Header, @payload : Payload, @signature : Bytes, @raw_token : String)
    end

    def algorithm : Algorithm
      @header.algorithm_enum
    end

    def valid?(now : Time = Time.utc) : Bool
      !@payload.expired?(now) && !@payload.premature?(now)
    end
  end

  class DecodeError < Exception
  end

  class VerificationError < Exception
  end

  class ExpiredTokenError < Exception
  end

  class PrematureTokenError < Exception
  end
end
