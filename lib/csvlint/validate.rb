module Csvlint

  class Validator
    class LineCSV < CSV
      ENCODE_RE = Hash.new do |h,str|
        h[str] = Regexp.new(str)
      end

      ENCODE_STR = Hash.new do |h,encoding_name|
        h[encoding_name] = Hash.new do |h,chunks|
          h[chunks] = chunks.map { |chunk| chunk.encode(encoding_name) }.join('')
        end
      end

      ESCAPE_RE = Hash.new do |h,re_chars|
        h[re_chars] = Hash.new do |h,re_esc|
          h[re_esc] = Hash.new do |h,str|
            h[str] = str.gsub(re_chars) {|c| re_esc + c}
          end
        end
      end

      # Optimization: Memoize `encode_re`.
      # @see https://github.com/ruby/ruby/blob/v2_2_3/lib/csv.rb#L2273
      def encode_re(*chunks)
        ENCODE_RE[encode_str(*chunks)]
      end

      # Optimization: Memoize `encode_str`.
      # @see https://github.com/ruby/ruby/blob/v2_2_3/lib/csv.rb#L2281
      def encode_str(*chunks)
        ENCODE_STR[@encoding.name][chunks]
      end

      # Optimization: Memoize `escape_re`.
      # @see https://github.com/ruby/ruby/blob/v2_2_3/lib/csv.rb#L2265
      def escape_re(str)
        ESCAPE_RE[@re_chars][@re_esc][str]
      end

      if RUBY_VERSION < '2.5'
        # Optimization: Disable the CSV library's converters feature.
        # @see https://github.com/ruby/ruby/blob/v2_2_3/lib/csv.rb#L2100
        def init_converters(options, field_name = :converters)
          @converters = []
          @header_converters = []
          options.delete(:unconverted_fields)
          options.delete(field_name)
        end
      end
    end

    include Csvlint::ErrorCollector

    attr_reader :encoding, :content_type, :extension, :headers, :link_headers, :dialect, :csv_header, :schema, :data, :current_line

    ERROR_MATCHERS = {
        "Missing or stray quote" => :stray_quote,
        "Illegal quoting" => :whitespace,
        "Unclosed quoted field" => :unclosed_quote,
        "Unquoted fields do not allow \\r or \\n" => :line_breaks,
    }

    def initialize(source, dialect = {}, schema = nil, options = {})
      reset
      @source = source
      @formats = []
      @schema = schema
      @dialect = dialect
      @csv_header = true
      @headers = {}
      @lambda = options[:lambda]
      @validate = options[:validate].nil? ? true : options[:validate]
      @leading = ""

      @limit_lines = options[:limit_lines]
      @extension = parse_extension(source) unless @source.nil?

      @expected_columns = 0
      @col_counts = []
      @line_breaks = []

      @errors += @schema.errors unless @schema.nil?
      @warnings += @schema.warnings unless @schema.nil?

      @data = [] # it may be advisable to flush this on init?

      validate
    end

    def validate
      if @extension =~ /.xls(x)?/
        build_warnings(:excel, :context)
        return
      end
      locate_schema unless @schema.instance_of?(Csvlint::Schema)
      set_dialect

      if @source.class == String
        validate_url
      else
        validate_metadata
        validate_stream
      end
      finish
    end

    def validate_stream
      if (@source.nil?)
        return
      end
      @current_line = 1
      @source.each_line do |line|
        break if line_limit_reached?
        parse_line(line)
      end
      validate_line(@leading, @current_line) unless @leading == ""
    end

    def validate_url
      @current_line = 1
      request = Typhoeus::Request.new(@source, followlocation: true)
      request.on_headers do |response|
        @headers = response.headers || {}
        @content_type = response.headers["content-type"] rescue nil
        @response_code = response.code
        return build_errors(:not_found) if response.code == 404
        validate_metadata
      end
      request.on_body do |chunk|
        chunk.force_encoding(Encoding::UTF_8) if chunk.encoding == Encoding::ASCII_8BIT
        io = StringIO.new(chunk)
        io.each_line do |line|
          break if line_limit_reached?
          parse_line(line)
        end
      end
      request.run
      # Validate the last line too
      validate_line(@leading, @current_line) unless @leading == ""
    end

    def parse_line(line)
      line = @leading + line
      # Check if the last line is a line break - in which case it's a full line
      if line[-1, 1].include?("\n")
        # If the number of quotes is odd, the linebreak is inside some quotes
        if line.count(@dialect["quoteChar"]).odd?
          @leading = line
        else
          validate_line(line, @current_line)
          @leading = ""
          @current_line = @current_line+1
        end
      else
        # If it's not a full line, then prepare to add it to the beginning of the next chunk
        @leading = line
      end
    rescue ArgumentError => ae
      build_errors(:invalid_encoding, :structure, @current_line, nil, @current_line) unless @reported_invalid_encoding
      @current_line = @current_line+1
      @reported_invalid_encoding = true
    end

    def validate_line(input = nil, index = nil)
      @input = input
      single_col = false
      line = index.present? ? index : 0
      @encoding = input.encoding.to_s
      report_line_breaks(line)
      parse_contents(input, line)
      @lambda.call(self) unless @lambda.nil?
    rescue ArgumentError => ae
      build_errors(:invalid_encoding, :structure, @current_line, nil, index) unless @reported_invalid_encoding
      @reported_invalid_encoding = true
    end

    # analyses the provided csv and builds errors, warnings and info messages
    def parse_contents(stream, line = nil)
      # parse_contents will parse one line and apply headers, formats methods and error handle as appropriate
      current_line = line.present? ? line : 1
      all_errors = []

      @csv_options[:encoding] = @encoding

      begin
        row = LineCSV.parse_line(stream, @csv_options)
      rescue LineCSV::MalformedCSVError => e
        build_exception_messages(e, stream, current_line)
      end

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
            @schema.validate_row(row, current_line, all_errors, @source, @validate)
            @errors += @schema.errors
            all_errors += @schema.errors
            @warnings += @schema.warnings
          else
            build_errors(:ragged_rows, :structure, current_line, nil, stream.to_s) if !row.empty? && row.size != @expected_columns
          end
        end
      end
      @data << row
    end

    def finish
      sum = @col_counts.inject(:+)
      unless sum.nil?
        build_warnings(:title_row, :structure) if @col_counts.first < (sum / @col_counts.size.to_f)
      end
      # return expected_columns to calling class
      build_warnings(:check_options, :structure) if @expected_columns == 1
      check_consistency
      check_foreign_keys if @validate
      check_mixed_linebreaks
      validate_encoding
    end

    def validate_metadata
      assumed_header = !@supplied_dialect
      unless @headers.empty?
        if @headers["content-type"] =~ /text\/csv/
          @csv_header = @csv_header && true
          assumed_header = @assumed_header.present?
        end
        if @headers["content-type"] =~ /header=(present|absent)/
          @csv_header = true if $1 == "present"
          @csv_header = false if $1 == "absent"
          assumed_header = false
        end
        build_warnings(:no_content_type, :context) if @content_type == nil
        build_errors(:wrong_content_type, :context) unless (@content_type && @content_type =~ /text\/csv/)
      end
      @header_processed = true
      build_info_messages(:assumed_header, :structure) if assumed_header

      @link_headers = @headers["link"].split(",") rescue nil
      @link_headers.each do |link_header|
        match = LINK_HEADER_REGEXP.match(link_header)
        uri = match["uri"].gsub(/(^\<|\>$)/, "") rescue nil
        rel = match["rel-relationship"].gsub(/(^\"|\"$)/, "") rescue nil
        param = match["param"]
        param_value = match["param-value"].gsub(/(^\"|\"$)/, "") rescue nil
        if rel == "describedby" && param == "type" && ["application/csvm+json", "application/ld+json", "application/json"].include?(param_value)
          begin
            url = URI.join(@source_url, uri)
            schema = Schema.load_from_uri(url)
            if schema.instance_of? Csvlint::Csvw::TableGroup
              if schema.tables[@source_url]
                @schema = schema
              else
                warn_if_unsuccessful = true
                build_warnings(:schema_mismatch, :context, nil, nil, @source_url, schema)
              end
            end
          rescue OpenURI::HTTPError
          end
        end
      end if @link_headers
    end

    def header?
      @csv_header && @dialect["header"]
    end

    def report_line_breaks(line_no=nil)
      return unless @input[-1, 1].include?("\n") # Return straight away if there's no newline character - i.e. we're on the last line
      line_break = get_line_break(@input)
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

    def set_dialect
      @assumed_header = @dialect["header"].nil?
      @supplied_dialect = @dialect != {}

      begin
        schema_dialect = @schema.tables[@source_url].dialect || {}
      rescue
        schema_dialect = {}
      end
      @dialect = {
          "header" => true,
          "headerRowCount" => 1,
          "delimiter" => ",",
          "skipInitialSpace" => true,
          "lineTerminator" => :auto,
          "quoteChar" => '"',
          "trim" => :true
      }.merge(schema_dialect).merge(@dialect || {})

      @csv_header = @csv_header && @dialect["header"]
      @csv_options = dialect_to_csv_options(@dialect)
    end

    def validate_encoding
      if @headers["content-type"]
        if @headers["content-type"] !~ /charset=/
          build_warnings(:no_encoding, :context)
        elsif @headers["content-type"] !~ /charset=utf-8/i
          build_warnings(:encoding, :context)
        end
      end
      build_warnings(:encoding, :context) if @encoding != "UTF-8"
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

    def row_count
      data.count
    end

    def build_exception_messages(csvException, errChars, lineNo)
      #TODO 1 - this is a change in logic, rather than straight refactor of previous error building, however original logic is bonkers
      #TODO 2 - using .kind_of? is a very ugly fix here and it meant to work around instances where :auto symbol is preserved in @csv_options
      type = fetch_error(csvException)
      if !@csv_options[:row_sep].kind_of?(Symbol) && [:unclosed_quote,:stray_quote].include?(type) && !@input.match(@csv_options[:row_sep])
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
        @schema.validate_header(header, @source, @validate)
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
            elsif possible_date?(col)
              date_formats(col)
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
          @source_url = "file:#{URI.encode(File.expand_path(@source))}"
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
      paths = []
      if @source_url =~ /^http(s)?/
        begin
          well_known_uri = URI.join(@source_url, "/.well-known/csvm")
          paths = open(well_known_uri).read.split("\n")
        rescue OpenURI::HTTPError, URI::BadURIError
        end
      end
      paths = ["{+url}-metadata.json", "csv-metadata.json"] if paths.empty?
      paths.each do |template|
        begin
          template = URITemplate.new(template)
          path = template.expand('url' => @source_url)
          url = URI.join(@source_url, path)
          url = File.new(url.to_s.sub(/^file:/, "")) if url.to_s =~ /^file:/
          schema = Schema.load_from_uri(url)
          if schema.instance_of? Csvlint::Csvw::TableGroup
            if schema.tables[@source_url]
              @schema = schema
              return
            else
              warn_if_unsuccessful = true
              build_warnings(:schema_mismatch, :context, nil, nil, @source_url, schema)
            end
          end
        rescue Errno::ENOENT
        rescue OpenURI::HTTPError, URI::BadURIError, ArgumentError
        rescue => e
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

    def possible_date?(col)
      col[POSSIBLE_DATE_REGEXP]
    end

    def date_formats(col)
      if col[FORMATS[:date_db]] && date_format?(Date, col, '%Y-%m-%d')
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
    end

    def date_format?(klass, value, format)
      klass.strptime(value, format).strftime(format) == value
    rescue ArgumentError # invalid date
      false
    end

    def line_limit_reached?
      @limit_lines.present? && @current_line > @limit_lines
    end

    def get_line_break(line)
      eol = line.chars.last(2)
      if eol.first == "\r"
        "\r\n"
      else
        "\n"
      end
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
    POSSIBLE_DATE_REGEXP = Regexp.new("\\A(\\d|\\s\\d#{Date::ABBR_MONTHNAMES.join('|')}#{Date::MONTHNAMES.join('|')})")

  end
end
