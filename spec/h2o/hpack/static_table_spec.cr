require "../../spec_helper"

describe H2O::HPACK::StaticTable do
  describe ".size" do
    it "returns the correct static table size" do
      H2O::HPACK::StaticTable.size.should eq(61)
    end
  end

  describe ".[]" do
    it "returns correct entries for valid indices" do
      entry = H2O::HPACK::StaticTable[1]
      entry.should_not be_nil
      if entry
        entry.name.should eq(":authority")
        entry.value.should eq("")
      end
    end

    it "returns :method GET for index 2" do
      entry = H2O::HPACK::StaticTable[2]
      entry.should_not be_nil
      if entry
        entry.name.should eq(":method")
        entry.value.should eq("GET")
      end
    end

    it "returns nil for invalid indices" do
      H2O::HPACK::StaticTable[0].should be_nil
      H2O::HPACK::StaticTable[62].should be_nil
      H2O::HPACK::StaticTable[-1].should be_nil
    end
  end

  describe ".find_name" do
    it "finds entries by name" do
      index = H2O::HPACK::StaticTable.find_name(":method")
      index.should eq(2)
    end

    it "returns nil for non-existent names" do
      index = H2O::HPACK::StaticTable.find_name("non-existent")
      index.should be_nil
    end
  end

  describe ".find_name_value" do
    it "finds entries by name and value" do
      index = H2O::HPACK::StaticTable.find_name_value(":method", "GET")
      index.should eq(2)
    end

    it "returns nil for non-matching name/value pairs" do
      index = H2O::HPACK::StaticTable.find_name_value(":method", "INVALID")
      index.should be_nil
    end
  end
end
