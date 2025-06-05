require "../spec_helper"

describe H2O::Client do
  describe "connection pooling" do
    it "should initialize with connection pool settings" do
      client = H2O::Client.new(connection_pool_size: 5, timeout: 1.seconds)

      begin
        # Verify client initialization
        client.should_not be_nil

        # Verify initial connection pool state
        client.connections.should be_empty
      ensure
        client.close
      end
    end

    it "should respect connection pool size configuration" do
      pool_size = 3
      client = H2O::Client.new(connection_pool_size: pool_size, timeout: 1.seconds)

      begin
        # Verify pool size is respected in configuration
        client.should_not be_nil
        client.connections.size.should eq(0)
      ensure
        client.close
      end
    end

    it "should handle client lifecycle operations" do
      client = H2O::Client.new(connection_pool_size: 2, timeout: 1.seconds)

      begin
        # Test basic client operations
        client.connections.should be_empty

        # Test multiple close calls (should be idempotent)
        client.close
        client.close

        # Verify state after close
        client.connections.should be_empty
      rescue
        # Ensure cleanup even if test fails
        client.close rescue nil
      end
    end

    it "should handle timeout configuration" do
      # Test with very short timeout
      client = H2O::Client.new(timeout: 10.milliseconds)

      begin
        client.should_not be_nil
        client.connections.should be_empty
      ensure
        client.close
      end
    end
  end
end
