# Parallel test runner for maximum concurrency
require "spec"
require "fiber"
require "channel"
require "../src/h2o"

# Global shared resources for maximum efficiency
class TestResourcePool
  @@clients = Channel(H2O::Client).new(20) # Pool of 20 clients
  @@initialized = false

  def self.initialize_pool
    return if @@initialized

    # Pre-create clients in parallel
    channels = Array(Channel(Nil)).new(20)
    20.times do |_|
      channel = Channel(Nil).new(1)
      channels << channel

      spawn do
        client = H2O::Client.new(timeout: 500.milliseconds)
        @@clients.send(client)
        channel.send(nil)
      end
    end

    # Wait for all clients to be created
    channels.each(&.receive)
    @@initialized = true
  end

  def self.get_client : H2O::Client
    initialize_pool
    @@clients.receive
  end

  def self.return_client(client : H2O::Client)
    @@clients.send(client)
  end

  def self.close_all
    return unless @@initialized

    # Close all clients
    clients = Array(H2O::Client).new
    20.times do
      begin
        client = @@clients.receive?
        clients << client if client
      rescue Channel::ClosedError
        break
      end
    end

    clients.each(&.close)
    @@clients.close
  end
end

# Parallel test execution framework
class ParallelTestRunner
  def self.run_parallel_tests(test_groups : Array(Proc(Nil)))
    channels = Array(Channel(Bool)).new(test_groups.size)

    test_groups.each do |test_group|
      channel = Channel(Bool).new(1)
      channels << channel

      spawn do
        begin
          test_group.call
          channel.send(true)
        rescue ex
          puts "Test group failed: #{ex.message}"
          channel.send(false)
        end
      end
    end

    # Wait for all test groups to complete
    results = channels.map(&.receive)
    successful_count = results.count(&.itself)

    puts "Parallel execution: #{successful_count}/#{test_groups.size} test groups passed"
  end

  # Execute multiple specs in parallel fibers
  def self.parallel_spec_execution(spec_files : Array(String))
    channels = Array(Channel(Bool)).new(spec_files.size)

    spec_files.each do |spec_file|
      channel = Channel(Bool).new(1)
      channels << channel

      spawn do
        begin
          # This would ideally run each spec file in isolation
          # For now, we'll simulate with individual test execution
          success = execute_spec_file(spec_file)
          channel.send(success)
        rescue
          channel.send(false)
        end
      end
    end

    results = channels.map(&.receive)
    successful_count = results.count(&.itself)

    {successful_count, spec_files.size}
  end

  private def self.execute_spec_file(spec_file : String) : Bool
    # Simulate spec file execution
    # In practice, this would require restructuring Crystal's spec runner
    true
  end
end

# High-performance test helpers with resource pooling
module FastTestHelpers
  extend self

  def parallel_http_requests(urls : Array(String), count : Int32 = urls.size)
    channels = Array(Channel(H2O::Response?)).new(count)

    count.times do |i|
      channel = Channel(H2O::Response?).new(1)
      channels << channel

      spawn do
        client = TestResourcePool.get_client
        begin
          url = urls[i % urls.size]
          response = client.get(url)
          channel.send(response)
        rescue
          channel.send(nil)
        ensure
          TestResourcePool.return_client(client)
        end
      end
    end

    channels.map(&.receive)
  end

  def concurrent_client_tests(test_count : Int32, &block : H2O::Client, Int32 -> Bool)
    channels = Array(Channel(Bool)).new(test_count)

    test_count.times do |i|
      channel = Channel(Bool).new(1)
      channels << channel

      spawn do
        client = TestResourcePool.get_client
        begin
          result = block.call(client, i)
          channel.send(result)
        rescue
          channel.send(false)
        ensure
          TestResourcePool.return_client(client)
        end
      end
    end

    results = channels.map(&.receive)
    successful_count = results.count(&.itself)

    {successful_count, test_count}
  end

  def batch_validation_tests(validations : Array(Proc(Bool)))
    channels = Array(Channel(Bool)).new(validations.size)

    validations.each do |validation|
      channel = Channel(Bool).new(1)
      channels << channel

      spawn do
        begin
          result = validation.call
          channel.send(result)
        rescue
          channel.send(false)
        end
      end
    end

    results = channels.map(&.receive)
    successful_count = results.count(&.itself)

    {successful_count, validations.size}
  end
end

# Cleanup handler
at_exit do
  TestResourcePool.close_all
end
