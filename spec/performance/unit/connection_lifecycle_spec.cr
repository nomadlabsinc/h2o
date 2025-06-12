require "../../spec_helper"

describe "Connection Lifecycle Management" do
  describe "connection state management" do
    it "properly initializes connection state" do
      # Mock connection creation without actual network
      connection = MockConnection.new

      connection.closed?.should be_false
      connection.closing?.should be_false
    end

    it "handles single close call correctly" do
      connection = MockConnection.new

      connection.close

      connection.closed?.should be_true
    end

    it "handles multiple close calls without errors" do
      connection = MockConnection.new

      # Multiple close calls should be idempotent
      connection.close
      connection.close
      connection.close

      connection.closed?.should be_true
    end

    it "prevents operations on closed connections" do
      connection = MockConnection.new
      connection.close

      # Operations on closed connections should be handled gracefully
      expect_raises(H2O::ConnectionError, /Connection is closed/) do
        connection.simulate_request
      end
    end
  end

  describe "fiber coordination" do
    it "properly manages fiber lifecycle" do
      coordinator = FiberCoordinator.new

      # Start some fibers
      coordinator.start_fibers(3)
      coordinator.fibers_running?.should be_true

      # Stop fibers gracefully
      coordinator.stop_fibers
      coordinator.fibers_running?.should be_false
    end

    it "handles fiber termination timeout gracefully" do
      coordinator = FiberCoordinator.new

      # Start a stubborn fiber that doesn't respond to close signals
      coordinator.start_stubborn_fiber

      # Should timeout gracefully without hanging
      start_time = Time.monotonic
      coordinator.stop_fibers_with_timeout(100.milliseconds)
      elapsed = Time.monotonic - start_time

      # Should complete within reasonable time (timeout + safety margin)
      elapsed.should be < 200.milliseconds
    end

    it "prevents race conditions during shutdown" do
      coordinator = FiberCoordinator.new
      coordinator.start_fibers(5)

      # Multiple concurrent close attempts
      results = Array(Bool).new
      fibers = Array(Fiber).new

      5.times do
        fibers << spawn do
          begin
            coordinator.stop_fibers
            results << true
          rescue
            results << false
          end
        end
      end

      # Wait for all fibers to complete
      sleep 50.milliseconds # Give time for fibers to complete

      # All should succeed without race conditions
      results.all?(&.itself).should be_true
      coordinator.fibers_running?.should be_false
    end
  end

  describe "channel management" do
    it "handles channel closure correctly" do
      manager = ChannelManager.new

      manager.channels_open?.should be_true

      manager.close_channels

      manager.channels_open?.should be_false
    end

    it "handles operations on closed channels gracefully" do
      manager = ChannelManager.new
      manager.close_channels

      # Should not raise Channel::ClosedError
      result = manager.try_send_message("test")
      result.should be_false
    end

    it "prevents sending to closed channels" do
      manager = ChannelManager.new

      # Send a message successfully
      result1 = manager.try_send_message("first")
      result1.should be_true

      # Close channels
      manager.close_channels

      # Subsequent sends should fail gracefully
      result2 = manager.try_send_message("second")
      result2.should be_false
    end
  end

  describe "resource cleanup" do
    it "ensures proper cleanup order" do
      resource_manager = ResourceManager.new

      resource_manager.allocate_resources
      resource_manager.all_allocated?.should be_true

      # Cleanup should happen in reverse order
      cleanup_order = resource_manager.cleanup_with_tracking

      # Should clean up in LIFO order
      cleanup_order.should eq(["resource_3", "resource_2", "resource_1"])
      resource_manager.all_allocated?.should be_false
    end

    it "handles partial cleanup failures" do
      resource_manager = ResourceManager.new
      resource_manager.allocate_resources

      # Simulate cleanup failure for middle resource
      resource_manager.set_cleanup_failure("resource_2")

      # Should clean up what it can
      resource_manager.cleanup_with_error_handling

      # Should have cleaned up resources that didn't fail
      resource_manager.allocated?("resource_1").should be_false
      resource_manager.allocated?("resource_3").should be_false
      # Failed resource might still be allocated
    end
  end
end

# Mock classes to test connection lifecycle without actual network operations
class MockConnection
  getter closed : Bool = false
  getter closing : Bool = false

  def initialize
    @closed = false
    @closing = false
  end

  def close : Nil
    return if @closed || @closing
    @closing = true
    # Simulate cleanup
    @closed = true
    @closing = false
  end

  def closed? : Bool
    @closed
  end

  def closing? : Bool
    @closing
  end

  def simulate_request : String
    raise H2O::ConnectionError.new("Connection is closed") if @closed
    "request completed"
  end
end

class FiberCoordinator
  @fibers = Array(Fiber).new
  @stop_signal = Channel(Bool).new
  @stopped = false

  def start_fibers(count : Int32) : Nil
    count.times do |_|
      @fibers << spawn do
        loop do
          select
          when @stop_signal.receive
            break
          when timeout(10.milliseconds)
            # Keep running
          end
        end
      end
    end
  end

  def start_stubborn_fiber : Nil
    @fibers << spawn do
      # This fiber ignores stop signals for testing timeout handling
      loop do
        sleep 50.milliseconds
      end
    end
  end

  def fibers_running? : Bool
    @fibers.any? { |fiber| !fiber.dead? }
  end

  def stop_fibers : Nil
    return if @stopped
    @stopped = true

    # Signal all fibers to stop
    @fibers.size.times do
      begin
        @stop_signal.send(true) unless @stop_signal.closed?
      rescue Channel::ClosedError
        # Ignore
      end
    end

    # Wait for them to finish
    @fibers.each do |_|
      # Give some time for graceful shutdown
      sleep 1.millisecond
    end
  end

  def stop_fibers_with_timeout(timeout : Time::Span) : Nil
    return if @stopped
    @stopped = true

    # Use our timeout utility
    H2O::Timeout(Bool).execute_with_handler(timeout, -> { false }) do
      stop_fibers
      true
    end
  end
end

class ChannelManager
  @channels = Array(Channel(String)).new
  @closed = false

  def initialize
    3.times { @channels << Channel(String).new(10) }
  end

  def channels_open? : Bool
    !@closed && @channels.all? { |channel| !channel.closed? }
  end

  def close_channels : Nil
    return if @closed
    @closed = true

    @channels.each do |channel|
      begin
        channel.close unless channel.closed?
      rescue
        # Ignore errors during close
      end
    end
  end

  def try_send_message(message : String) : Bool
    return false if @closed

    begin
      @channels.first.send(message)
      true
    rescue Channel::ClosedError
      false
    end
  end
end

class ResourceManager
  @allocated_resources = Hash(String, Bool).new
  @cleanup_failures = Set(String).new

  def allocate_resources : Nil
    ["resource_1", "resource_2", "resource_3"].each do |name|
      @allocated_resources[name] = true
    end
  end

  def all_allocated? : Bool
    @allocated_resources.values.all?(&.itself)
  end

  def allocated?(name : String) : Bool
    @allocated_resources[name]? || false
  end

  def set_cleanup_failure(resource : String) : Nil
    @cleanup_failures << resource
  end

  def cleanup_with_tracking : Array(String)
    cleanup_order = Array(String).new

    @allocated_resources.keys.reverse!.each do |name|
      cleanup_order << name
      @allocated_resources[name] = false
    end

    cleanup_order
  end

  def cleanup_with_error_handling : Nil
    @allocated_resources.keys.reverse!.each do |name|
      next if @cleanup_failures.includes?(name)
      @allocated_resources[name] = false
    end
  end
end
