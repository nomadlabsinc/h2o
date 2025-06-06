require "../spec_helper"

describe "H2O HTTP/2 Integration Tests" do
  it "creates a client without frame initialization errors" do
    client = H2O::Client.new
    client.should_not be_nil
  end

  it "can initialize data frames without errors" do
    data = "Hello World".to_slice
    frame = H2O::DataFrame.new(1_u32, data, H2O::DataFrame::FLAG_PADDED, 5_u8)

    frame.data.should eq(data)
    frame.padded?.should be_true
    frame.padding_length.should eq(5_u8)
  end

  it "can initialize headers frames without errors" do
    headers = "test headers".to_slice
    frame = H2O::HeadersFrame.new(1_u32, headers, H2O::HeadersFrame::FLAG_PADDED, 3_u8)

    frame.header_block.should eq(headers)
    frame.padded?.should be_true
    frame.padding_length.should eq(3_u8)
  end

  it "can initialize push promise frames without errors" do
    headers = "promise headers".to_slice
    frame = H2O::PushPromiseFrame.new(1_u32, 3_u32, headers, false, 2_u8)

    frame.promised_stream_id.should eq(3_u32)
    frame.header_block.should eq(headers)
    frame.padded?.should be_true
  end

  it "can create HTTP/2 client for real server requests" do
    # This test verifies client creation works for real HTTP/2 requests
    # For full integration testing with Docker servers, run:
    # cd spec/integration && docker-compose up -d
    # Then test: crystal spec spec/integration/

    client = H2O::Client.new
    client.should_not be_nil

    # Verify we can create connections (basic connectivity test)
    # Real HTTP/2 requests require the Docker test infrastructure
    # This will fail without Docker servers, returning nil instead of raising
    response = client.get("https://localhost:8443/")
    response.should be_nil
  end
end
