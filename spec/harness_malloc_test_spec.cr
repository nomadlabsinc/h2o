require "./spec_helper"
require "process"

describe "Harness Malloc Test" do
  it "runs single harness process and connects" do
    harness_process = Process.new(
      "/usr/local/bin/harness",
      ["--port", "20000", "--test", "3.5/1"],
      output: Process::Redirect::Pipe,
      error: Process::Redirect::Pipe
    )
    
    sleep 0.5.seconds
    
    begin
      client = H2O::H2::Client.new("localhost", 20000, verify_ssl: false)
      response = client.request("GET", "/", {"host" => "localhost:20000"})
      puts "Got response: #{response.status}"
      client.close
    rescue ex
      puts "Client error: #{ex.class} - #{ex.message}"
    ensure
      harness_process.terminate
      harness_process.wait
    end
  end

  it "runs two harness processes sequentially" do
    2.times do |i|
      puts "Starting harness #{i}"
      
      harness_process = Process.new(
        "/usr/local/bin/harness",
        ["--port", "#{20000 + i}", "--test", "3.5/1"],
        output: Process::Redirect::Pipe,
        error: Process::Redirect::Pipe
      )
      
      sleep 0.5.seconds
      
      begin
        client = H2O::H2::Client.new("localhost", 20000 + i, verify_ssl: false)
        response = client.request("GET", "/", {"host" => "localhost:#{20000 + i}"})
        puts "Harness #{i} - Got response: #{response.status}"
        client.close
      rescue ex
        puts "Harness #{i} - Client error: #{ex.class} - #{ex.message}"
      ensure
        harness_process.terminate
        harness_process.wait
      end
      
      # Delay between tests
      sleep 0.2.seconds
    end
  end
end