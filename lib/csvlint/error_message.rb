module Csvlint
  class ErrorMessage
    attr_reader :type, :category, :row, :column, :content, :constraints

    def initialize(type, category, row, column, content, constraints)
      @type = type
      @category = category
      @row = row
      @column = column
      @content = content
      @constraints = constraints
    end
  end
end
