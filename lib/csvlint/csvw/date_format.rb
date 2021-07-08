module Csvlint
  module Csvw
    class DateFormat

      attr_reader :pattern

      def initialize(pattern, datatype=nil)
        @pattern = pattern

        if @pattern.nil?
          @regexp = DEFAULT_REGEXP[datatype]
          @type = datatype
        else
          test_pattern = pattern.clone
          test_pattern.gsub!(/S+/, "")
          FIELDS.keys.sort_by{|f| -f.length}.each do |field|
            test_pattern.gsub!(field, "")
          end
          raise Csvw::DateFormatError, "unrecognised date field symbols in date format" if test_pattern =~ /[GyYuUrQqMLlwWdDFgEecahHKkjJmsSAzZOvVXx]/

          @regexp = DATE_PATTERN_REGEXP[@pattern]
          @type = @regexp.nil? ? "http://www.w3.org/2001/XMLSchema#time" : "http://www.w3.org/2001/XMLSchema#date"
          @regexp = @regexp || TIME_PATTERN_REGEXP[@pattern]
          @type = @regexp.nil? ? "http://www.w3.org/2001/XMLSchema#dateTime" : @type
          @regexp = @regexp || DATE_TIME_PATTERN_REGEXP[@pattern]

          if @regexp.nil?
            regexp = @pattern

            @type = "http://www.w3.org/2001/XMLSchema#date" if !(regexp =~ /HH/) && regexp =~ /yyyy/
            @type = "http://www.w3.org/2001/XMLSchema#time" if regexp =~ /HH/ && !(regexp =~ /yyyy/)
            @type = "http://www.w3.org/2001/XMLSchema#dateTime" if regexp =~ /HH/ && regexp =~ /yyyy/

            regexp = regexp.sub("HH", FIELDS["HH"].to_s)
            regexp = regexp.sub("mm", FIELDS["mm"].to_s)
            if @pattern =~ /ss\.S+/
              max_fractional_seconds = @pattern.split(".")[-1].length
              regexp = regexp.sub(/ss\.S+$/, "(?<second>#{FIELDS["ss"]}(\.[0-9]{1,#{max_fractional_seconds}})?)")
            else
              regexp = regexp.sub("ss", "(?<second>#{FIELDS["ss"]})")
            end

            if regexp =~ /yyyy/
              regexp = regexp.sub("yyyy", FIELDS["yyyy"].to_s)
              regexp = regexp.sub("MM", FIELDS["MM"].to_s)
              regexp = regexp.sub("M", FIELDS["M"].to_s)
              regexp = regexp.sub("dd", FIELDS["dd"].to_s)
              regexp = regexp.sub(/d(?=[-T \/\.])/, FIELDS["d"].to_s)
            end

            regexp = regexp.sub("XXX", FIELDS["XXX"].to_s)
            regexp = regexp.sub("XX", FIELDS["XX"].to_s)
            regexp = regexp.sub("X", FIELDS["X"].to_s)
            regexp = regexp.sub("xxx", FIELDS["xxx"].to_s)
            regexp = regexp.sub("xx", FIELDS["xx"].to_s)
            regexp = regexp.sub(/x(?!:)/, FIELDS["x"].to_s)

            @regexp = Regexp.new("^#{regexp}$")
          end
        end
      end

      def match(value)
        value =~ @regexp ? true : false
      end

      def parse(value)
        match = @regexp.match(value)
        return nil if match.nil?
        # STDERR.puts(@regexp)
        # STDERR.puts(value)
        # STDERR.puts(match.inspect)
        value = {}
        match.names.each do |field|
          unless match[field].nil?
            case field
            when "timezone"
              tz = match["timezone"]
              tz = "+00:00" if tz == 'Z'
              tz += ':00' if tz.length == 3
              tz = "#{tz[0..2]}:#{tz[3..4]}" unless tz =~ /:/
              value[:timezone] = tz
            when "second"
              value[:second] = match["second"].to_f
            else
              value[field.to_sym] = match[field].to_i
            end
          end
        end
        case @type
        when "http://www.w3.org/2001/XMLSchema#date"
          begin
            value[:dateTime] = Date.new(match["year"].to_i, match["month"].to_i, match["day"].to_i)
          rescue ArgumentError
            return nil
          end
        when "http://www.w3.org/2001/XMLSchema#dateTime"
          begin
            value[:dateTime] = DateTime.new(match["year"].to_i, match["month"].to_i, match["day"].to_i, match["hour"].to_i, match["minute"].to_i, (match.names.include?("second") ? match["second"].to_f : 0), match.names.include?("timezone") && match["timezone"] ? match["timezone"] : '')
          rescue ArgumentError
            return nil
          end
        else
          value[:dateTime] = DateTime.new(value[:year] || 0, value[:month] || 1, value[:day] || 1, value[:hour] || 0, value[:minute] || 0, value[:second] || 0, value[:timezone] || "+00:00")
        end
        if value[:year]
          if value[:month]
            if value[:day]
              if value[:hour]
                # dateTime
                value[:string] = "#{format('%04d', value[:year])}-#{format('%02d', value[:month])}-#{format('%02d', value[:day])}T#{format('%02d', value[:hour])}:#{format('%02d', value[:minute] || 0)}:#{format('%02g', value[:second] || 0)}#{value[:timezone] ? value[:timezone].sub("+00:00", "Z") : ''}"
              else
                # date
                value[:string] = "#{format('%04d', value[:year])}-#{format('%02d', value[:month])}-#{format('%02d', value[:day])}#{value[:timezone] ? value[:timezone].sub("+00:00", "Z") : ''}"
              end
            else
              # gYearMonth
              value[:string] = "#{format('%04d', value[:year])}-#{format('%02d', value[:month])}#{value[:timezone] ? value[:timezone].sub("+00:00", "Z") : ''}"
            end
          else
            # gYear
            value[:string] = "#{format('%04d', value[:year])}#{value[:timezone] ? value[:timezone].sub("+00:00", "Z") : ''}"
          end
        elsif value[:month]
          if value[:day]
            # gMonthDay
            value[:string] = "--#{format('%02d', value[:month])}-#{format('%02d', value[:day])}#{value[:timezone] ? value[:timezone].sub("+00:00", "Z") : ''}"
          else
            # gMonth
            value[:string] = "--#{format('%02d', value[:month])}#{value[:timezone] ? value[:timezone].sub("+00:00", "Z") : ''}"
          end
        elsif value[:day]
          # gDay
          value[:string] = "---#{format('%02d', value[:day])}#{value[:timezone] ? value[:timezone].sub("+00:00", "Z") : ''}"
        else
          value[:string] = "#{format('%02d', value[:hour])}:#{format('%02d', value[:minute])}:#{format('%02g', value[:second] || 0)}#{value[:timezone] ? value[:timezone].sub("+00:00", "Z") : ''}"
        end
        return value
      end

      private
        FIELDS = {
          "yyyy" => /(?<year>-?([1-9][0-9]{3}|0[0-9]{3}))/,
          "MM" => /(?<month>0[1-9]|1[0-2])/,
          "M" => /(?<month>[1-9]|1[0-2])/,
          "dd" => /(?<day>0[1-9]|[12][0-9]|3[01])/,
          "d" => /(?<day>0?[1-9]|[12]?[0-9]|3[01])/,
          "HH" => /(?<hour>[01][0-9]|2[0-3])/,
          "H" => /(?<hour>0?[0-9]|1[0-9]|2[0-3])/,
          "mm" => /(?<minute>[0-5][0-9])/,
          "ss" => /([0-6][0-9])/,
          "X" => /(?<timezone>Z|[-+]((0[0-9]|1[0-3])([0-5][0-9])?|14(00)?))/,
          "XX" => /(?<timezone>Z|[-+]((0[0-9]|1[0-3])[0-5][0-9]|1400))/,
          "XXX" => /(?<timezone>Z|[-+]((0[0-9]|1[0-3]):[0-5][0-9]|14:00))/,
          "x" => /(?<timezone>[-+]((0[0-9]|1[0-3])([0-5][0-9])?|14(00)?))/,
          "xx" => /(?<timezone>[-+]((0[0-9]|1[0-3])[0-5][0-9]|1400))/,
          "xxx" => /(?<timezone>[-+]((0[0-9]|1[0-3]):[0-5][0-9]|14:00))/,
        }

        DATE_PATTERN_REGEXP = {
          "yyyy-MM-dd" => Regexp.new("^#{FIELDS["yyyy"]}-#{FIELDS["MM"]}-#{FIELDS["dd"]}$"),
          "yyyyMMdd" => Regexp.new("^#{FIELDS["yyyy"]}#{FIELDS["MM"]}#{FIELDS["dd"]}$"),
          "dd-MM-yyyy" => Regexp.new("^#{FIELDS["dd"]}-#{FIELDS["MM"]}-#{FIELDS["yyyy"]}$"),
          "d-M-yyyy" => Regexp.new("^#{FIELDS["d"]}-#{FIELDS["M"]}-#{FIELDS["yyyy"]}$"),
          "MM-dd-yyyy" => Regexp.new("^#{FIELDS["MM"]}-#{FIELDS["dd"]}-#{FIELDS["yyyy"]}$"),
          "M-d-yyyy" => Regexp.new("^#{FIELDS["M"]}-#{FIELDS["d"]}-#{FIELDS["yyyy"]}$"),
          "dd/MM/yyyy" => Regexp.new("^#{FIELDS["dd"]}/#{FIELDS["MM"]}/#{FIELDS["yyyy"]}$"),
          "d/M/yyyy" => Regexp.new("^#{FIELDS["d"]}/#{FIELDS["M"]}/#{FIELDS["yyyy"]}$"),
          "MM/dd/yyyy" => Regexp.new("^#{FIELDS["MM"]}/#{FIELDS["dd"]}/#{FIELDS["yyyy"]}$"),
          "M/d/yyyy" => Regexp.new("^#{FIELDS["M"]}/#{FIELDS["d"]}/#{FIELDS["yyyy"]}$"),
          "dd.MM.yyyy" => Regexp.new("^#{FIELDS["dd"]}.#{FIELDS["MM"]}.#{FIELDS["yyyy"]}$"),
          "d.M.yyyy" => Regexp.new("^#{FIELDS["d"]}.#{FIELDS["M"]}.#{FIELDS["yyyy"]}$"),
          "MM.dd.yyyy" => Regexp.new("^#{FIELDS["MM"]}.#{FIELDS["dd"]}.#{FIELDS["yyyy"]}$"),
          "M.d.yyyy" => Regexp.new("^#{FIELDS["M"]}.#{FIELDS["d"]}.#{FIELDS["yyyy"]}$"),
          "dMMyyyy" => Regexp.new("^#{FIELDS["d"]}#{FIELDS["MM"]}#{FIELDS["yyyy"]}$"),
        }

        TIME_PATTERN_REGEXP = {
          "HH:mm:ss" => Regexp.new("^#{FIELDS["HH"]}:#{FIELDS["mm"]}:(?<second>#{FIELDS["ss"]})$"),
          "HHmmss" => Regexp.new("^#{FIELDS["HH"]}#{FIELDS["mm"]}(?<second>#{FIELDS["ss"]})$"),
          "HH:mm" => Regexp.new("^#{FIELDS["HH"]}:#{FIELDS["mm"]}$"),
          "H:mm" => Regexp.new("^#{FIELDS["H"]}:#{FIELDS["mm"]}$"),
          "HHmm" => Regexp.new("^#{FIELDS["HH"]}#{FIELDS["mm"]}$")
        }

        DATE_TIME_PATTERN_REGEXP = {
          "yyyy-MM-ddTHH:mm:ss" => Regexp.new("^#{FIELDS["yyyy"]}-#{FIELDS["MM"]}-#{FIELDS["dd"]}T#{FIELDS["HH"]}:#{FIELDS["mm"]}:(?<second>#{FIELDS["ss"]})$"),
          "yyyy-MM-ddTHH:mm" => Regexp.new("^#{FIELDS["yyyy"]}-#{FIELDS["MM"]}-#{FIELDS["dd"]}T#{FIELDS["HH"]}:#{FIELDS["mm"]}$")
        }

        DEFAULT_REGEXP = {
          "http://www.w3.org/2001/XMLSchema#date" =>
            Regexp.new("^#{FIELDS["yyyy"]}-#{FIELDS["MM"]}-#{FIELDS["dd"]}#{FIELDS["XXX"]}?$"),
          "http://www.w3.org/2001/XMLSchema#dateTime" =>
            Regexp.new("^#{FIELDS["yyyy"]}-#{FIELDS["MM"]}-#{FIELDS["dd"]}T#{FIELDS["HH"]}:#{FIELDS["mm"]}:(?<second>#{FIELDS["ss"]}(\.[0-9]+)?)#{FIELDS["XXX"]}?$"),
          "http://www.w3.org/2001/XMLSchema#dateTimeStamp" =>
            Regexp.new("^#{FIELDS["yyyy"]}-#{FIELDS["MM"]}-#{FIELDS["dd"]}T#{FIELDS["HH"]}:#{FIELDS["mm"]}:(?<second>#{FIELDS["ss"]}(\.[0-9]+)?)#{FIELDS["XXX"]}$"),
          "http://www.w3.org/2001/XMLSchema#gDay" =>
            Regexp.new("^---#{FIELDS["dd"]}#{FIELDS["XXX"]}?$"),
          "http://www.w3.org/2001/XMLSchema#gMonth" =>
            Regexp.new("^--#{FIELDS["MM"]}#{FIELDS["XXX"]}?$"),
          "http://www.w3.org/2001/XMLSchema#gMonthDay" =>
            Regexp.new("^--#{FIELDS["MM"]}-#{FIELDS["dd"]}#{FIELDS["XXX"]}?$"),
          "http://www.w3.org/2001/XMLSchema#gYear" =>
            Regexp.new("^#{FIELDS["yyyy"]}#{FIELDS["XXX"]}?$"),
          "http://www.w3.org/2001/XMLSchema#gYearMonth" =>
            Regexp.new("^#{FIELDS["yyyy"]}-#{FIELDS["MM"]}#{FIELDS["XXX"]}?$"),
          "http://www.w3.org/2001/XMLSchema#time" =>
            Regexp.new("^#{FIELDS["HH"]}:#{FIELDS["mm"]}:(?<second>#{FIELDS["ss"]}(\.[0-9]+)?)#{FIELDS["XXX"]}?$")
        }

    end

    class DateFormatError < StandardError

    end
  end
end
