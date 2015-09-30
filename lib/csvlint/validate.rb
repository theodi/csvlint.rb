module Csvlint

  class Validator

    include Csvlint::ErrorCollector

    attr_reader :encoding, :content_type, :extension, :headers, :link_headers, :dialect, :csv_header, :schema, :data

    ERROR_MATCHERS = {
        "Missing or stray quote" => :stray_quote,
        "Illegal quoting" => :whitespace,
        "Unclosed quoted field" => :unclosed_quote,
        "Unquoted fields do not allow \\r or \\n" => :line_breaks,
    }

    def initialize(source, dialect = {}, schema = nil, options = {}, row_sep = nil)
      reset
      @source = source
      @formats = []
      @schema = schema

      @assumed_header = dialect["header"].nil?
      @supplied_dialect = dialect != {}

      @dialect = {
          "header" => true,
          "delimiter" => ",",
          "skipInitialSpace" => true,
          "lineTerminator" => :auto,
          "quoteChar" => '"'
      }.merge(dialect)

      @csv_header = @dialect["header"]
      @limit_lines = options[:limit_lines]
      @extension = parse_extension(source) unless @source.nil?
      @csv_options = dialect_to_csv_options(@dialect)

      @expected_columns = 0
      @col_counts = []
      @line_breaks = []

      @data = [] # it may be advisable to flush this on init?

      reset
      validate
      # TODO - separating the initialise and validate calls means that specs assertions in streaming_validator are more verbose, but can also be unit tested

    end

    def validate
      locate_schema unless @schema.instance_of?(Csvlint::Schema)

      if @source.class == String
        validate_url
      else
        validate_stream
      end
      finish
    end

    def validate_stream
      @i = 1
      @source.each_line do |line|
        break if line_limit_reached?
        validate_line(line, @i)
        @i = @i+1
      end
    end

    def validate_url
      @i = 1
    begin
      leading = ""
      request = Typhoeus::Request.new(@source, followlocation: true)
      request.on_headers do |response|
        @headers = response.headers
        @content_type = response.headers["content-type"] rescue nil
        @response_code = response.code
        return build_errors(:not_found) if response.code == 404
      end
      request.on_body do |chunk|
        io = StringIO.new(leading + chunk)
        io.each_line do |line|
          break if line_limit_reached?
          line = leading + line
          # Check if the last line is a line break - in which case it's a full line
          if line[-1, 1].include?("\n")
            # If the number of quotes is odd, the linebreak is inside some quotes
            if line.count(@dialect["quoteChar"]).odd?
              leading = line
            else
              validate_line(line, @i)
              leading = ""
              @i = @i+1
            end
          else
            # If it's not a full line, then prepare to add it to the beginning of the next chunk
            leading = line
          end
        end
      end
      request.run
      # Validate the last line too
      validate_line(leading, @i) unless leading == ""
      rescue ArgumentError => ae
        build_errors(:invalid_encoding, :structure, @i, nil, @i) unless @reported_invalid_encoding
        @reported_invalid_encoding = true
      end
    end

    def validate_line(input = nil, index = nil)
      @input = input
      single_col = false
      line = index.present? ? index : 0
      @encoding = input.encoding.to_s
      report_line_breaks(line)
      parse_contents(input, line)
    rescue ArgumentError => ae
       build_errors(:invalid_encoding, :structure, i, nil, index) unless @reported_invalid_encoding
       @reported_invalid_encoding = true
    end

    # analyses the provided csv and builds errors, warnings and info messages
    def parse_contents(stream, line = nil)
      # parse_contents will parse one line and apply headers, formats methods and error handle as appropriate
      current_line = line.present? ? line : 1
      all_errors = []

      @csv_options[:encoding] = @encoding

      begin
      row = CSV.parse_line(stream, @csv_options)
        # this is a one line substitute for CSV.new followed by row = CSV.shift. a CSV Row class is required
        # CSV.parse will return an array of arrays which breaks subsequent each_with_index invocations
        # TODO investigate if above would be a drag on memory

      rescue CSV::MalformedCSVError => e
        build_exception_messages(e, stream, current_line)
      end

      @data << row
      # TODO currently it doesn't matter where the above rescue is the @data array is either populated with nil or nothing
      # TODO is that intended behaviour?
      if row
        if current_line <= 1 && @csv_header
          # this conditional should be refactored somewhere
          row = row.reject { |col| col.nil? || col.empty? }
          validate_header(row)
          @col_counts << row.size
        else
          build_formats(row)
          @col_counts << row.reject { |col| col.nil? || col.empty? }.size
          @expected_columns = row.size unless @expected_columns != 0
          build_errors(:blank_rows, :structure, current_line, nil, stream.to_s) if row.reject { |c| c.nil? || c.empty? }.size == 0
          # Builds errors and warnings related to the provided schema file
          if @schema
            @schema.validate_row(row, current_line, all_errors, @source)
            @errors += @schema.errors
            all_errors += @schema.errors
            @warnings += @schema.warnings
          else
            build_errors(:ragged_rows, :structure, current_line, nil, stream.to_s) if !row.empty? && row.size != @expected_columns
          end
        end
      end
    end

    def finish
      sum = @col_counts.inject(:+)
      unless sum.nil?
        build_warnings(:title_row, :structure) if @col_counts.first < (sum / @col_counts.size.to_f)
      end
      # return expected_columns to calling class
      build_warnings(:check_options, :structure) if @expected_columns == 1
      check_consistency
      validate_metadata
      check_mixed_linebreaks
    end

    def validate_metadata
      @csv_header = true
      assumed_header = !@supplied_dialect
      if @headers
        if @headers["content-type"] =~ /text\/csv/
          @csv_header = true
          assumed_header = @assumed_header.present?
        end
        if @headers["content-type"] =~ /header=(present|absent)/
          @csv_header = true if $1 == "present"
          @csv_header = false if $1 == "absent"
          assumed_header = false
        end
        if @headers["content-type"] !~ /charset=/
          build_warnings(:no_encoding, :context)
        elsif @encoding != "UTF-8" || @headers["content-type"] !~ /charset=utf-8/i
          build_warnings(:encoding, :context)
        end
        build_warnings(:no_content_type, :context) if @content_type == nil
        build_warnings(:excel, :context) if @content_type == nil && @extension =~ /.xls(x)?/
        build_errors(:wrong_content_type, :context) unless (@content_type && @content_type =~ /text\/csv/)
      end
      @header_processed = true
      build_info_messages(:assumed_header, :structure) if assumed_header
    end

    def header?
      @csv_header && @dialect["header"]
    end

    def report_line_breaks(line_no=nil)
      return if @input !~ /[\r|\n]/ # Return straight away if there's no newline character - i.e. we're on the last line
      line_break = CSV.new(@input).row_sep
      @line_breaks << line_break
      unless line_breaks_reported?
        if line_break != "\r\n"
          build_info_messages(:nonrfc_line_breaks, :structure, line_no)
          @line_breaks_reported = true
        end
      end
    end

    def line_breaks_reported?
      @line_breaks_reported === true
    end

    def set_dialect(dialect)
      begin
        schema_dialect = @schema.tables[@source_url].dialect || {}
      rescue
        schema_dialect = {}
      end
      @dialect = {
        "header" => true,
        "delimiter" => ",",
        "skipInitialSpace" => true,
        "lineTerminator" => :auto,
        "quoteChar" => '"',
        "trim" => :true
      }.merge(schema_dialect).merge(dialect || {})

      @csv_header = @csv_header && @dialect["header"]
      @csv_options = dialect_to_csv_options(@dialect)
    end


    def check_mixed_linebreaks
      build_linebreak_error if @line_breaks.uniq.count > 1
    end

    def line_breaks
      if @line_breaks.uniq.count > 1
        :mixed
      else
        @line_breaks.uniq.first
      end
    end

    def build_exception_messages(csvException, errChars, lineNo)
      #TODO 1 - this is a change in logic, rather than straight refactor of previous error building, however original logic is bonkers
      #TODO 2 - using .kind_of? is a very ugly fix here and it meant to work around instances where :auto symbol is preserved in @csv_options
      type = fetch_error(csvException)
      if !@csv_options[:row_sep].kind_of?(Symbol) && type == :unclosed_quote && !@input.match(@csv_options[:row_sep])
        build_linebreak_error
      else
        build_errors(type, :structure, lineNo, nil, errChars)
      end
    end

    def build_linebreak_error
      build_errors(:line_breaks, :structure) unless @errors.any? { |e| e.type == :line_breaks }
    end

    def validate_header(header)
      names = Set.new
      header.map{|h| h.strip! } if @dialect["trim"] == :true
      header.each_with_index do |name,i|
        build_warnings(:empty_column_name, :schema, nil, i+1) if name == ""
        if names.include?(name)
          build_warnings(:duplicate_column_name, :schema, nil, i+1)
        else
          names << name
        end
      end
      if @schema
        @schema.validate_header(header, @source)
        @errors += @schema.errors
        @warnings += @schema.warnings
      end
      return valid?
    end

    def fetch_error(error)
      e = error.message.match(/^(.+?)(?: [io]n)? \(?line \d+\)?\.?$/i)
      message = e[1] rescue nil
      ERROR_MATCHERS.fetch(message, :unknown_error)
    end

    def dialect_to_csv_options(dialect)
      skipinitialspace = dialect["skipInitialSpace"] || true
      delimiter = dialect["delimiter"]
      delimiter = delimiter + " " if !skipinitialspace
      return {
          :col_sep => delimiter,
          :row_sep => dialect["lineTerminator"],
          :quote_char => dialect["quoteChar"],
          :skip_blanks => false
      }
    end

    def build_formats(row)
      row.each_with_index do |col, i|
        next if col.nil? || col.empty?
        @formats[i] ||= Hash.new(0)

        format =
            if col.strip[FORMATS[:numeric]]
              :numeric
            elsif uri?(col)
              :uri
            elsif col[FORMATS[:date_db]] && date_format?(Date, col, '%Y-%m-%d')
              :date_db
            elsif col[FORMATS[:date_short]] && date_format?(Date, col, '%e %b')
              :date_short
            elsif col[FORMATS[:date_rfc822]] && date_format?(Date, col, '%e %b %Y')
              :date_rfc822
            elsif col[FORMATS[:date_long]] && date_format?(Date, col, '%B %e, %Y')
              :date_long
            elsif col[FORMATS[:dateTime_time]] && date_format?(Time, col, '%H:%M')
              :dateTime_time
            elsif col[FORMATS[:dateTime_hms]] && date_format?(Time, col, '%H:%M:%S')
              :dateTime_hms
            elsif col[FORMATS[:dateTime_db]] && date_format?(Time, col, '%Y-%m-%d %H:%M:%S')
              :dateTime_db
            elsif col[FORMATS[:dateTime_iso8601]] && date_format?(Time, col, '%Y-%m-%dT%H:%M:%SZ')
              :dateTime_iso8601
            elsif col[FORMATS[:dateTime_short]] && date_format?(Time, col, '%d %b %H:%M')
              :dateTime_short
            elsif col[FORMATS[:dateTime_long]] && date_format?(Time, col, '%B %d, %Y %H:%M')
              :dateTime_long
            else
              :string
            end

        @formats[i][format] += 1
      end
    end

    def check_consistency
      @formats.each_with_index do |format,i|
        if format
          total = format.values.reduce(:+).to_f
          if format.none?{|_,count| count / total >= 0.9}
            build_warnings(:inconsistent_values, :schema, nil, i + 1)
          end
        end
      end
    end

    def check_foreign_keys
      if @schema.instance_of? Csvlint::Csvw::TableGroup
        @schema.validate_foreign_keys
        @errors += @schema.errors
        @warnings += @schema.warnings
      end
    end

    def locate_schema
      @source_url = nil
      warn_if_unsuccessful = false
      case @source
      when StringIO
        return
      when File
        @source_url = "file:#{File.expand_path(@source)}"
      else
        @source_url = @source
      end
      unless @schema.nil?
        if @schema.tables[@source_url]
          return
        else
          @schema = nil
        end
      end
      link_schema = nil
      @link_headers.each do |link_header|
        match = LINK_HEADER_REGEXP.match(link_header)
        uri = match["uri"].gsub(/(^\<|\>$)/, "")
        rel = match["rel-relationship"].gsub(/(^\"|\"$)/, "")
        param = match["param"]
        param_value = match["param-value"].gsub(/(^\"|\"$)/, "")
        if rel == "describedby" && param == "type" && ["application/csvm+json", "application/ld+json", "application/json"].include?(param_value)
          begin
            url = URI.join(@source_url, uri)
            schema = Schema.load_from_json(url)
            if schema.instance_of? Csvlint::Csvw::TableGroup
              if schema.tables[@source_url]
                link_schema = schema
              else
                warn_if_unsuccessful = true
                build_warnings(:schema_mismatch, :context, nil, nil, @source_url, schema)
              end
            end
          rescue OpenURI::HTTPError
          end
        end
      end if @link_headers
      @schema = link_schema if link_schema

      paths = []
      if @source_url =~ /^http(s)?/
        begin
          well_known_uri = URI.join(@source_url, "/.well-known/csvm")
          well_known = open(well_known_uri).read
          # TODO
        rescue OpenURI::HTTPError
        end
      end
      paths = ["{+url}-metadata.json", "csv-metadata.json"] if paths.empty?
      paths.each do |template|
        begin
          template = URITemplate.new(template)
          path = template.expand('url' => @source_url)
          url = URI.join(@source_url, path)
          url = File.new(url.to_s.sub(/^file:/, "")) if url.to_s =~ /^file:/
          schema = Schema.load_from_json(url)
          if schema.instance_of? Csvlint::Csvw::TableGroup
            if schema.tables[@source_url]
              @schema = schema
            else
              warn_if_unsuccessful = true
              build_warnings(:schema_mismatch, :context, nil, nil, @source_url, schema)
            end
          end
        rescue Errno::ENOENT
        rescue OpenURI::HTTPError
        rescue=> e
          STDERR.puts e.class
          STDERR.puts e.message
          STDERR.puts e.backtrace
          raise e
        end
      end
      build_warnings(:schema_mismatch, :context, nil, nil, @source_url, schema) if warn_if_unsuccessful
      @schema = nil
    end

    private

    def parse_extension(source)

      case source
        when File
          return File.extname( source.path )
        when IO
          return ""
        when StringIO
          return ""
        when Tempfile
          # this is triggered when the revalidate dialect use case happens
          return ""
        else
          begin
            parsed = URI.parse(source)
            File.extname(parsed.path)
          rescue URI::InvalidURIError
            return ""
          end
      end
    end

    def uri?(value)
      if value.strip[FORMATS[:uri]]
        uri = URI.parse(value)
        uri.kind_of?(URI::HTTP) || uri.kind_of?(URI::HTTPS)
      end
    rescue URI::InvalidURIError
      false
    end

    def date_format?(klass, value, format)
      klass.strptime(value, format).strftime(format) == value
    rescue ArgumentError # invalid date
      false
    end

    def line_limit_reached?
       @limit_lines.present? && @i > @limit_lines
    end

    FORMATS = {
        :string => nil,
        :numeric => /\A[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?\z/,
        :uri => /\Ahttps?:/,
        :date_db => /\A\d{4,}-\d\d-\d\d\z/,                                               # "12345-01-01"
        :date_long => /\A(?:#{Date::MONTHNAMES.join('|')}) [ \d]\d, \d{4,}\z/,            # "January  1, 12345"
        :date_rfc822 => /\A[ \d]\d (?:#{Date::ABBR_MONTHNAMES.join('|')}) \d{4,}\z/,      # " 1 Jan 12345"
        :date_short => /\A[ \d]\d (?:#{Date::ABBR_MONTHNAMES.join('|')})\z/,              # "1 Jan"
        :dateTime_db => /\A\d{4,}-\d\d-\d\d \d\d:\d\d:\d\d\z/,                            # "12345-01-01 00:00:00"
        :dateTime_hms => /\A\d\d:\d\d:\d\d\z/,                                            # "00:00:00"
        :dateTime_iso8601 => /\A\d{4,}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/,                      # "12345-01-01T00:00:00Z"
        :dateTime_long => /\A(?:#{Date::MONTHNAMES.join('|')}) \d\d, \d{4,} \d\d:\d\d\z/, # "January 01, 12345 00:00"
        :dateTime_short => /\A\d\d (?:#{Date::ABBR_MONTHNAMES.join('|')}) \d\d:\d\d\z/,   # "01 Jan 00:00"
        :dateTime_time => /\A\d\d:\d\d\z/,                                                # "00:00"
    }.freeze

    URI_REGEXP = /(?<uri>.*?)/
    TOKEN_REGEXP = /([^\(\)\<\>@,;:\\"\/\[\]\?=\{\} \t]+)/
    QUOTED_STRING_REGEXP = /("[^"]*")/
    SGML_NAME_REGEXP = /([A-Za-z][-A-Za-z0-9\.]*)/
    RELATIONSHIP_REGEXP = Regexp.new("(?<relationship>#{SGML_NAME_REGEXP}|(\"#{SGML_NAME_REGEXP}(\\s+#{SGML_NAME_REGEXP})*\"))")
    REL_REGEXP = Regexp.new("(?<rel>\\s*rel\\s*=\\s*(?<rel-relationship>#{RELATIONSHIP_REGEXP}))")
    REV_REGEXP = Regexp.new("(?<rev>\\s*rev\\s*=\\s*#{RELATIONSHIP_REGEXP})")
    TITLE_REGEXP = Regexp.new("(?<title>\\s*title\\s*=\\s*#{QUOTED_STRING_REGEXP})")
    ANCHOR_REGEXP = Regexp.new("(?<anchor>\\s*anchor\\s*=\\s*\\<#{URI_REGEXP}\\>)")
    LINK_EXTENSION_REGEXP = Regexp.new("(?<link-extension>(?<param>#{TOKEN_REGEXP})(\\s*=\\s*(?<param-value>#{TOKEN_REGEXP}|#{QUOTED_STRING_REGEXP}))?)")
    LINK_PARAM_REGEXP = Regexp.new("(#{REL_REGEXP}|#{REV_REGEXP}|#{TITLE_REGEXP}|#{ANCHOR_REGEXP}|#{LINK_EXTENSION_REGEXP})")
    LINK_HEADER_REGEXP = Regexp.new("\<#{URI_REGEXP}\>(\\s*;\\s*#{LINK_PARAM_REGEXP})*")

  end
end
