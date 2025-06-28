require "../spec_helper"
require "process"

# Debug compliance test to understand SSL/TLS issues

describe "H2O HTTP/2 Compliance Debug" do
  it "debugs the test harness connection" do
    port = 45000
    container_name = "h2-debug-test"
    
    # Kill any existing container
    Process.run("docker", ["kill", container_name], output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)
    Process.run("docker", ["rm", container_name], output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)
    
    puts "\n🔍 Starting test harness for debugging..."
    
    # Start test harness with explicit port binding
    docker_cmd = [
      "docker", "run", "--rm", "-d",
      "--name", container_name,
      "-p", "#{port}:8080",
      "h2-client-test-harness",
      "--test=6.5.3/2"
    ]
    
    docker_result = Process.run(docker_cmd[0], docker_cmd[1..], output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)
    output = docker_result.output.read
    error_output = docker_result.error.read
    
    unless docker_result.success?
      puts "Failed to start harness:"
      puts "Output: #{output}"
      puts "Error: #{error_output}"
      false.should be_true
    end
    
    puts "Started container: #{output.strip}"
    
    # Give it time to start
    sleep 2.seconds
    
    # Check if container is running
    ps_result = Process.run("docker", ["ps", "--filter", "name=#{container_name}"], output: Process::Redirect::Pipe)
    puts "Container status:\n#{ps_result.output.read}"
    
    # Try to get logs
    logs_result = Process.run("docker", ["logs", container_name], output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)
    puts "\nContainer logs:\n#{logs_result.output.read}#{logs_result.error.read}"
    
    # Test different connection approaches
    puts "\n🧪 Testing connection methods..."
    
    # Test 1: HTTP/2 with TLS
    begin
      puts "\n1. Testing HTTPS connection..."
      client = H2O::H2::Client.new("localhost", port,
                                   connect_timeout: 3.seconds,
                                   request_timeout: 3.seconds,
                                   use_tls: true,
                                   verify_ssl: false)
      
      headers = H2O::Headers{"host" => "localhost:#{port}"}
      response = client.request("GET", "/", headers)
      puts "   ✅ Success! Status: #{response.status}"
    rescue ex
      puts "   ❌ Failed: #{ex.class.name} - #{ex.message}"
    end
    
    # Test 2: Check if we can connect with curl
    puts "\n2. Testing with curl..."
    curl_result = Process.run("bash", ["-c", "curl -k --http2-prior-knowledge https://localhost:#{port}/ -v"], 
                              output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)
    puts "   Curl output: #{curl_result.error.read[0..500]}..."
    
    # Cleanup
    Process.run("docker", ["kill", container_name], output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)
    
    true.should be_true
  end
end