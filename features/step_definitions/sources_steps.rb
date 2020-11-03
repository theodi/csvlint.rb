Given(/^it is parsed as a StringIO$/) do
  @url = StringIO.new(@csv)
end

Given(/^I parse a file called "(.*?)"$/) do |filename|
  @url = File.new(File.join(File.dirname(__FILE__), "..", "fixtures", filename))
end
