Given(/^it is encoded as "(.*?)"$/) do |encoding|
  @csv = @csv.encode(encoding)
  @encoding = encoding
end

Given(/^I set an encoding header of "(.*?)"$/) do |encoding|
  @encoding = encoding
end

Given(/^I do not set an encoding header$/) do
  @encoding = nil
end

Given(/^I have a CSV file called "(.*?)"$/) do |filename|
  @csv = File.read(File.join(File.dirname(__FILE__), "..", "fixtures", filename))
end

When(/^I ask if there are warnings$/) do
  @csv_options ||= default_csv_options
  if @schema_json
    @schema = if @schema_type == :json_table
      Csvlint::Schema.from_json_table(@schema_url || "http://example.org ", JSON.parse(@schema_json))
    else
      Csvlint::Schema.from_csvw_metadata(@schema_url || "http://example.org ", JSON.parse(@schema_json))
    end
  end

  @validator = Csvlint::Validator.new(@url, @csv_options, @schema)
  @warnings = @validator.warnings
end

Then(/^there should be warnings$/) do
  expect(@warnings.count).to be > 0
end

Then(/^there should not be warnings$/) do
  # this test is only used for CSVW testing, and :inconsistent_values warnings don't count in CSVW
  @warnings.delete_if { |w| [:inconsistent_values, :check_options].include?(w.type) }
  expect(@warnings.count).to eq(0)
end

Then(/^there should be (\d+) warnings$/) do |count|
  expect(@warnings.count).to eq(count.to_i)
end

Given(/^the content type is set to "(.*?)"$/) do |type|
  @content_type = type
end

Then(/^that warning should have the row "(.*?)"$/) do |row|
  expect(@warnings.first.row).to eq(row.to_i)
end

Then(/^that warning should have the column "(.*?)"$/) do |column|
  expect(@warnings.first.column).to eq(column.to_i)
end

Then(/^that warning should have the type "(.*?)"$/) do |type|
  expect(@warnings.first.type).to eq(type.to_sym)
end
