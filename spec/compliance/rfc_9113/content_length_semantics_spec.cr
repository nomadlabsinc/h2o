require "../../spec_helper"

describe "RFC 9113 Content-Length Semantics" do
  describe "Content-Length with END_STREAM validation" do
    it "rejects non-zero Content-Length with END_STREAM and no DATA frames" do
      # RFC 9113 Section 8.1.2.6: A Content-Length header field in a HEADERS frame
      # that is followed by an END_STREAM flag and no DATA frames MUST indicate a 
      # length of 0. If it indicates a non-zero length, it's a PROTOCOL_ERROR.
      
      headers = H2O::Headers.new
      headers[":status"] = "200"
      headers["content-length"] = "10"  # Non-zero content-length
      
      expect_raises(H2O::ProtocolError, /Content-Length mismatch/) do
        H2O::HeaderListValidation.validate_content_length_end_stream(headers, true, 0)
      end
    end
    
    it "accepts zero Content-Length with END_STREAM and no DATA frames" do
      # RFC 9113: Content-Length: 0 with END_STREAM and no DATA is valid
      headers = H2O::Headers.new
      headers[":status"] = "200"  
      headers["content-length"] = "0"  # Zero content-length
      
      expect_no_error do
        H2O::HeaderListValidation.validate_content_length_end_stream(headers, true, 0)
      end
    end
    
    it "accepts non-zero Content-Length with END_STREAM and matching DATA frames" do
      # Valid: Content-Length matches actual data length
      headers = H2O::Headers.new
      headers[":status"] = "200"
      headers["content-length"] = "10"
      
      expect_no_error do
        H2O::HeaderListValidation.validate_content_length_end_stream(headers, true, 10)
      end
    end
    
    it "accepts missing Content-Length with END_STREAM" do
      # Valid: No Content-Length header is allowed
      headers = H2O::Headers.new
      headers[":status"] = "200"
      # No content-length header
      
      expect_no_error do
        H2O::HeaderListValidation.validate_content_length_end_stream(headers, true, 0)
      end
    end
    
    it "ignores Content-Length validation when END_STREAM is false" do
      # When END_STREAM is false, this validation doesn't apply
      headers = H2O::Headers.new
      headers[":status"] = "200"
      headers["content-length"] = "10"
      
      expect_no_error do
        # end_stream = false, so validation is skipped
        H2O::HeaderListValidation.validate_content_length_end_stream(headers, false, 0)
      end
    end
    
    it "validates multiple Content-Length headers" do
      # RFC 9113: Multiple Content-Length headers with different values is an error
      headers = H2O::Headers.new
      headers[":status"] = "200"
      
      # Simulate multiple content-length headers (this would normally be caught by HPACK)
      # For now, test that the validation method handles this case properly
      expect_raises(H2O::ProtocolError, /Multiple Content-Length/) do
        # This tests the validation logic for multiple content-length values
        H2O::HeaderListValidation.validate_multiple_content_length(["10", "20"])
      end
    end
    
    it "accepts multiple Content-Length headers with same value" do
      # RFC 9113: Multiple Content-Length headers with the same value is allowed
      expect_no_error do
        H2O::HeaderListValidation.validate_multiple_content_length(["10", "10", "10"])
      end
    end
  end
  
  describe "Content-Length parsing" do
    it "rejects invalid Content-Length values" do
      expect_raises(H2O::ProtocolError, /Invalid Content-Length/) do
        H2O::HeaderListValidation.parse_content_length("invalid")
      end
      
      expect_raises(H2O::ProtocolError, /Invalid Content-Length/) do
        H2O::HeaderListValidation.parse_content_length("-5")
      end
      
      expect_raises(H2O::ProtocolError, /Invalid Content-Length/) do
        H2O::HeaderListValidation.parse_content_length("10.5")
      end
    end
    
    it "accepts valid Content-Length values" do
      H2O::HeaderListValidation.parse_content_length("0").should eq(0)
      H2O::HeaderListValidation.parse_content_length("10").should eq(10)
      H2O::HeaderListValidation.parse_content_length("1234567890").should eq(1234567890)
    end
  end
end

# Helper to expect no error
private def expect_no_error(&block)
  begin
    block.call
    true.should be_true
  rescue ex
    fail "Expected no error, but got: #{ex.message}"
  end
end