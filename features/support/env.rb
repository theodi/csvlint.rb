require "coveralls"
Coveralls.wear_merged!("test_frameworks")

$:.unshift File.join(File.dirname(__FILE__), "..", "..", "lib")

require "rspec/expectations"
require "cucumber/rspec/doubles"
require "csvlint"
require "pry"

require "spork"

Spork.each_run do
  require "csvlint"
end

class CustomWorld
  def default_csv_options
    {
    }
  end
end

World do
  CustomWorld.new
end
