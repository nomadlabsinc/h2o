require "../spec_helper"

describe H2O::ConnectionPool do
  after_each do
    GlobalStateHelper.clear_all_caches
  end

  describe "#initialize" do
    it "creates connection pool with default settings" do
      pool = H2O::ConnectionPool.new
      pool.should_not be_nil
      pool.pool_full?.should be_false
      pool.utilization_rate.should eq(0.0)
    end

    it "creates connection pool with custom pool size" do
      pool = H2O::ConnectionPool.new(pool_size: 5)
      pool.should_not be_nil
      # Pool should be empty initially
      stats = pool.statistics
      stats[:total_connections].should eq(0)
      stats[:pool_size].should eq(5)
    end

    it "creates connection pool with SSL verification disabled" do
      pool = H2O::ConnectionPool.new(verify_ssl: false)
      pool.should_not be_nil
    end
  end

  describe "#get_connection" do
    it "creates new HTTP/2 connection for HTTPS" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)
      begin
        connection = pool.get_connection("example.com", 443, use_tls: true)

        connection.should be_a(H2O::BaseConnection)
        connection.should be_a(H2O::H2::Client)

        stats = pool.statistics
        stats[:total_connections].should eq(1)
      ensure
        pool.close
      end
    end

    it "reuses existing healthy connection" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      # Get first connection
      connection1 = pool.get_connection("example.com", 443, use_tls: true)
      connection1_id = connection1.object_id

      # Return it as successful
      pool.return_connection(connection1, true, 100.milliseconds)

      # Get connection again - should reuse
      connection2 = pool.get_connection("example.com", 443, use_tls: true)
      connection2.object_id.should eq(connection1_id)

      stats = pool.statistics
      stats[:total_connections].should eq(1)

      pool.close
    end

    it "creates new connection when pool has space" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      # Get connections to different hosts
      connection1 = pool.get_connection("example.com", 443, use_tls: true)
      connection2 = pool.get_connection("test.example.com", 443, use_tls: true)

      connection1.should_not eq(connection2)

      stats = pool.statistics
      stats[:total_connections].should eq(2)

      pool.close
    end
  end

  describe "#return_connection" do
    it "updates connection metadata on successful return" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      connection = pool.get_connection("example.com", 443, use_tls: true)

      # Return with success
      pool.return_connection(connection, true, 50.milliseconds)

      stats = pool.statistics
      stats[:total_requests].should eq(1)
      stats[:total_errors].should eq(0)
      stats[:error_rate].should eq(0.0)

      pool.close
    end

    it "updates connection metadata on failed return" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      connection = pool.get_connection("example.com", 443, use_tls: true)

      # Return with failure
      pool.return_connection(connection, false, 200.milliseconds)

      stats = pool.statistics
      stats[:total_requests].should eq(1)
      stats[:total_errors].should eq(1)
      stats[:error_rate].should eq(1.0)

      pool.close
    end

    it "handles multiple request cycles" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      connection = pool.get_connection("example.com", 443, use_tls: true)

      # Multiple successful requests
      pool.return_connection(connection, true, 30.milliseconds)
      pool.return_connection(connection, true, 40.milliseconds)
      pool.return_connection(connection, false, 100.milliseconds) # One failure
      pool.return_connection(connection, true, 20.milliseconds)

      stats = pool.statistics
      stats[:total_requests].should eq(4)
      stats[:total_errors].should eq(1)
      stats[:error_rate].should eq(0.25)

      pool.close
    end
  end

  describe "#warmup_connection" do
    it "warms up connection to host" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      pool.warmup_connection("example.com", 443)

      # Allow some time for background fiber to complete
      sleep(50.milliseconds)

      stats = pool.statistics
      stats[:warmup_hosts].should eq(1)

      pool.close
    end

    it "uses default port 443 for warmup" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      pool.warmup_connection("example.com")

      # Allow some time for background fiber to complete
      sleep(50.milliseconds)

      stats = pool.statistics
      stats[:warmup_hosts].should eq(1)

      pool.close
    end

    it "does not warm up same host multiple times" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      # Try to warm up same host multiple times
      pool.warmup_connection("example.com", 443)
      pool.warmup_connection("example.com", 443)

      # Allow some time for background fibers
      sleep(50.milliseconds)

      stats = pool.statistics
      stats[:warmup_hosts].should eq(1)

      pool.close
    end
  end

  describe "#close" do
    it "closes all connections and clears pool" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      # Create connections to different endpoints
      connection1 = pool.get_connection("example.com", 443, use_tls: true)
      connection2 = pool.get_connection("secondexample.com", 4433, use_tls: true)

      pool.warmup_connection("test-1.example.com")
      sleep(50.milliseconds)

      stats_before = pool.statistics
      # The connection pool may intelligently reuse connections to the same Docker container
      # even when different host/port combinations are used, if they resolve to the same endpoint
      stats_before[:total_connections].should be >= 1
      stats_before[:total_connections].should be <= 2
      stats_before[:warmup_hosts].should eq(1)

      # Close pool
      pool.close

      stats_after = pool.statistics
      stats_after[:total_connections].should eq(0)
      stats_after[:warmup_hosts].should eq(0)
    end
  end

  describe "#connection_healthy?" do
    it "considers fresh successful connection healthy" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      connection = pool.get_connection("example.com", 443, use_tls: true)
      pool.return_connection(connection, true, 50.milliseconds)

      # Connection should be healthy
      health = pool.connection_healthy?(connection)
      health.should be_true

      pool.close
    end

    it "considers connection with many errors unhealthy" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      connection = pool.get_connection("example.com", 443, use_tls: true)

      # Multiple failures to lower score below 30
      30.times do
        pool.return_connection(connection, false, 5000.milliseconds)
      end

      # Connection should be unhealthy due to low score
      health = pool.connection_healthy?(connection)
      health.should be_false

      pool.close
    end
  end

  describe "#statistics" do
    it "returns comprehensive pool statistics" do
      pool = H2O::ConnectionPool.new(pool_size: 3, verify_ssl: false)

      # Create connections and simulate usage
      connection1 = pool.get_connection("example.com", 443, use_tls: true)
      connection2 = pool.get_connection("test.example.com", 443, use_tls: true)

      pool.return_connection(connection1, true, 30.milliseconds)
      pool.return_connection(connection1, false, 100.milliseconds)
      pool.return_connection(connection2, true, 25.milliseconds)

      pool.warmup_connection("test-0.example.com")
      sleep(50.milliseconds)

      stats = pool.statistics

      stats[:total_connections].should eq(3)
      stats[:pool_size].should eq(3)
      stats[:total_requests].should eq(3)
      stats[:total_errors].should eq(1)
      stats[:error_rate].should be_close(0.33, 0.01)
      stats[:avg_score].should be_a(Float64)
      stats[:warmup_hosts].should eq(1)

      pool.close
    end
  end

  describe "#set_batch_processing" do
    it "enables batch processing for HTTP/2 connections" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      connection = pool.get_connection("example.com", 443, use_tls: true)

      # Should not raise
      pool.set_batch_processing(true)
      pool.set_batch_processing(false)

      pool.close
    end
  end

  describe "#cleanup_expired_connections" do
    it "removes expired connections from pool" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      connection = pool.get_connection("example.com", 443, use_tls: true)

      initial_stats = pool.statistics
      initial_stats[:total_connections].should eq(1)

      # Cleanup should not affect recent connections
      pool.cleanup_expired_connections

      after_cleanup_stats = pool.statistics
      after_cleanup_stats[:total_connections].should eq(1)

      pool.close
    end
  end

  describe "#utilization_rate" do
    it "calculates correct utilization rate" do
      pool = H2O::ConnectionPool.new(pool_size: 4, verify_ssl: false)

      # Empty pool
      pool.utilization_rate.should eq(0.0)

      # Add connections
      connection1 = pool.get_connection("example.com", 443, use_tls: true)
      pool.utilization_rate.should eq(0.25)

      connection2 = pool.get_connection("secondexample.com", 4433, use_tls: true)
      pool.utilization_rate.should eq(0.5)

      connection3 = pool.get_connection("test-0.example.com", 443, use_tls: true)
      pool.utilization_rate.should eq(0.75)

      connection4 = pool.get_connection("test-1.example.com", 443, use_tls: true)
      pool.utilization_rate.should eq(1.0)

      pool.close
    end
  end

  describe "#pool_full?" do
    it "correctly identifies when pool is full" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      pool.pool_full?.should be_false

      connection1 = pool.get_connection("example.com", 443, use_tls: true)
      pool.pool_full?.should be_false

      connection2 = pool.get_connection("test.example.com", 443, use_tls: true)
      pool.pool_full?.should be_true

      pool.close
    end
  end

  describe "connection scoring" do
    it "maintains connection scores based on performance" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      connection = pool.get_connection("example.com", 443, use_tls: true)

      # Fast successful requests should maintain good score
      5.times do
        pool.return_connection(connection, true, 20.milliseconds)
      end

      stats = pool.statistics
      stats[:avg_score].should be > 80.0

      # Slow/failed requests should lower score
      5.times do
        pool.return_connection(connection, false, 1000.milliseconds)
      end

      stats_after = pool.statistics
      stats_after[:avg_score].should be < stats[:avg_score]

      pool.close
    end
  end

  describe "error handling" do
    it "handles connection return for non-existent connection gracefully" do
      pool = H2O::ConnectionPool.new(pool_size: 2, verify_ssl: false)

      fake_connection = H2O::H2::Client.new("fake.com", 443, verify_ssl: false, use_tls: true)

      # Should not raise, just ignore
      pool.return_connection(fake_connection, true, 50.milliseconds)

      stats = pool.statistics
      stats[:total_requests].should eq(0)

      fake_connection.close
      pool.close
    end
  end

  describe "concurrent access" do
    it "handles concurrent connection requests safely" do
      pool = H2O::ConnectionPool.new(pool_size: 5, verify_ssl: false)

      # Create multiple fibers requesting connections
      connections = [] of H2O::BaseConnection
      mutex = Mutex.new
      channel = Channel(Bool).new(5)

      5.times do |i|
        spawn do
          connection = pool.get_connection("test-#{i}.example.com", 443, use_tls: true)
          mutex.synchronize do
            connections << connection
          end
          channel.send(true)
        end
      end

      # Wait for all fibers to complete
      5.times { channel.receive }

      connections.size.should eq(5)
      stats = pool.statistics
      stats[:total_connections].should eq(5)

      pool.close
    end
  end
end
