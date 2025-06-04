require "./spec_helper"

describe H2O do
  it "has a version" do
    H2O::VERSION.should_not be_empty
  end

  it "defines Headers type alias" do
    headers = H2O::Headers.new
    headers["test"] = "value"
    headers["test"].should eq("value")
  end

  it "defines StreamId type alias" do
    stream_id : H2O::StreamId = 1_u32
    stream_id.should eq(1_u32)
  end
end
