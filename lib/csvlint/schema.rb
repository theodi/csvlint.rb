module Csvlint
  class Schema
    include Csvlint::ErrorCollector

    attr_reader :uri, :fields, :title, :description

    def initialize(uri, fields = [], title = nil, description = nil)
      @uri = uri
      @fields = fields
      @title = title
      @description = description
      reset
    end

    class << self
      extend Gem::Deprecate

      def from_json_table(uri, json)
        fields = []
        json["fields"]&.each do |field_desc|
          fields << Csvlint::Field.new(field_desc["name"], field_desc["constraints"],
            field_desc["title"], field_desc["description"])
        end
        Schema.new(uri, fields, json["title"], json["description"])
      end

      def from_csvw_metadata(uri, json)
        Csvlint::Csvw::TableGroup.from_json(uri, json)
      end

      # Deprecated method signature
      def load_from_json(uri, output_errors = true)
        load_from_uri(uri, output_errors)
      end
      deprecate :load_from_json, :load_from_uri, 2018, 1

      def load_from_uri(uri, output_errors = true)
        load_from_string(uri, open(uri).read, output_errors)
      rescue OpenURI::HTTPError, Errno::ENOENT => e
        raise e
      end

      def load_from_string(uri, string, output_errors = true)
        json = JSON.parse(string)
        if json["@context"]
          uri = "file:#{File.expand_path(uri)}" unless /^http(s)?/.match?(uri.to_s)
          Schema.from_csvw_metadata(uri, json)
        else
          Schema.from_json_table(uri, json)
        end
      rescue TypeError => e
        # NO IDEA what this was even trying to do - SP 20160526
      rescue Csvlint::Csvw::MetadataError => e
        raise e
      rescue => e
        if output_errors === true
          warn e.class
          warn e.message
          warn e.backtrace
        end
        Schema.new(nil, [], "malformed", "malformed")
      end
    end

    def validate_header(header, source_url = nil, validate = true)
      reset

      found_header = header.to_csv(row_sep: "")
      expected_header = @fields.map { |f| f.name }.to_csv(row_sep: "")
      if found_header != expected_header
        build_warnings(:malformed_header, :schema, 1, nil, found_header, "expectedHeader" => expected_header)
      end
      valid?
    end

    def validate_row(values, row = nil, all_errors = [], source_url = nil, validate = true)
      reset
      if values.length < fields.length
        fields[values.size..-1].each_with_index do |field, i|
          build_warnings(:missing_column, :schema, row, values.size + i + 1)
        end
      end
      if values.length > fields.length
        values[fields.size..-1].each_with_index do |data_column, i|
          build_warnings(:extra_column, :schema, row, fields.size + i + 1)
        end
      end

      fields.each_with_index do |field, i|
        value = values[i] || ""
        result = field.validate_column(value, row, i + 1, all_errors)
        @errors += fields[i].errors
        @warnings += fields[i].warnings
      end

      valid?
    end
  end
end
