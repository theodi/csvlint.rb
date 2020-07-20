require "spec_helper"

describe Csvlint::Csvw::Table do
  context "when parsing CSVW table metadata" do
    before(:each) do
      @metadata = <<~EOL
        {
          "@context": "http://www.w3.org/ns/csvw",
          "tables": [{
            "url": "countries.csv",
            "tableSchema": {
              "columns": [{
                "name": "countryCode",
                "titles": "countryCode",
                "datatype": "string",
                "propertyUrl": "http://www.geonames.org/ontology{#_name}"
              }, {
                "name": "latitude",
                "titles": "latitude",
                "datatype": "number"
              }, {
                "name": "longitude",
                "titles": "longitude",
                "datatype": "number"
              }, {
                "name": "name",
                "titles": "name",
                "datatype": "string"
              }],
              "aboutUrl": "http://example.org/countries.csv{#countryCode}",
              "propertyUrl": "http://schema.org/{_name}",
              "primaryKey": "countryCode"
            }
          }, {
            "url": "country_slice.csv",
            "tableSchema": {
              "columns": [{
                "name": "countryRef",
                "titles": "countryRef",
                "valueUrl": "http://example.org/countries.csv{#countryRef}"
              }, {
                "name": "year",
                "titles": "year",
                "datatype": "gYear"
              }, {
                "name": "population",
                "titles": "population",
                "datatype": "integer"
              }],
              "foreignKeys": [{
                "columnReference": "countryRef",
                "reference": {
                  "resource": "countries.csv",
                  "columnReference": "countryCode"
                }
              }]
            }
          }]
        }
      EOL
      stub_request(:get, "http://w3c.github.io/csvw/tests/countries.json").to_return(status: 200, body: @metadata)
      @countries = <<~EOL
        countryCode,latitude,longitude,name
        AD,42.546245,1.601554,Andorra
        AE,23.424076,53.847818,"United Arab Emirates"
        AF,33.93911,67.709953,Afghanistan
      EOL
      stub_request(:get, "http://w3c.github.io/csvw/tests/countries.csv").to_return(status: 200, body: @countries)
      @country_slice = <<~EOL
        countryRef,year,population
        AF,1960,9616353
        AF,1961,9799379
        AF,1962,9989846
      EOL
      stub_request(:get, "http://w3c.github.io/csvw/tests/country_slice.csv").to_return(status: 200, body: @country_slice)
    end

    it "should create a table from pre-parsed CSVW metadata" do
      json = JSON.parse(@metadata)
      table = Csvlint::Csvw::Table.from_json(json["tables"][0], "http://w3c.github.io/csvw/tests/countries.json")

      expect(table).to be_a(Csvlint::Csvw::Table)
      expect(table.url.to_s).to eq("http://w3c.github.io/csvw/tests/countries.csv")
      expect(table.columns.length).to eq(4)
      expect(table.columns[0]).to be_a(Csvlint::Csvw::Column)
    end
  end
end
