module Csvlint
  module Csvw
    class PropertyChecker
      class << self
        def check_property(property, value, base_url, lang)
          if PROPERTIES.include? property
            PROPERTIES[property].call(value, base_url, lang)
          elsif property =~ /^([a-z]+):/ && NAMESPACES.include?(property.split(":")[0])
            value, warnings = check_common_property_value(value, base_url, lang)
            [value, warnings, :annotation]
          else
            # property name must be an absolute URI
            begin
              return value, :invalid_property, nil if URI(property).scheme.nil?
              value, warnings = check_common_property_value(value, base_url, lang)
              [value, warnings, :annotation]
            rescue
              [value, :invalid_property, nil]
            end
          end
        end

        private

        def check_common_property_value(value, base_url, lang)
          case value
          when Hash
            value = value.clone
            warnings = []
            value.each do |p, v|
              case p
              when "@context"
                raise Csvlint::Csvw::MetadataError.new(p), "common property has @context property"
              when "@list"
                raise Csvlint::Csvw::MetadataError.new(p), "common property has @list property"
              when "@set"
                raise Csvlint::Csvw::MetadataError.new(p), "common property has @set property"
              when "@type"
                if value["@value"] && BUILT_IN_DATATYPES.include?(v)
                elsif !value["@value"] && BUILT_IN_TYPES.include?(v)
                elsif v =~ /^([a-z]+):/ && NAMESPACES.include?(v.split(":")[0])
                else
                  # must be an absolute URI
                  begin
                    raise Csvlint::Csvw::MetadataError.new, "common property has invalid @type (#{v})" if URI(v).scheme.nil?
                  rescue
                    raise Csvlint::Csvw::MetadataError.new, "common property has invalid @type (#{v})"
                  end
                end
              when "@id"
                unless base_url.nil?
                  begin
                    v = URI.join(base_url, v)
                  rescue
                    raise Csvlint::Csvw::MetadataError.new, "common property has invalid @id (#{v})"
                  end
                end
              when "@value"
                raise Csvlint::Csvw::MetadataError.new, "common property with @value has both @language and @type" if value["@type"] && value["@language"]
                raise Csvlint::Csvw::MetadataError.new, "common property with @value has properties other than @language or @type" unless value.except("@type").except("@language").except("@value").empty?
              when "@language"
                raise Csvlint::Csvw::MetadataError.new, "common property with @language lacks a @value" unless value["@value"]
                raise Csvlint::Csvw::MetadataError.new, "common property has invalid @language (#{v})" unless v =~ BCP47_LANGUAGE_REGEXP || v.nil?
              else
                if p[0] == "@"
                  raise Csvlint::Csvw::MetadataError.new, "common property has property other than @id, @type, @value or @language beginning with @ (#{p})"
                else
                  v, w = check_common_property_value(v, base_url, lang)
                  warnings += Array(w)
                end
              end
              value[p] = v
            end
            [value, warnings]
          when String
            if lang == "und"
              [value, nil]
            else
              [{"@value" => value, "@language" => lang}, nil]
            end
          when Array
            values = []
            warnings = []
            value.each do |v|
              v, w = check_common_property_value(v, base_url, lang)
              warnings += Array(w)
              values << v
            end
            [values, warnings]
          else
            [value, nil]
          end
        end

        def convert_value_facet(value, property, datatype)
          if value[property]
            if DATE_FORMAT_DATATYPES.include?(datatype)
              format = Csvlint::Csvw::DateFormat.new(nil, datatype)
              v = format.parse(value[property])
              if v.nil?
                value.delete(property)
                return [":invalid_#{property}".to_sym]
              else
                value[property] = v
                return []
              end
            elsif NUMERIC_FORMAT_DATATYPES.include?(datatype)
              return []
            else
              raise Csvlint::Csvw::MetadataError.new("datatype.#{property}"), "#{property} is only allowed for numeric, date/time and duration types"
            end
          end
          []
        end

        def array_property(type)
          lambda { |value, base_url, lang|
            return value, nil, type if value.instance_of? Array
            return false, :invalid_value, type
          }
        end

        def boolean_property(type)
          lambda { |value, base_url, lang|
            return value, nil, type if value == true || value == false
            return false, :invalid_value, type
          }
        end

        def string_property(type)
          lambda { |value, base_url, lang|
            return value, nil, type if value.instance_of? String
            return "", :invalid_value, type
          }
        end

        def uri_template_property(type)
          lambda { |value, base_url, lang|
            return URITemplate.new(value), nil, type if value.instance_of? String
            return URITemplate.new(""), :invalid_value, type
          }
        end

        def numeric_property(type)
          lambda { |value, base_url, lang|
            return value, nil, type if value.is_a?(Integer) && value >= 0
            return nil, :invalid_value, type
          }
        end

        def link_property(type)
          lambda { |value, base_url, lang|
            raise Csvlint::Csvw::MetadataError.new, "URL #{value} starts with _:" if /^_:/.match?(value.to_s)
            return (base_url.nil? ? URI(value) : URI.join(base_url, value)), nil, type if value.instance_of? String
            return base_url, :invalid_value, type
          }
        end

        def language_property(type)
          lambda { |value, base_url, lang|
            return value, nil, type if BCP47_REGEXP.match?(value)
            return nil, :invalid_value, type
          }
        end

        def natural_language_property(type)
          lambda { |value, base_url, lang|
            warnings = []
            if value.instance_of? String
              return {lang => [value]}, nil, type
            elsif value.instance_of? Array
              valid_titles = []
              value.each do |title|
                if title.instance_of? String
                  valid_titles << title
                else
                  warnings << :invalid_value
                end
              end
              return {lang => valid_titles}, warnings, type
            elsif value.instance_of? Hash
              value = value.clone
              value.each do |l, v|
                if BCP47_REGEXP.match?(l)
                  valid_titles = []
                  Array(v).each do |title|
                    if title.instance_of? String
                      valid_titles << title
                    else
                      warnings << :invalid_value
                    end
                  end
                  value[l] = valid_titles
                else
                  value.delete(l)
                  warnings << :invalid_language
                end
              end
              warnings << :invalid_value if value.empty?
              return value, warnings, type
            else
              return {}, :invalid_value, type
            end
          }
        end

        def column_reference_property(type)
          lambda { |value, base_url, lang|
            return Array(value), nil, type
          }
        end
      end

      PROPERTIES = {
        # context properties
        "@language" => language_property(:context),
        "@base" => link_property(:context),
        # common properties
        "@id" => link_property(:common),
        "notes" => lambda { |value, base_url, lang|
          return false, :invalid_value, :common unless value.instance_of? Array
          values = []
          warnings = []
          value.each do |v|
            v, w = check_common_property_value(v, base_url, lang)
            values << v
            warnings += w
          end
          return values, warnings, :common
        },
        "suppressOutput" => boolean_property(:common),
        "dialect" => lambda { |value, base_url, lang|
          if value.instance_of? Hash
            value = value.clone
            warnings = []
            value.each do |p, v|
              if p == "@id"
                raise Csvlint::Csvw::MetadataError.new("dialect.@id"), "@id starts with _:" if /^_:/.match?(v)
              elsif p == "@type"
                raise Csvlint::Csvw::MetadataError.new("dialect.@type"), "@type of dialect is not 'Dialect'" if v != "Dialect"
              else
                v, warning, type = check_property(p, v, base_url, lang)
                if type == :dialect && (warning.nil? || warning.empty?)
                  value[p] = v
                else
                  value.delete(p)
                  warnings << :invalid_property unless type == :dialect
                  warnings += Array(warning)
                end
              end
            end
            return value, warnings, :common
          else
            return {}, :invalid_value, :common
          end
        },
        # inherited properties
        "null" => lambda { |value, base_url, lang|
          case value
          when String
            return [value], nil, :inherited
          when Array
            values = []
            warnings = []
            value.each do |v|
              if v.instance_of? String
                values << v
              else
                warnings << :invalid_value
              end
            end
            return values, warnings, :inherited
          else
            return [""], :invalid_value, :inherited
          end
        },
        "default" => string_property(:inherited),
        "separator" => lambda { |value, base_url, lang|
          return value, nil, :inherited if value.instance_of?(String) || value.nil?
          return nil, :invalid_value, :inherited
        },
        "lang" => language_property(:inherited),
        "datatype" => lambda { |value, base_url, lang|
          value = value.clone
          warnings = []
          if value.instance_of? Hash
            if value["@id"]
              raise Csvlint::Csvw::MetadataError.new("datatype.@id"), "datatype @id must not be the id of a built-in datatype (#{value["@id"]})" if BUILT_IN_DATATYPES.values.include?(value["@id"])
              v, w, t = PROPERTIES["@id"].call(value["@id"], base_url, lang)
              unless w.nil?
                warnings << w
                value.delete("@id")
              end
            end

            if value["base"]
              if BUILT_IN_DATATYPES.include? value["base"]
                value["base"] = BUILT_IN_DATATYPES[value["base"]]
              else
                value["base"] = BUILT_IN_DATATYPES["string"]
                warnings << :invalid_datatype_base
              end
            else
              value["base"] = BUILT_IN_DATATYPES["string"]
            end
          elsif BUILT_IN_DATATYPES.include? value
            value = {"@id" => BUILT_IN_DATATYPES[value]}
          else
            value = {"@id" => BUILT_IN_DATATYPES["string"]}
            warnings << :invalid_value
          end

          unless STRING_DATATYPES.include?(value["base"]) || BINARY_DATATYPES.include?(value["base"])
            raise Csvlint::Csvw::MetadataError.new("datatype.length"), "datatypes based on #{value["base"]} cannot have a length facet" if value["length"]
            raise Csvlint::Csvw::MetadataError.new("datatype.minLength"), "datatypes based on #{value["base"]} cannot have a minLength facet" if value["minLength"]
            raise Csvlint::Csvw::MetadataError.new("datatype.maxLength"), "datatypes based on #{value["base"]} cannot have a maxLength facet" if value["maxLength"]
          end

          if value["minimum"]
            value["minInclusive"] = value["minimum"]
            value.delete("minimum")
          end
          if value["maximum"]
            value["maxInclusive"] = value["maximum"]
            value.delete("maximum")
          end

          warnings += convert_value_facet(value, "minInclusive", value["base"])
          warnings += convert_value_facet(value, "minExclusive", value["base"])
          warnings += convert_value_facet(value, "maxInclusive", value["base"])
          warnings += convert_value_facet(value, "maxExclusive", value["base"])

          minInclusive = value["minInclusive"].is_a?(Hash) ? value["minInclusive"][:dateTime] : value["minInclusive"]
          maxInclusive = value["maxInclusive"].is_a?(Hash) ? value["maxInclusive"][:dateTime] : value["maxInclusive"]
          minExclusive = value["minExclusive"].is_a?(Hash) ? value["minExclusive"][:dateTime] : value["minExclusive"]
          maxExclusive = value["maxExclusive"].is_a?(Hash) ? value["maxExclusive"][:dateTime] : value["maxExclusive"]

          raise Csvlint::Csvw::MetadataError.new(""), "datatype cannot specify both minimum/minInclusive (#{minInclusive}) and minExclusive (#{minExclusive}" if minInclusive && minExclusive
          raise Csvlint::Csvw::MetadataError.new(""), "datatype cannot specify both maximum/maxInclusive (#{maxInclusive}) and maxExclusive (#{maxExclusive}" if maxInclusive && maxExclusive
          raise Csvlint::Csvw::MetadataError.new(""), "datatype minInclusive (#{minInclusive}) cannot be more than maxInclusive (#{maxInclusive}" if minInclusive && maxInclusive && minInclusive > maxInclusive
          raise Csvlint::Csvw::MetadataError.new(""), "datatype minInclusive (#{minInclusive}) cannot be more than or equal to maxExclusive (#{maxExclusive}" if minInclusive && maxExclusive && minInclusive >= maxExclusive
          raise Csvlint::Csvw::MetadataError.new(""), "datatype minExclusive (#{minExclusive}) cannot be more than or equal to maxExclusive (#{maxExclusive}" if minExclusive && maxExclusive && minExclusive > maxExclusive
          raise Csvlint::Csvw::MetadataError.new(""), "datatype minExclusive (#{minExclusive}) cannot be more than maxInclusive (#{maxInclusive}" if minExclusive && maxInclusive && minExclusive >= maxInclusive

          raise Csvlint::Csvw::MetadataError.new(""), "datatype length (#{value["length"]}) cannot be less than minLength (#{value["minLength"]}" if value["length"] && value["minLength"] && value["length"] < value["minLength"]
          raise Csvlint::Csvw::MetadataError.new(""), "datatype length (#{value["length"]}) cannot be more than maxLength (#{value["maxLength"]}" if value["length"] && value["maxLength"] && value["length"] > value["maxLength"]
          raise Csvlint::Csvw::MetadataError.new(""), "datatype minLength (#{value["minLength"]}) cannot be more than maxLength (#{value["maxLength"]}" if value["minLength"] && value["maxLength"] && value["minLength"] > value["maxLength"]

          if value["format"]
            if REGEXP_FORMAT_DATATYPES.include?(value["base"])
              begin
                value["format"] = Regexp.new(value["format"])
              rescue RegexpError
                value.delete("format")
                warnings << :invalid_regex
              end
            elsif NUMERIC_FORMAT_DATATYPES.include?(value["base"])
              value["format"] = {"pattern" => value["format"]} if value["format"].instance_of? String
              begin
                value["format"] = Csvlint::Csvw::NumberFormat.new(value["format"]["pattern"], value["format"]["groupChar"], value["format"]["decimalChar"] || ".", INTEGER_FORMAT_DATATYPES.include?(value["base"]))
              rescue Csvlint::Csvw::NumberFormatError
                value["format"] = Csvlint::Csvw::NumberFormat.new(nil, value["format"]["groupChar"], value["format"]["decimalChar"] || ".", INTEGER_FORMAT_DATATYPES.include?(value["base"]))
                warnings << :invalid_number_format
              end
            elsif value["base"] == "http://www.w3.org/2001/XMLSchema#boolean"
              if value["format"].instance_of? String
                value["format"] = value["format"].split("|")
                unless value["format"].length == 2
                  value.delete("format")
                  warnings << :invalid_boolean_format
                end
              else
                value.delete("format")
                warnings << :invalid_boolean_format
              end
            elsif DATE_FORMAT_DATATYPES.include?(value["base"])
              if value["format"].instance_of? String
                begin
                  value["format"] = Csvlint::Csvw::DateFormat.new(value["format"])
                rescue Csvlint::CsvDateFormatError
                  value.delete("format")
                  warnings << :invalid_date_format
                end
              else
                value.delete("format")
                warnings << :invalid_date_format
              end
            end
          end
          return value, warnings, :inherited
        },
        "required" => boolean_property(:inherited),
        "ordered" => boolean_property(:inherited),
        "aboutUrl" => uri_template_property(:inherited),
        "propertyUrl" => uri_template_property(:inherited),
        "valueUrl" => uri_template_property(:inherited),
        "textDirection" => lambda { |value, base_url, lang|
          value = value.to_sym
          return value, nil, :inherited if [:ltr, :rtl, :auto, :inherit].include? value
          return :inherit, :invalid_value, :inherited
        },
        # column level properties
        "virtual" => boolean_property(:column),
        "titles" => natural_language_property(:column),
        "name" => lambda { |value, base_url, lang|
          return value, nil, :column if value.instance_of?(String) && value =~ NAME_REGEXP
          return nil, :invalid_value, :column
        },
        # table level properties
        "transformations" => lambda { |value, base_url, lang|
          transformations = []
          warnings = []
          if value.instance_of? Array
            value.each_with_index do |transformation, i|
              if transformation.instance_of? Hash
                transformation = transformation.clone
                transformation.each do |p, v|
                  if p == "@id"
                    raise Csvlint::Csvw::MetadataError.new("transformations[#{i}].@id"), "@id starts with _:" if /^_:/.match?(v)
                  elsif p == "@type"
                    raise Csvlint::Csvw::MetadataError.new("transformations[#{i}].@type"), "@type of transformation is not 'Template'" if v != "Template"
                  elsif p == "url"
                  elsif p == "titles"
                  else
                    v, warning, type = check_property(p, v, base_url, lang)
                    unless type == :transformation && (warning.nil? || warning.empty?)
                      value.delete(p)
                      warnings << :invalid_property unless type == :transformation
                      warnings += Array(warning)
                    end
                  end
                end
                transformations << transformation
              else
                warnings << :invalid_transformation
              end
            end
          else
            warnings << :invalid_value
          end
          return transformations, warnings, :table
        },
        "tableDirection" => lambda { |value, base_url, lang|
          value = value.to_sym
          return value, nil, :table if [:ltr, :rtl, :auto].include? value
          return :auto, :invalid_value, :table
        },
        "tableSchema" => lambda { |value, base_url, lang|
          schema_base_url = base_url
          schema_lang = lang
          if value.instance_of? String
            schema_url = URI.join(base_url, value).to_s
            schema_base_url = schema_url
            schema_ref = schema_url.start_with?("file:") ? File.new(schema_url[5..-1]) : schema_url
            schema = JSON.parse(open(schema_ref).read)
            schema["@id"] = schema["@id"] ? URI.join(schema_url, schema["@id"]).to_s : schema_url
            if schema["@context"]
              if schema["@context"].instance_of?(Array) && schema["@context"].length > 1
                schema_base_url = schema["@context"][1]["@base"] ? URI.join(schema_base_url, schema["@context"][1]["@base"]).to_s : schema_base_url
                schema_lang = schema["@context"][1]["@language"] || schema_lang
              end
              schema.delete("@context")
            end
          elsif value.instance_of? Hash
            schema = value.clone
          else
            return {}, :invalid_value, :table
          end
          warnings = []
          schema.each do |p, v|
            if p == "@id"
              raise Csvlint::Csvw::MetadataError.new("tableSchema.@id"), "@id starts with _:" if /^_:/.match?(v)
            elsif p == "@type"
              raise Csvlint::Csvw::MetadataError.new("tableSchema.@type"), "@type of schema is not 'Schema'" if v != "Schema"
            else
              v, warning, type = check_property(p, v, schema_base_url, schema_lang)
              if (type == :schema || type == :inherited) && (warning.nil? || warning.empty?)
                schema[p] = v
              else
                schema.delete(p)
                warnings << :invalid_property unless type == :schema || type == :inherited
                warnings += Array(warning)
              end
            end
          end
          return schema, warnings, :table
        },
        "url" => link_property(:table),
        # dialect properties
        "commentPrefix" => string_property(:dialect),
        "delimiter" => string_property(:dialect),
        "doubleQuote" => boolean_property(:dialect),
        "encoding" => lambda { |value, base_url, lang|
          return value, nil, :dialect if VALID_ENCODINGS.include? value
          return nil, :invalid_value, :dialect
        },
        "header" => boolean_property(:dialect),
        "headerRowCount" => numeric_property(:dialect),
        "lineTerminators" => array_property(:dialect),
        "quoteChar" => string_property(:dialect),
        "skipBlankRows" => boolean_property(:dialect),
        "skipColumns" => numeric_property(:dialect),
        "skipInitialSpace" => boolean_property(:dialect),
        "skipRows" => numeric_property(:dialect),
        "trim" => lambda { |value, base_url, lang|
          value = :true if value == true || value == "true"
          value = :false if value == false || value == "false"
          value = :start if value == "start"
          value = :end if value == "end"
          return value, nil, :dialect if [:true, :false, :start, :end].include? value
          return true, :invalid_value, :dialect
        },
        # schema properties
        "columns" => lambda { |value, base_url, lang| return value, nil, :schema },
        "primaryKey" => column_reference_property(:schema),
        "foreignKeys" => lambda { |value, base_url, lang|
          foreign_keys = []
          warnings = []
          if value.instance_of? Array
            value.each_with_index do |foreign_key, i|
              if foreign_key.instance_of? Hash
                foreign_key = foreign_key.clone
                foreign_key.each do |p, v|
                  v, warning, type = check_property(p, v, base_url, lang)
                  if type == :foreign_key && (warning.nil? || warning.empty?)
                    foreign_key[p] = v
                  elsif /:/.match?(p)
                    raise Csvlint::Csvw::MetadataError.new("foreignKey.#{p}"), "foreignKey includes a prefixed (common) property"
                  else
                    foreign_key.delete(p)
                    warnings << :invalid_property unless type == :foreign_key
                    warnings += Array(warning)
                  end
                end
                foreign_keys << foreign_key
              else
                warnings << :invalid_foreign_key
              end
            end
          else
            warnings << :invalid_value
          end
          return foreign_keys, warnings, :schema
        },
        "rowTitles" => column_reference_property(:schema),
        # transformation properties
        "targetFormat" => lambda { |value, base_url, lang| return value, nil, :transformation },
        "scriptFormat" => lambda { |value, base_url, lang| return value, nil, :transformation },
        "source" => lambda { |value, base_url, lang| return value, nil, :transformation },
        # foreignKey properties
        "columnReference" => column_reference_property(:foreign_key),
        "reference" => lambda { |value, base_url, lang|
          if value.instance_of? Hash
            value = value.clone
            warnings = []
            value.each do |p, v|
              if ["resource", "schemaReference", "columnReference"].include? p
                v, warning, type = check_property(p, v, base_url, lang)
                if warning.nil? || warning.empty?
                  value[p] = v
                else
                  value.delete(p)
                  warnings += Array(warning)
                end
              elsif /:/.match?(p)
                raise Csvlint::Csvw::MetadataError.new("foreignKey.reference.#{p}"), "foreignKey reference includes a prefixed (common) property"
              else
                value.delete(p)
                warnings << :invalid_property
              end
            end
            raise Csvlint::Csvw::MetadataError.new("foreignKey.reference.columnReference"), "foreignKey reference columnReference is missing" unless value["columnReference"]
            raise Csvlint::Csvw::MetadataError.new("foreignKey.reference"), "foreignKey reference does not have either resource or schemaReference" unless value["resource"] || value["schemaReference"]
            raise Csvlint::Csvw::MetadataError.new("foreignKey.reference"), "foreignKey reference has both resource and schemaReference" if value["resource"] && value["schemaReference"]
            return value, warnings, :foreign_key
          else
            raise Csvlint::Csvw::MetadataError.new("foreignKey.reference"), "foreignKey reference is not an object"
          end
        },
        # foreignKey reference properties
        "resource" => lambda { |value, base_url, lang| return value, nil, :foreign_key_reference },
        "schemaReference" => lambda { |value, base_url, lang|
          return URI.join(base_url, value).to_s, nil, :foreign_key_reference
        }
      }

      NAMESPACES = {
        "dcat" => "http://www.w3.org/ns/dcat#",
        "qb" => "http://purl.org/linked-data/cube#",
        "grddl" => "http://www.w3.org/2003/g/data-view#",
        "ma" => "http://www.w3.org/ns/ma-ont#",
        "org" => "http://www.w3.org/ns/org#",
        "owl" => "http://www.w3.org/2002/07/owl#",
        "prov" => "http://www.w3.org/ns/prov#",
        "rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
        "rdfa" => "http://www.w3.org/ns/rdfa#",
        "rdfs" => "http://www.w3.org/2000/01/rdf-schema#",
        "rif" => "http://www.w3.org/2007/rif#",
        "rr" => "http://www.w3.org/ns/r2rml#",
        "sd" => "http://www.w3.org/ns/sparql-service-description#",
        "skos" => "http://www.w3.org/2004/02/skos/core#",
        "skosxl" => "http://www.w3.org/2008/05/skos-xl#",
        "wdr" => "http://www.w3.org/2007/05/powder#",
        "void" => "http://rdfs.org/ns/void#",
        "wdrs" => "http://www.w3.org/2007/05/powder-s#",
        "xhv" => "http://www.w3.org/1999/xhtml/vocab#",
        "xml" => "http://www.w3.org/XML/1998/namespace",
        "xsd" => "http://www.w3.org/2001/XMLSchema#",
        "csvw" => "http://www.w3.org/ns/csvw#",
        "cnt" => "http://www.w3.org/2008/content",
        "earl" => "http://www.w3.org/ns/earl#",
        "ht" => "http://www.w3.org/2006/http#",
        "oa" => "http://www.w3.org/ns/oa#",
        "ptr" => "http://www.w3.org/2009/pointers#",
        "cc" => "http://creativecommons.org/ns#",
        "ctag" => "http://commontag.org/ns#",
        "dc" => "http://purl.org/dc/terms/",
        "dcterms" => "http://purl.org/dc/terms/",
        "dc11" => "http://purl.org/dc/elements/1.1/",
        "foaf" => "http://xmlns.com/foaf/0.1/",
        "gr" => "http://purl.org/goodrelations/v1#",
        "ical" => "http://www.w3.org/2002/12/cal/icaltzd#",
        "og" => "http://ogp.me/ns#",
        "rev" => "http://purl.org/stuff/rev#",
        "sioc" => "http://rdfs.org/sioc/ns#",
        "v" => "http://rdf.data-vocabulary.org/#",
        "vcard" => "http://www.w3.org/2006/vcard/ns#",
        "schema" => "http://schema.org/"
      }

      BCP47_REGULAR_REGEXP = "(art-lojban|cel-gaulish|no-bok|no-nyn|zh-guoyu|zh-hakka|zh-min|zh-min-nan|zh-xiang)"
      BCP47_IRREGULAR_REGEXP = "(en-GB-oed|i-ami|i-bnn|i-default|i-enochian|i-hak|i-klingon|i-lux|i-mingo|i-navajo|i-pwn|i-tao|i-tay|i-tsu|sgn-BE-FR|sgn-BE-NL|sgn-CH-DE)"
      BCP47_GRANDFATHERED_REGEXP = "(?<grandfathered>" + BCP47_IRREGULAR_REGEXP + "|" + BCP47_REGULAR_REGEXP + ")"
      BCP47_PRIVATE_USE_REGEXP = "(?<privateUse>x(-[A-Za-z0-9]{1,8})+)"
      BCP47_SINGLETON_REGEXP = "[0-9A-WY-Za-wy-z]"
      BCP47_EXTENSION_REGEXP = "(?<extension>" + BCP47_SINGLETON_REGEXP + "(-[A-Za-z0-9]{2,8})+)"
      BCP47_VARIANT_REGEXP = "(?<variant>[A-Za-z0-9]{5,8}|[0-9][A-Za-z0-9]{3})"
      BCP47_REGION_REGEXP = "(?<region>[A-Za-z]{2}|[0-9]{3})"
      BCP47_SCRIPT_REGEXP = "(?<script>[A-Za-z]{4})"
      BCP47_EXTLANG_REGEXP = "(?<extlang>[A-Za-z]{3}(-[A-Za-z]{3}){0,2})"
      BCP47_LANGUAGE_REGEXP = "(?<language>([A-Za-z]{2,3}(-" + BCP47_EXTLANG_REGEXP + ")?)|[A-Za-z]{4}|[A-Za-z]{5,8})"
      BCP47_LANGTAG_REGEXP = "(" + BCP47_LANGUAGE_REGEXP + "(-" + BCP47_SCRIPT_REGEXP + ")?" + "(-" + BCP47_REGION_REGEXP + ")?" + "(-" + BCP47_VARIANT_REGEXP + ")*" + "(-" + BCP47_EXTENSION_REGEXP + ")*" + "(-" + BCP47_PRIVATE_USE_REGEXP + ")?" + ")"
      BCP47_LANGUAGETAG_REGEXP = "^(" + BCP47_GRANDFATHERED_REGEXP + "|" + BCP47_LANGTAG_REGEXP + "|" + BCP47_PRIVATE_USE_REGEXP + ")$"
      BCP47_REGEXP = Regexp.new(BCP47_LANGUAGETAG_REGEXP)

      NAME_REGEXP = /^([A-Za-z0-9]|(%[A-F0-9][A-F0-9]))([A-Za-z0-9_]|(%[A-F0-9][A-F0-9]))*$/

      BUILT_IN_TYPES = ["TableGroup", "Table", "Schema", "Column", "Dialect", "Template", "Datatype"]

      REGEXP_FORMAT_DATATYPES = [
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral",
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#HTML",
        "http://www.w3.org/ns/csvw#JSON",
        "http://www.w3.org/2001/XMLSchema#anyAtomicType",
        "http://www.w3.org/2001/XMLSchema#anyURI",
        "http://www.w3.org/2001/XMLSchema#base64Binary",
        "http://www.w3.org/2001/XMLSchema#duration",
        "http://www.w3.org/2001/XMLSchema#dayTimeDuration",
        "http://www.w3.org/2001/XMLSchema#yearMonthDuration",
        "http://www.w3.org/2001/XMLSchema#hexBinary",
        "http://www.w3.org/2001/XMLSchema#QName",
        "http://www.w3.org/2001/XMLSchema#string",
        "http://www.w3.org/2001/XMLSchema#normalizedString",
        "http://www.w3.org/2001/XMLSchema#token",
        "http://www.w3.org/2001/XMLSchema#language",
        "http://www.w3.org/2001/XMLSchema#Name",
        "http://www.w3.org/2001/XMLSchema#NMTOKEN"
      ]

      STRING_DATATYPES = [
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral",
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#HTML",
        "http://www.w3.org/ns/csvw#JSON",
        "http://www.w3.org/2001/XMLSchema#string",
        "http://www.w3.org/2001/XMLSchema#normalizedString",
        "http://www.w3.org/2001/XMLSchema#token",
        "http://www.w3.org/2001/XMLSchema#language",
        "http://www.w3.org/2001/XMLSchema#Name",
        "http://www.w3.org/2001/XMLSchema#NMTOKEN"
      ]

      BINARY_DATATYPES = [
        "http://www.w3.org/2001/XMLSchema#base64Binary",
        "http://www.w3.org/2001/XMLSchema#hexBinary"
      ]

      INTEGER_FORMAT_DATATYPES = [
        "http://www.w3.org/2001/XMLSchema#integer",
        "http://www.w3.org/2001/XMLSchema#long",
        "http://www.w3.org/2001/XMLSchema#int",
        "http://www.w3.org/2001/XMLSchema#short",
        "http://www.w3.org/2001/XMLSchema#byte",
        "http://www.w3.org/2001/XMLSchema#nonNegativeInteger",
        "http://www.w3.org/2001/XMLSchema#positiveInteger",
        "http://www.w3.org/2001/XMLSchema#unsignedLong",
        "http://www.w3.org/2001/XMLSchema#unsignedInt",
        "http://www.w3.org/2001/XMLSchema#unsignedShort",
        "http://www.w3.org/2001/XMLSchema#unsignedByte",
        "http://www.w3.org/2001/XMLSchema#nonPositiveInteger",
        "http://www.w3.org/2001/XMLSchema#negativeInteger"
      ]

      NUMERIC_FORMAT_DATATYPES = [
        "http://www.w3.org/2001/XMLSchema#decimal",
        "http://www.w3.org/2001/XMLSchema#double",
        "http://www.w3.org/2001/XMLSchema#float"
      ] + INTEGER_FORMAT_DATATYPES

      DATE_FORMAT_DATATYPES = [
        "http://www.w3.org/2001/XMLSchema#date",
        "http://www.w3.org/2001/XMLSchema#dateTime",
        "http://www.w3.org/2001/XMLSchema#dateTimeStamp",
        "http://www.w3.org/2001/XMLSchema#time"
      ]

      BUILT_IN_DATATYPES = {
        "number" => "http://www.w3.org/2001/XMLSchema#double",
        "binary" => "http://www.w3.org/2001/XMLSchema#base64Binary",
        "datetime" => "http://www.w3.org/2001/XMLSchema#dateTime",
        "any" => "http://www.w3.org/2001/XMLSchema#anyAtomicType",
        "xml" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral",
        "html" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#HTML",
        "json" => "http://www.w3.org/ns/csvw#JSON",
        "anyAtomicType" => "http://www.w3.org/2001/XMLSchema#anyAtomicType",
        "anyURI" => "http://www.w3.org/2001/XMLSchema#anyURI",
        "base64Binary" => "http://www.w3.org/2001/XMLSchema#base64Binary",
        "boolean" => "http://www.w3.org/2001/XMLSchema#boolean",
        "date" => "http://www.w3.org/2001/XMLSchema#date",
        "dateTime" => "http://www.w3.org/2001/XMLSchema#dateTime",
        "dateTimeStamp" => "http://www.w3.org/2001/XMLSchema#dateTimeStamp",
        "decimal" => "http://www.w3.org/2001/XMLSchema#decimal",
        "integer" => "http://www.w3.org/2001/XMLSchema#integer",
        "long" => "http://www.w3.org/2001/XMLSchema#long",
        "int" => "http://www.w3.org/2001/XMLSchema#int",
        "short" => "http://www.w3.org/2001/XMLSchema#short",
        "byte" => "http://www.w3.org/2001/XMLSchema#byte",
        "nonNegativeInteger" => "http://www.w3.org/2001/XMLSchema#nonNegativeInteger",
        "positiveInteger" => "http://www.w3.org/2001/XMLSchema#positiveInteger",
        "unsignedLong" => "http://www.w3.org/2001/XMLSchema#unsignedLong",
        "unsignedInt" => "http://www.w3.org/2001/XMLSchema#unsignedInt",
        "unsignedShort" => "http://www.w3.org/2001/XMLSchema#unsignedShort",
        "unsignedByte" => "http://www.w3.org/2001/XMLSchema#unsignedByte",
        "nonPositiveInteger" => "http://www.w3.org/2001/XMLSchema#nonPositiveInteger",
        "negativeInteger" => "http://www.w3.org/2001/XMLSchema#negativeInteger",
        "double" => "http://www.w3.org/2001/XMLSchema#double",
        "duration" => "http://www.w3.org/2001/XMLSchema#duration",
        "dayTimeDuration" => "http://www.w3.org/2001/XMLSchema#dayTimeDuration",
        "yearMonthDuration" => "http://www.w3.org/2001/XMLSchema#yearMonthDuration",
        "float" => "http://www.w3.org/2001/XMLSchema#float",
        "gDay" => "http://www.w3.org/2001/XMLSchema#gDay",
        "gMonth" => "http://www.w3.org/2001/XMLSchema#gMonth",
        "gMonthDay" => "http://www.w3.org/2001/XMLSchema#gMonthDay",
        "gYear" => "http://www.w3.org/2001/XMLSchema#gYear",
        "gYearMonth" => "http://www.w3.org/2001/XMLSchema#gYearMonth",
        "hexBinary" => "http://www.w3.org/2001/XMLSchema#hexBinary",
        "QName" => "http://www.w3.org/2001/XMLSchema#QName",
        "string" => "http://www.w3.org/2001/XMLSchema#string",
        "normalizedString" => "http://www.w3.org/2001/XMLSchema#normalizedString",
        "token" => "http://www.w3.org/2001/XMLSchema#token",
        "language" => "http://www.w3.org/2001/XMLSchema#language",
        "Name" => "http://www.w3.org/2001/XMLSchema#Name",
        "NMTOKEN" => "http://www.w3.org/2001/XMLSchema#NMTOKEN",
        "time" => "http://www.w3.org/2001/XMLSchema#time"
      }

      VALID_ENCODINGS = [
        "utf-8",
        "ibm866",
        "iso-8859-2",
        "iso-8859-3",
        "iso-8859-4",
        "iso-8859-5",
        "iso-8859-6",
        "iso-8859-7",
        "iso-8859-8",
        "iso-8859-8-i",
        "iso-8859-10",
        "iso-8859-13",
        "iso-8859-14",
        "iso-8859-15",
        "iso-8859-16",
        "koi8-r",
        "koi8-u",
        "macintosh",
        "windows-874",
        "windows-1250",
        "windows-1251",
        "windows-1252",
        "windows-1253",
        "windows-1254",
        "windows-1255",
        "windows-1256",
        "windows-1257",
        "windows-1258",
        "x-mac-cyrillic",
        "gb18030",
        "hz-gb-2312",
        "big5",
        "euc-jp",
        "iso-2022-jp",
        "shift_jis",
        "euc-kr",
        "replacement",
        "utf-16be",
        "utf-16le",
        "x-user-defined"
      ]
    end
  end
end
