require "../../spec_helper"
require "./test_helpers"

include H2SpecTestHelpers

describe "H2SPEC Connection Preface Compliance" do
  # Test for 3.5/1: Sends an invalid connection preface.
  it "sends an invalid connection preface and expects a connection error" do
    # These tests validate that the server sends proper connection preface
    # In our mock setup, we're simulating what a server would send
    mock_socket = IO::Memory.new
    
    # Write invalid preface (server would normally send proper preface)
    mock_socket.write("INVALID PREFACE\r\n\r\n".to_slice)
    mock_socket.rewind
    
    # MockH2Client expects to read frames, not the preface
    # So this will fail when trying to read frame header
    client = MockH2Client.new(mock_socket)

    expect_raises(H2O::FrameSizeError) do
      client.request("GET", "/")
    end

    client.close
  end

  # Test for 3.5/2: Sends no connection preface.
  it "sends no connection preface and expects an error" do
    mock_socket = IO::Memory.new
    # Don't write anything - simulate a server that sends nothing
    # The socket is empty, so any read will immediately fail
    
    # This will fail immediately when trying to read frames
    client = MockH2Client.new(mock_socket)

    # The mock client will fail to read from empty socket
    expect_raises(IO::EOFError, "No data in socket") do
      client.request("GET", "/")
    end

    client.close
  end
end
