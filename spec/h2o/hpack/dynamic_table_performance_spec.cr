require "../../spec_helper"

describe "HPACK Dynamic Table Performance" do
  describe "NameValueKey optimization" do
    it "correctly handles name-value lookups without string allocation" do
      table = H2O::HPACK::DynamicTable.new

      table.add("content-type", "application/json")
      table.add("server", "h2o")
      table.add("content-length", "42")

      # Test name lookup
      index = table.find_name("content-type")
      index.should_not be_nil

      # Test name-value lookup with optimized key
      index = table.find_name_value("content-type", "application/json")
      index.should_not be_nil

      # Test non-existent name-value pair
      index = table.find_name_value("content-type", "text/html")
      index.should be_nil
    end

    it "maintains correct indexing after evictions" do
      table = H2O::HPACK::DynamicTable.new(100) # Small size to force evictions

      # Add entries that will exceed the table size
      table.add("large-header-name-1", "large-header-value-that-takes-up-space-1")
      table.add("large-header-name-2", "large-header-value-that-takes-up-space-2")
      table.add("content-type", "application/json")

      # Verify the most recent entry is still findable
      index = table.find_name_value("content-type", "application/json")
      index.should_not be_nil
    end

    it "handles multiple entries with same name correctly" do
      table = H2O::HPACK::DynamicTable.new

      table.add("x-custom", "value1")
      table.add("y-different", "other-value") # Add different entry to create different indices
      table.add("x-custom", "value2")

      # Should find the name (first occurrence for names)
      name_index = table.find_name("x-custom")
      name_index.should_not be_nil

      # Should find specific name-value pairs
      index1 = table.find_name_value("x-custom", "value1")
      index2 = table.find_name_value("x-custom", "value2")
      other_index = table.find_name_value("y-different", "other-value")

      index1.should_not be_nil
      index2.should_not be_nil
      other_index.should_not be_nil

      # Different name-value pairs should have different indices
      index1.should_not eq(index2)
      index1.should_not eq(other_index)
      index2.should_not eq(other_index)
    end
  end
end
