module Csvlint
  module ErrorCollector
    attr_reader :errors, :warnings, :info_messages
    # Creates a validation error
    def build_errors(type, category = nil, row = nil, column = nil, content = nil, constraints = {})
      @errors << Csvlint::ErrorMessage.new(type, category, row, column, content, constraints)
    end

    # Creates a validation warning
    def build_warnings(type, category = nil, row = nil, column = nil, content = nil, constraints = {})
      @warnings << Csvlint::ErrorMessage.new(type, category, row, column, content, constraints)
    end

    # Creates a validation information message
    def build_info_messages(type, category = nil, row = nil, column = nil, content = nil, constraints = {})
      @info_messages << Csvlint::ErrorMessage.new(type, category, row, column, content, constraints)
    end

    def valid?
      errors.empty?
    end

    def reset
      @errors = []
      @warnings = []
      @info_messages = []
    end
  end
end
