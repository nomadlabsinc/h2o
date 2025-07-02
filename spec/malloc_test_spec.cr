require "./spec_helper"

describe "Malloc Test" do
  it "runs multiple H2O clients sequentially without malloc errors" do
    10.times do |i|
      puts "Creating client #{i}"
      
      begin
        client = H2O::H2::Client.new("httpbin.org", 443)
        response = client.request("GET", "/")
        puts "Client #{i} got response: #{response.status}"
        client.close
      rescue ex
        puts "Client #{i} failed: #{ex.message}"
      end
      
      # Small delay between clients
      sleep 0.1.seconds
    end
  end

  it "creates multiple clients to same host rapidly" do
    5.times do |i|
      puts "Creating rapid client #{i}"
      
      client = H2O::H2::Client.new("httpbin.org", 443)
      client.close
    end
  end
end