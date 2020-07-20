module Csvlint
  module Csvw
    class NumberFormat
      attr_reader :integer, :pattern, :prefix, :numeric_part, :suffix, :grouping_separator, :decimal_separator, :primary_grouping_size, :secondary_grouping_size, :fractional_grouping_size

      def initialize(pattern = nil, grouping_separator = nil, decimal_separator = ".", integer = nil)
        @pattern = pattern
        @integer = integer
        if @integer.nil?
          @integer = if @pattern.nil?
            nil
          else
            !@pattern.include?(decimal_separator)
          end
        end
        @grouping_separator = grouping_separator || (@pattern.nil? ? nil : ",")
        @decimal_separator = decimal_separator || "."
        if pattern.nil?
          @regexp = if integer
            INTEGER_REGEXP
          else
            Regexp.new("^(([-+]?[0-9]+(\\.[0-9]+)?([Ee][-+]?[0-9]+)?[%‰]?)|NaN|INF|-INF)$")
          end
        else
          numeric_part_regexp = Regexp.new("(?<numeric_part>[-+]?([0#Ee]|#{Regexp.escape(@grouping_separator)}|#{Regexp.escape(@decimal_separator)})+)")
          number_format_regexp = Regexp.new("^(?<prefix>.*?)#{numeric_part_regexp}(?<suffix>.*?)$")
          match = number_format_regexp.match(pattern)
          raise Csvw::NumberFormatError, "invalid number format" if match.nil?

          @prefix = match["prefix"]
          @numeric_part = match["numeric_part"]
          @suffix = match["suffix"]

          parts = @numeric_part.split("E")
          mantissa_part = parts[0]
          exponent_part = parts[1] || ""
          mantissa_parts = mantissa_part.split(@decimal_separator)
          # raise Csvw::NumberFormatError, "more than two decimal separators in number format" if parts.length > 2
          integer_part = mantissa_parts[0]
          fractional_part = mantissa_parts[1] || ""

          if ["+", "-"].include?(integer_part[0])
            numeric_part_regexp = "\\#{integer_part[0]}"
            integer_part = integer_part[1..-1]
          else
            numeric_part_regexp = "[-+]?"
          end

          min_integer_digits = integer_part.gsub(@grouping_separator, "").delete("#").length
          min_fraction_digits = fractional_part.gsub(@grouping_separator, "").delete("#").length
          max_fraction_digits = fractional_part.gsub(@grouping_separator, "").length
          min_exponent_digits = exponent_part.delete("#").length
          max_exponent_digits = exponent_part.length

          integer_parts = integer_part.split(@grouping_separator)[1..-1]
          @primary_grouping_size = begin
                                     integer_parts[-1].length
                                   rescue
                                     0
                                   end
          @secondary_grouping_size = begin
                                       integer_parts[-2].length
                                     rescue
                                       @primary_grouping_size
                                     end

          fractional_parts = fractional_part.split(@grouping_separator)[0..-2]
          @fractional_grouping_size = begin
                                        fractional_parts[0].length
                                      rescue
                                        0
                                      end

          if @primary_grouping_size == 0
            integer_regexp = "[0-9]*[0-9]{#{min_integer_digits}}"
          else
            leading_regexp = "([0-9]{0,#{@secondary_grouping_size - 1}}#{Regexp.escape(@grouping_separator)})?"
            secondary_groups = "([0-9]{#{@secondary_grouping_size}}#{Regexp.escape(@grouping_separator)})*"
            if min_integer_digits > @primary_grouping_size
              remaining_req_digits = min_integer_digits - @primary_grouping_size
              req_secondary_groups = remaining_req_digits / @secondary_grouping_size > 0 ? "([0-9]{#{@secondary_grouping_size}}#{Regexp.escape(@grouping_separator)}){#{remaining_req_digits / @secondary_grouping_size}}" : ""
              if remaining_req_digits % @secondary_grouping_size > 0
                final_req_digits = "[0-9]{#{@secondary_grouping_size - (remaining_req_digits % @secondary_grouping_size)}}"
                final_opt_digits = "[0-9]{0,#{@secondary_grouping_size - (remaining_req_digits % @secondary_grouping_size)}}"
                integer_regexp = "((#{leading_regexp}#{secondary_groups}#{final_req_digits})|#{final_opt_digits})[0-9]{#{remaining_req_digits % @secondary_grouping_size}}#{Regexp.escape(@grouping_separator)}#{req_secondary_groups}[0-9]{#{@primary_grouping_size}}"
              else
                integer_regexp = "(#{leading_regexp}#{secondary_groups})?#{req_secondary_groups}[0-9]{#{@primary_grouping_size}}"
              end
            else
              final_req_digits = @primary_grouping_size > min_integer_digits ? "[0-9]{#{@primary_grouping_size - min_integer_digits}}" : ""
              final_opt_digits = @primary_grouping_size > min_integer_digits ? "[0-9]{0,#{@primary_grouping_size - min_integer_digits}}" : ""
              integer_regexp = "((#{leading_regexp}#{secondary_groups}#{final_req_digits})|#{final_opt_digits})[0-9]{#{min_integer_digits}}"
            end
          end

          numeric_part_regexp += integer_regexp

          if max_fraction_digits > 0
            if @fractional_grouping_size == 0
              fractional_regexp = ""
              fractional_regexp += "[0-9]{#{min_fraction_digits}}" if min_fraction_digits > 0
              fractional_regexp += "[0-9]{0,#{max_fraction_digits - min_fraction_digits}}" unless min_fraction_digits == max_fraction_digits
              fractional_regexp = "#{Regexp.escape(@decimal_separator)}#{fractional_regexp}"
              fractional_regexp = "(#{fractional_regexp})?" if min_fraction_digits == 0
              numeric_part_regexp += fractional_regexp
            else
              fractional_regexp = ""

              if min_fraction_digits > 0
                if min_fraction_digits >= @fractional_grouping_size
                  # first group of required digits - something like "[0-9]{3}"
                  fractional_regexp += "[0-9]{#{@fractional_grouping_size}}"
                  # additional groups of required digits - something like "(,[0-9]{3}){1}"
                  fractional_regexp += "(#{Regexp.escape(@grouping_separator)}[0-9]{#{@fractional_grouping_size}}){#{min_fraction_digits / @fractional_grouping_size - 1}}" if min_fraction_digits / @fractional_grouping_size > 1
                  fractional_regexp += Regexp.escape(@grouping_separator).to_s if min_fraction_digits % @fractional_grouping_size > 0
                end
                # additional required digits - something like ",[0-9]{1}"
                fractional_regexp += "[0-9]{#{min_fraction_digits % @fractional_grouping_size}}" if min_fraction_digits % @fractional_grouping_size > 0

                opt_fractional_digits = max_fraction_digits - min_fraction_digits
                if opt_fractional_digits > 0
                  fractional_regexp += "("

                  if min_fraction_digits % @fractional_grouping_size > 0
                    # optional fractional digits to complete the group
                    fractional_regexp += "[0-9]{0,#{[opt_fractional_digits, @fractional_grouping_size - (min_fraction_digits % @fractional_grouping_size)].min}}"
                    fractional_regexp += "|"
                    fractional_regexp += "[0-9]{#{[opt_fractional_digits, @fractional_grouping_size - (min_fraction_digits % @fractional_grouping_size)].min}}"
                  else
                    fractional_regexp += "(#{Regexp.escape(@grouping_separator)}[0-9]{1,#{@fractional_grouping_size}})?"
                    fractional_regexp += "|"
                    fractional_regexp += "#{Regexp.escape(@grouping_separator)}[0-9]{#{@fractional_grouping_size}}"
                  end

                  remaining_opt_fractional_digits = opt_fractional_digits - (@fractional_grouping_size - (min_fraction_digits % @fractional_grouping_size))
                  if remaining_opt_fractional_digits > 0
                    if remaining_opt_fractional_digits % @fractional_grouping_size > 0
                      # optional fraction digits in groups
                      fractional_regexp += "(#{Regexp.escape(@grouping_separator)}[0-9]{#{@fractional_grouping_size}}){0,#{remaining_opt_fractional_digits / @fractional_grouping_size}}" if remaining_opt_fractional_digits > @fractional_grouping_size
                      # remaining optional fraction digits
                      fractional_regexp += "(#{Regexp.escape(@grouping_separator)}[0-9]{1,#{remaining_opt_fractional_digits % @fractional_grouping_size}})?"
                    else
                      # optional fraction digits in groups
                      fractional_regexp += "(#{Regexp.escape(@grouping_separator)}[0-9]{#{@fractional_grouping_size}}){0,#{(remaining_opt_fractional_digits / @fractional_grouping_size) - 1}}" if remaining_opt_fractional_digits > @fractional_grouping_size
                      # remaining optional fraction digits
                      fractional_regexp += "(#{Regexp.escape(@grouping_separator)}[0-9]{1,#{@fractional_grouping_size}})?"
                    end

                    # optional fraction digits in groups
                    fractional_regexp += "(#{Regexp.escape(@grouping_separator)}[0-9]{#{@fractional_grouping_size}}){0,#{(remaining_opt_fractional_digits / @fractional_grouping_size) - 1}}" if remaining_opt_fractional_digits > @fractional_grouping_size
                    # remaining optional fraction digits
                    fractional_regexp += "(#{Regexp.escape(@grouping_separator)}[0-9]{1,#{remaining_opt_fractional_digits % @fractional_grouping_size}})?" if remaining_opt_fractional_digits % @fractional_grouping_size > 0
                  end
                  fractional_regexp += ")"
                end
              elsif max_fraction_digits % @fractional_grouping_size > 0
                # optional fractional digits in groups
                fractional_regexp += "([0-9]{#{@fractional_grouping_size}}#{Regexp.escape(@grouping_separator)}){0,#{max_fraction_digits / @fractional_grouping_size}}"
                # remaining optional fraction digits
                fractional_regexp += "(#{Regexp.escape(@grouping_separator)}[0-9]{1,#{max_fraction_digits % @fractional_grouping_size}})?" if max_fraction_digits % @fractional_grouping_size > 0
              else
                fractional_regexp += "([0-9]{#{@fractional_grouping_size}}#{Regexp.escape(@grouping_separator)}){0,#{(max_fraction_digits / @fractional_grouping_size) - 1}}" if max_fraction_digits > @fractional_grouping_size
                fractional_regexp += "[0-9]{1,#{@fractional_grouping_size}}"
              end
              fractional_regexp = "#{Regexp.escape(@decimal_separator)}#{fractional_regexp}"
              fractional_regexp = "(#{fractional_regexp})?" if min_fraction_digits == 0
              numeric_part_regexp += fractional_regexp
            end
          end

          if max_exponent_digits > 0
            numeric_part_regexp += "E"
            numeric_part_regexp += "[0-9]{0,#{max_exponent_digits - min_exponent_digits}}" unless max_exponent_digits == min_exponent_digits
            numeric_part_regexp += "[0-9]{#{min_exponent_digits}}" unless min_exponent_digits == 0
          end

          @regexp = Regexp.new("^(?<prefix>#{Regexp.escape(@prefix)})(?<numeric_part>#{numeric_part_regexp})(?<suffix>#{suffix})$")
        end
      end

      def match(value)
        value&.match?(@regexp) ? true : false
      end

      def parse(value)
        if @pattern.nil?
          return nil if !@grouping_separator.nil? && value =~ Regexp.new("((^#{Regexp.escape(@grouping_separator)})|#{Regexp.escape(@grouping_separator)}{2})")
          value.gsub!(@grouping_separator, "") unless @grouping_separator.nil?
          value.gsub!(@decimal_separator, ".") unless @decimal_separator.nil?
          if value&.match?(@regexp)
            case value
            when "NaN"
              Float::NAN
            when "INF"
              Float::INFINITY
            when "-INF"
              -Float::INFINITY
            else
              case value[-1]
              when "%"
                value.to_f / 100
              when "‰"
                value.to_f / 1000
              else
                if @integer.nil?
                  value.include?(".") ? value.to_f : value.to_i
                else
                  @integer ? value.to_i : value.to_f
                end
              end
            end
          end
        else
          match = @regexp.match(value)
          return nil if match.nil?
          number = match["numeric_part"]
          number.gsub!(@grouping_separator, "") unless @grouping_separator.nil?
          number.gsub!(@decimal_separator, ".") unless @decimal_separator.nil?
          number = @integer ? number.to_i : number.to_f
          number = number.to_f / 100 if match["prefix"].include?("%") || match["suffix"].include?("%")
          number = number.to_f / 1000 if match["prefix"].include?("‰") || match["suffix"].include?("‰")
          number
        end
      end

      private

      INTEGER_REGEXP = /^[-+]?[0-9]+[%‰]?$/
    end

    class NumberFormatError < StandardError
    end
  end
end
