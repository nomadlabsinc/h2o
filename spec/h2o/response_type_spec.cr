require "../spec_helper"

describe "Response Type Safety" do
  describe "Response as class (reference type)" do
    it "properly updates status when passed to methods" do
      response = H2O::Response.new(0)

      # Simulate what happens in stream processing
      update_response_status(response, 200)

      response.status.should eq(200)
    end

    it "properly updates headers when passed to methods" do
      response = H2O::Response.new(200)

      # Simulate what happens in header processing
      add_response_header(response, "content-type", "application/json")

      response.headers["content-type"].should eq("application/json")
    end

    it "properly updates body when passed to methods" do
      response = H2O::Response.new(200)

      # Simulate what happens in data frame processing
      append_response_body(response, "Hello, ")
      append_response_body(response, "World!")

      response.body.should eq("Hello, World!")
    end

    it "maintains reference integrity across multiple updates" do
      response = H2O::Response.new(0)

      # Simulate complex processing pipeline
      update_response_status(response, 200)
      add_response_header(response, "server", "h2o")
      add_response_header(response, "content-length", "13")
      append_response_body(response, "Hello, World!")

      # All changes should be preserved
      response.status.should eq(200)
      response.headers["server"].should eq("h2o")
      response.headers["content-length"].should eq("13")
      response.body.should eq("Hello, World!")
    end

    it "works correctly when stored in variables and passed around" do
      response = H2O::Response.new(0)
      original_response = response

      # Modify through a different reference
      update_response_status(original_response, 404)

      # Both references should see the change
      response.status.should eq(404)
      original_response.status.should eq(404)

      # They should be the same object
      response.should be(original_response)
    end
  end

  # These would fail if Response was incorrectly defined as struct
  describe "preventing struct-related bugs" do
    it "does not lose updates when response is reassigned" do
      response = H2O::Response.new(0)
      response_ref = response

      # This pattern was problematic with struct Response
      response = process_response(response)

      # Both should have the updated status
      response.status.should eq(200)
      response_ref.status.should eq(200)
    end

    it "preserves changes across method boundaries" do
      responses = [H2O::Response.new(0), H2O::Response.new(0)]

      responses.each_with_index do |resp, i|
        update_response_status(resp, 200 + i)
      end

      responses[0].status.should eq(200)
      responses[1].status.should eq(201)
    end

    it "works correctly in arrays and collections" do
      responses = Array(H2O::Response).new
      3.times { |i| responses << H2O::Response.new(i) }

      # Modify through array access
      responses.each_with_index do |resp, i|
        update_response_status(resp, 200 + i)
        add_response_header(resp, "x-index", i.to_s)
      end

      # Check all were modified correctly
      responses[0].status.should eq(200)
      responses[0].headers["x-index"].should eq("0")

      responses[1].status.should eq(201)
      responses[1].headers["x-index"].should eq("1")

      responses[2].status.should eq(202)
      responses[2].headers["x-index"].should eq("2")
    end
  end
end

# Helper methods that simulate how Response objects are processed
private def update_response_status(response : H2O::Response, status : Int32) : Nil
  response.status = status
end

private def add_response_header(response : H2O::Response, name : String, value : String) : Nil
  response.headers[name] = value
end

private def append_response_body(response : H2O::Response, content : String) : Nil
  response.body = String.build do |str|
    str << response.body
    str << content
  end
end

private def process_response(response : H2O::Response) : H2O::Response
  response.status = 200
  response
end
