require "spec_helper"

describe Csvlint::Csvw::Column do
  it "shouldn't generate errors for string values" do
    column = Csvlint::Csvw::Column.new(1, "foo")
    value = column.validate("bar", 2)
    expect(value).to eq("bar")
  end

  it "should generate errors for string values that aren't long enough" do
    column = Csvlint::Csvw::Column.new(1, "foo", datatype: {"base" => "http://www.w3.org/2001/XMLSchema#string", "minLength" => 4})
    value = column.validate("bar", 2)
    expect(value).to eq({invalid: "bar"})
    expect(column.errors.length).to eq(1)
  end

  it "shouldn't generate errors for string values that are long enough" do
    column = Csvlint::Csvw::Column.new(1, "foo", datatype: {"base" => "http://www.w3.org/2001/XMLSchema#string", "minLength" => 4})
    value = column.validate("barn", 2)
    expect(value).to eq("barn")
    expect(column.errors.length).to eq(0)
  end

  context "when parsing CSVW column descriptions" do
    it "should provide appropriate default values" do
      @desc = <<-EOL
      {
        "name": "countryCode"
      }
      EOL
      json = JSON.parse(@desc)
      column = Csvlint::Csvw::Column.from_json(1, json)

      expect(column).to be_a(Csvlint::Csvw::Column)
      expect(column.number).to eq(1)
      expect(column.name).to eq("countryCode")
      expect(column.about_url).to eq(nil)
      expect(column.datatype).to eq({"@id" => "http://www.w3.org/2001/XMLSchema#string"})
      expect(column.default).to eq("")
      expect(column.lang).to eq("und")
      expect(column.null).to eq([""])
      expect(column.ordered).to eq(false)
      expect(column.property_url).to eq(nil)
      expect(column.required).to eq(false)
      expect(column.separator).to eq(nil)
      expect(column.source_number).to eq(1)
      expect(column.suppress_output).to eq(false)
      expect(column.text_direction).to eq(:inherit)
      expect(column.titles).to eq(nil)
      expect(column.value_url).to eq(nil)
      expect(column.virtual).to eq(false)
      expect(column.annotations).to eql({})
    end

    it "should override default values" do
      @desc = <<-EOL
      {
        "name": "countryCode",
        "titles": "countryCode",
        "propertyUrl": "http://www.geonames.org/ontology{#_name}"
      }
      EOL
      json = JSON.parse(@desc)
      column = Csvlint::Csvw::Column.from_json(2, json)

      expect(column).to be_a(Csvlint::Csvw::Column)
      expect(column.number).to eq(2)
      expect(column.name).to eq("countryCode")
      expect(column.about_url).to eq(nil)
      expect(column.datatype).to eq({"@id" => "http://www.w3.org/2001/XMLSchema#string"})
      expect(column.default).to eq("")
      expect(column.lang).to eq("und")
      expect(column.null).to eq([""])
      expect(column.ordered).to eq(false)
      expect(column.property_url).to eq("http://www.geonames.org/ontology{#_name}")
      expect(column.required).to eq(false)
      expect(column.separator).to eq(nil)
      expect(column.source_number).to eq(2)
      expect(column.suppress_output).to eq(false)
      expect(column.text_direction).to eq(:inherit)
      expect(column.titles).to eql({"und" => ["countryCode"]})
      expect(column.value_url).to eq(nil)
      expect(column.virtual).to eq(false)
      expect(column.annotations).to eql({})
    end

    it "should include the datatype" do
      @desc = <<-EOL
      { "name": "Id", "required": true, "datatype": { "base": "string", "minLength": 3 } }
      EOL
      json = JSON.parse(@desc)
      column = Csvlint::Csvw::Column.from_json(1, json)
      expect(column.name).to eq("Id")
      expect(column.required).to eq(true)
      expect(column.datatype).to eql({"base" => "http://www.w3.org/2001/XMLSchema#string", "minLength" => 3})
    end

    it "should generate warnings for invalid null values" do
      @desc = <<-EOL
      {
        "name": "countryCode",
        "null": true
      }
      EOL
      json = JSON.parse(@desc)
      column = Csvlint::Csvw::Column.from_json(1, json)
      expect(column.warnings.length).to eq(1)
      expect(column.warnings[0].type).to eq(:invalid_value)
    end
  end
end
