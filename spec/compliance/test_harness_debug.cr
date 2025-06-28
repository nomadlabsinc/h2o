require "../spec_helper"
require "process"

# Simple test to debug harness connectivity

port = 45000
container_name = "h2-debug-test"

# Kill any existing container
`docker kill #{container_name} 2>/dev/null`
`docker rm #{container_name} 2>/dev/null`

puts "🔍 Starting test harness..."

# Start test harness
container_id = `docker run --rm -d --name #{container_name} -p #{port}:8080 h2-client-test-harness --test=6.5.3/2`.strip
puts "Started container: #{container_id}"

sleep 2

# Check container status
puts "\nContainer status:"
puts `docker ps --filter name=#{container_name}`

# Get logs
puts "\nContainer logs:"
puts `docker logs #{container_name} 2>&1`

# Test HTTPS connection
puts "\n🧪 Testing HTTPS connection..."
begin
  client = H2O::H2::Client.new("localhost", port,
                               connect_timeout: 3.seconds,
                               request_timeout: 3.seconds,
                               use_tls: true,
                               verify_ssl: false)
  
  headers = H2O::Headers{"host" => "localhost:#{port}"}
  response = client.request("GET", "/", headers)
  puts "✅ Success! Status: #{response.status}"
rescue ex
  puts "❌ Failed: #{ex.class.name} - #{ex.message}"
  if ex.responds_to?(:cause) && ex.cause
    puts "   Cause: #{ex.cause}"
  end
end

# Test with curl
puts "\n🧪 Testing with curl..."
puts `curl -k --http2-prior-knowledge https://localhost:#{port}/ -v 2>&1 | head -20`

# Cleanup
`docker kill #{container_name}`

puts "\n✅ Debug complete"