require "digest/sha256"
require "./tls_cache"

module H2O
  # Certificate validation with caching support
  class CertValidator
    # Compute fingerprint for a certificate
    def self.fingerprint(cert_data : Bytes) : String
      Digest::SHA256.hexdigest(cert_data)
    end

    # Validate certificate with caching
    def self.validate_cached(cert_data : Bytes, subject : String, issuer : String, expires : Time) : Bool
      fingerprint = fingerprint(cert_data)

      # Check cache first
      if cached = H2O.tls_cache.get_cert_validation(fingerprint)
        return cached.valid
      end

      # Perform validation
      valid = validate_cert(subject, issuer, expires)

      # Cache the result
      result = CertValidationResult.new(valid, subject, issuer, expires)
      H2O.tls_cache.set_cert_validation(fingerprint, result)

      valid
    end

    # Basic certificate validation logic
    private def self.validate_cert(subject : String, issuer : String, expires : Time) : Bool
      # Check expiration
      return false if Time.utc > expires

      # Check basic subject/issuer validity
      return false if subject.empty? || issuer.empty?

      # Additional validation logic would go here
      # For now, just return true if not expired
      true
    end
  end
end
