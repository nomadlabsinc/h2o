require "log"

module H2O
  # Performance-conscious logger for detailed debugging
  #
  # This logger is controlled by the `H2O_DEBUG` environment variable.
  # When disabled, logging calls compile down to a single, cached boolean check,
  # ensuring negligible performance impact in production.
  #
  # To enable, set `H2O_DEBUG=true` (or `1`, `yes`, `on`).
  #
  # Usage:
  #   H2O::DebugLogger.log "CONTEXT", "My debug message"
  #
  module DebugLogger
    # Cache the result of the ENV check for performance
    @@enabled : Bool? = nil

    # Checks if debug logging is enabled. The result is cached after the first call.
    def self.enabled? : Bool
      if enabled = @@enabled
        return enabled
      end
      @@enabled = H2O.env_flag_enabled?("H2O_DEBUG")
    end

    # Resets the cached enabled flag (used for testing)
    def self.reset_cache : Nil
      @@enabled = nil
    end

    # Logs a message if debug logging is enabled
    #
    # The message is only evaluated if logging is active.
    def self.log(context : String, message : String) : Nil
      return unless enabled?
      H2O::Log.debug { "[#{context}] #{message}" }
    end
  end
end
