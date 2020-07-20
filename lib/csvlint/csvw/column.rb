module Csvlint
  module Csvw
    class Column
      include Csvlint::ErrorCollector

      attr_reader :id, :about_url, :datatype, :default, :lang, :name, :null, :number, :ordered, :property_url, :required, :separator, :source_number, :suppress_output, :text_direction, :default_name, :titles, :value_url, :virtual, :annotations

      def initialize(number, name, id: nil, about_url: nil, datatype: {"@id" => "http://www.w3.org/2001/XMLSchema#string"}, default: "", lang: "und", null: [""], ordered: false, property_url: nil, required: false, separator: nil, source_number: nil, suppress_output: false, text_direction: :inherit, default_name: nil, titles: {}, value_url: nil, virtual: false, annotations: [], warnings: [])
        @number = number
        @name = name
        @id = id
        @about_url = about_url
        @datatype = datatype
        @default = default
        @lang = lang
        @null = null
        @ordered = ordered
        @property_url = property_url
        @required = required
        @separator = separator
        @source_number = source_number || number
        @suppress_output = suppress_output
        @text_direction = text_direction
        @default_name = default_name
        @titles = titles
        @value_url = value_url
        @virtual = virtual
        @annotations = annotations
        reset
        @warnings += warnings
      end

      def self.from_json(number, column_desc, base_url = nil, lang = "und", inherited_properties = {})
        annotations = {}
        warnings = []
        column_properties = {}
        inherited_properties = inherited_properties.clone

        column_desc.each do |property, value|
          if property == "@type"
            raise Csvlint::Csvw::MetadataError.new("columns[#{number}].@type"), "@type of column is not 'Column'" if value != "Column"
          else
            v, warning, type = Csvw::PropertyChecker.check_property(property, value, base_url, lang)
            warnings += Array(warning).map { |w| Csvlint::ErrorMessage.new(w, :metadata, nil, nil, "#{property}: #{value}", nil) } unless warning.nil? || warning.empty?
            if type == :annotation
              annotations[property] = v
            elsif type == :common || type == :column
              column_properties[property] = v
            elsif type == :inherited
              inherited_properties[property] = v
            else
              warnings << Csvlint::ErrorMessage.new(:invalid_property, :metadata, nil, nil, "column: #{property}", nil)
            end
          end
        end

        new(number, column_properties["name"],
          id: column_properties["@id"],
          datatype: inherited_properties["datatype"] || {"@id" => "http://www.w3.org/2001/XMLSchema#string"},
          lang: inherited_properties["lang"] || "und",
          null: inherited_properties["null"] || [""],
          default: inherited_properties["default"] || "",
          about_url: inherited_properties["aboutUrl"],
          property_url: inherited_properties["propertyUrl"],
          value_url: inherited_properties["valueUrl"],
          required: inherited_properties["required"] || false,
          separator: inherited_properties["separator"],
          ordered: inherited_properties["ordered"] || false,
          default_name: column_properties["titles"] && column_properties["titles"][lang] ? column_properties["titles"][lang][0] : nil,
          titles: column_properties["titles"],
          suppress_output: column_properties["suppressOutput"] || false,
          virtual: column_properties["virtual"] || false,
          annotations: annotations,
          warnings: warnings)
      end

      def validate_header(header, strict)
        reset
        if strict || @titles
          valid_headers = @titles ? @titles.map { |l, v| v if Column.languages_match(l, lang) }.flatten : []
          unless valid_headers.include? header
            if strict
              build_errors(:invalid_header, :schema, 1, @number, header, @titles)
            else
              build_warnings(:invalid_header, :schema, 1, @number, header, @titles)
            end
          end
        end
        valid?
      end

      def validate(string_value, row = nil)
        reset
        string_value ||= @default
        if null.include? string_value
          validate_required(nil, row)
          values = nil
          values
        else
          string_values = @separator.nil? ? [string_value] : string_value.split(@separator)
          values = []
          string_values.each do |s|
            invalid = false
            value, warning = DATATYPE_PARSER[@datatype["base"] || @datatype["@id"]].call(s, @datatype["format"])
            if warning.nil?
              validate_required(value, row)
              invalid = !validate_format(value, row) || invalid
              invalid = !validate_length(value, row) || invalid
              invalid = !validate_value(value, row) || invalid
              values << (invalid ? {invalid: s} : value)
            else
              build_errors(warning, :schema, row, @number, s, @datatype)
              values << {invalid: s}
            end
          end
          values = values && @separator.nil? ? values[0] : values
          values
        end
      end

      private

      class << self
        def create_date_parser(type, warning)
          lambda { |value, format|
            format = Csvlint::Csvw::DateFormat.new(nil, type) if format.nil?
            v = format.parse(value)
            return nil, warning if v.nil?
            return v, nil
          }
        end

        def create_regexp_based_parser(regexp, warning)
          lambda { |value, format|
            return nil, warning unless value&.match?(regexp)
            return value, nil
          }
        end

        def languages_match(l1, l2)
          return true if l1 == l2 || l1 == "und" || l2 == "und"
          return true if l1 =~ Regexp.new("^#{l2}-") || l2 =~ Regexp.new("^#{l1}-")
          false
        end
      end

      def validate_required(value, row)
        if @required && value.nil?
          build_errors(:required, :schema, row, number, value, {"required" => @required})
          return false
        end
        true
      end

      def validate_length(value, row)
        valid = true
        if datatype["length"] || datatype["minLength"] || datatype["maxLength"]
          length = value.length
          length = value.gsub(/==?$/, "").length * 3 / 4 if datatype["@id"] == "http://www.w3.org/2001/XMLSchema#base64Binary" || datatype["base"] == "http://www.w3.org/2001/XMLSchema#base64Binary"
          length = value.length / 2 if datatype["@id"] == "http://www.w3.org/2001/XMLSchema#hexBinary" || datatype["base"] == "http://www.w3.org/2001/XMLSchema#hexBinary"

          if datatype["minLength"] && length < datatype["minLength"]
            build_errors(:min_length, :schema, row, number, value, {"minLength" => datatype["minLength"]})
            valid = false
          end
          if datatype["maxLength"] && length > datatype["maxLength"]
            build_errors(:max_length, :schema, row, number, value, {"maxLength" => datatype["maxLength"]})
            valid = false
          end
          if datatype["length"] && length != datatype["length"]
            build_errors(:length, :schema, row, number, value, {"length" => datatype["length"]})
            valid = false
          end
        end
        valid
      end

      def validate_format(value, row)
        if datatype["format"]
          unless DATATYPE_FORMAT_VALIDATION[datatype["base"]].call(value, datatype["format"])
            build_errors(:format, :schema, row, number, value, {"format" => datatype["format"]})
            return false
          end
        end
        true
      end

      def validate_value(value, row)
        valid = true
        if datatype["minInclusive"] && ((value.is_a? Hash) ? (value[:dateTime] < datatype["minInclusive"][:dateTime]) : (value < datatype["minInclusive"]))
          build_errors(:min_inclusive, :schema, row, number, value, {"minInclusive" => datatype["minInclusive"]})
          valid = false
        end
        if datatype["maxInclusive"] && ((value.is_a? Hash) ? (value[:dateTime] > datatype["maxInclusive"][:dateTime]) : (value > datatype["maxInclusive"]))
          build_errors(:max_inclusive, :schema, row, number, value, {"maxInclusive" => datatype["maxInclusive"]})
          valid = false
        end
        if datatype["minExclusive"] && ((value.is_a? Hash) ? (value[:dateTime] <= datatype["minExclusive"][:dateTime]) : (value <= datatype["minExclusive"]))
          build_errors(:min_exclusive, :schema, row, number, value, {"minExclusive" => datatype["minExclusive"]})
          valid = false
        end
        if datatype["maxExclusive"] && ((value.is_a? Hash) ? (value[:dateTime] >= datatype["maxExclusive"][:dateTime]) : (value >= datatype["maxExclusive"]))
          build_errors(:max_exclusive, :schema, row, number, value, {"maxExclusive" => datatype["maxExclusive"]})
          valid = false
        end
        valid
      end

      REGEXP_VALIDATION = lambda { |value, format| value =~ format }

      NO_ADDITIONAL_VALIDATION = lambda { |value, format| true }

      DATATYPE_FORMAT_VALIDATION = {
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral" => REGEXP_VALIDATION,
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#HTML" => REGEXP_VALIDATION,
        "http://www.w3.org/ns/csvw#JSON" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#anyAtomicType" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#anyURI" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#base64Binary" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#boolean" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#date" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#dateTime" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#dateTimeStamp" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#decimal" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#integer" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#long" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#int" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#short" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#byte" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#nonNegativeInteger" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#positiveInteger" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#unsignedLong" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#unsignedInt" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#unsignedShort" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#unsignedByte" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#nonPositiveInteger" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#negativeInteger" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#double" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#duration" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#dayTimeDuration" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#yearMonthDuration" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#float" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#gDay" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#gMonth" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#gMonthDay" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#gYear" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#gYearMonth" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#hexBinary" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#QName" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#string" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#normalizedString" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#token" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#language" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#Name" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#NMTOKEN" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#time" => NO_ADDITIONAL_VALIDATION
      }

      TRIM_VALUE = lambda { |value, format| return value.strip, nil }
      ALL_VALUES_VALID = lambda { |value, format| return value, nil }

      NUMERIC_PARSER = lambda { |value, format, integer = false|
        format = Csvlint::Csvw::NumberFormat.new(nil, nil, ".", integer) if format.nil?
        v = format.parse(value)
        return nil, :invalid_number if v.nil?
        return v, nil
      }

      DATATYPE_PARSER = {
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral" => TRIM_VALUE,
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#HTML" => TRIM_VALUE,
        "http://www.w3.org/ns/csvw#JSON" => TRIM_VALUE,
        "http://www.w3.org/2001/XMLSchema#anyAtomicType" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#anyURI" => TRIM_VALUE,
        "http://www.w3.org/2001/XMLSchema#base64Binary" => TRIM_VALUE,
        "http://www.w3.org/2001/XMLSchema#boolean" => lambda { |value, format|
          if format.nil?
            return true, nil if ["true", "1"].include? value
            return false, nil if ["false", "0"].include? value
          else
            return true, nil if value == format[0]
            return false, nil if value == format[1]
          end
          return value, :invalid_boolean
        },
        "http://www.w3.org/2001/XMLSchema#date" =>
          create_date_parser("http://www.w3.org/2001/XMLSchema#date", :invalid_date),
        "http://www.w3.org/2001/XMLSchema#dateTime" =>
          create_date_parser("http://www.w3.org/2001/XMLSchema#dateTime", :invalid_date_time),
        "http://www.w3.org/2001/XMLSchema#dateTimeStamp" =>
          create_date_parser("http://www.w3.org/2001/XMLSchema#dateTimeStamp", :invalid_date_time_stamp),
        "http://www.w3.org/2001/XMLSchema#decimal" => lambda { |value, format|
          return nil, :invalid_decimal if /(E|e|^(NaN|INF|-INF)$)/.match?(value)
          return NUMERIC_PARSER.call(value, format)
        },
        "http://www.w3.org/2001/XMLSchema#integer" => lambda { |value, format|
          v, w = NUMERIC_PARSER.call(value, format, true)
          return v, :invalid_integer unless w.nil?
          return nil, :invalid_integer unless v.is_a? Integer
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#long" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_long unless w.nil?
          return nil, :invalid_long unless v <= 9223372036854775807 && v >= -9223372036854775808
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#int" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_int unless w.nil?
          return nil, :invalid_int unless v <= 2147483647 && v >= -2147483648
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#short" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_short unless w.nil?
          return nil, :invalid_short unless v <= 32767 && v >= -32768
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#byte" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_byte unless w.nil?
          return nil, :invalid_byte unless v <= 127 && v >= -128
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#nonNegativeInteger" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_nonNegativeInteger unless w.nil?
          return nil, :invalid_nonNegativeInteger unless v >= 0
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#positiveInteger" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_positiveInteger unless w.nil?
          return nil, :invalid_positiveInteger unless v > 0
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#unsignedLong" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#nonNegativeInteger"].call(value, format)
          return v, :invalid_unsignedLong unless w.nil?
          return nil, :invalid_unsignedLong unless v <= 18446744073709551615
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#unsignedInt" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#nonNegativeInteger"].call(value, format)
          return v, :invalid_unsignedInt unless w.nil?
          return nil, :invalid_unsignedInt unless v <= 4294967295
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#unsignedShort" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#nonNegativeInteger"].call(value, format)
          return v, :invalid_unsignedShort unless w.nil?
          return nil, :invalid_unsignedShort unless v <= 65535
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#unsignedByte" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#nonNegativeInteger"].call(value, format)
          return v, :invalid_unsignedByte unless w.nil?
          return nil, :invalid_unsignedByte unless v <= 255
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#nonPositiveInteger" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_nonPositiveInteger unless w.nil?
          return nil, :invalid_nonPositiveInteger unless v <= 0
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#negativeInteger" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_negativeInteger unless w.nil?
          return nil, :invalid_negativeInteger unless v < 0
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#double" => NUMERIC_PARSER,
        # regular expressions here taken from XML Schema datatypes spec
        "http://www.w3.org/2001/XMLSchema#duration" =>
          create_regexp_based_parser(/-?P((([0-9]+Y([0-9]+M)?([0-9]+D)?|([0-9]+M)([0-9]+D)?|([0-9]+D))(T(([0-9]+H)([0-9]+M)?([0-9]+(\.[0-9]+)?S)?|([0-9]+M)([0-9]+(\.[0-9]+)?S)?|([0-9]+(\.[0-9]+)?S)))?)|(T(([0-9]+H)([0-9]+M)?([0-9]+(\.[0-9]+)?S)?|([0-9]+M)([0-9]+(\.[0-9]+)?S)?|([0-9]+(\.[0-9]+)?S))))/, :invalid_duration),
        "http://www.w3.org/2001/XMLSchema#dayTimeDuration" =>
          create_regexp_based_parser(/-?P(([0-9]+D(T(([0-9]+H)([0-9]+M)?([0-9]+(\.[0-9]+)?S)?|([0-9]+M)([0-9]+(\.[0-9]+)?S)?|([0-9]+(\.[0-9]+)?S)))?)|(T(([0-9]+H)([0-9]+M)?([0-9]+(\.[0-9]+)?S)?|([0-9]+M)([0-9]+(\.[0-9]+)?S)?|([0-9]+(\.[0-9]+)?S))))/, :invalid_dayTimeDuration),
        "http://www.w3.org/2001/XMLSchema#yearMonthDuration" =>
          create_regexp_based_parser(/-?P([0-9]+Y([0-9]+M)?|([0-9]+M))/, :invalid_duration),
        "http://www.w3.org/2001/XMLSchema#float" => NUMERIC_PARSER,
        "http://www.w3.org/2001/XMLSchema#gDay" =>
          create_date_parser("http://www.w3.org/2001/XMLSchema#gDay", :invalid_gDay),
        "http://www.w3.org/2001/XMLSchema#gMonth" =>
          create_date_parser("http://www.w3.org/2001/XMLSchema#gMonth", :invalid_gMonth),
        "http://www.w3.org/2001/XMLSchema#gMonthDay" =>
          create_date_parser("http://www.w3.org/2001/XMLSchema#gMonthDay", :invalid_gMonthDay),
        "http://www.w3.org/2001/XMLSchema#gYear" =>
          create_date_parser("http://www.w3.org/2001/XMLSchema#gYear", :invalid_gYear),
        "http://www.w3.org/2001/XMLSchema#gYearMonth" =>
          create_date_parser("http://www.w3.org/2001/XMLSchema#gYearMonth", :invalid_gYearMonth),
        "http://www.w3.org/2001/XMLSchema#hexBinary" => TRIM_VALUE,
        "http://www.w3.org/2001/XMLSchema#QName" => TRIM_VALUE,
        "http://www.w3.org/2001/XMLSchema#string" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#normalizedString" => TRIM_VALUE,
        "http://www.w3.org/2001/XMLSchema#token" => TRIM_VALUE,
        "http://www.w3.org/2001/XMLSchema#language" => TRIM_VALUE,
        "http://www.w3.org/2001/XMLSchema#Name" => TRIM_VALUE,
        "http://www.w3.org/2001/XMLSchema#NMTOKEN" => TRIM_VALUE,
        "http://www.w3.org/2001/XMLSchema#time" =>
          create_date_parser("http://www.w3.org/2001/XMLSchema#time", :invalid_time)
      }
    end
  end
end
