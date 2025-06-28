require "../spec_helper"
require "./h2_compliance_spec"

# Quick test to verify the compliance harness is working
describe "H2O Quick Compliance Test" do
  it "tests a few key cases to verify setup" do
    test_cases = [
      H2Compliance::TestCase.new("6.5.3/2", "SETTINGS ACK expected", H2Compliance::ExpectedBehavior::Success),
      H2Compliance::TestCase.new("4.2/2", "DATA frame exceeds max size", H2Compliance::ExpectedBehavior::ConnectionError, H2O::ErrorCode::FrameSizeError),
      H2Compliance::TestCase.new("6.5/1", "SETTINGS with ACK and payload", H2Compliance::ExpectedBehavior::ConnectionError, H2O::ErrorCode::FrameSizeError),
    ]
    
    puts "\n🔍 Running quick compliance test..."
    
    test_cases.each do |test_case|
      print "Testing #{test_case.id}: #{test_case.description}... "
      result = H2Compliance::ComplianceRunner.run_single_test(test_case)
      
      if result.passed
        puts "✅ PASS"
      else
        puts "❌ FAIL (expected #{test_case.expected}, got #{result.actual_behavior})"
      end
    end
  end
end