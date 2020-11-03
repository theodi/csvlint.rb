module Csvlint
  module Csvw
    class MetadataError < StandardError
      attr_reader :path

      def initialize(path = nil)
        @path = path
      end
    end
  end
end
