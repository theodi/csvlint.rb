Given(/^I ask if there are info messages$/) do
  @csv_options ||= default_csv_options

  if @schema_json
    @schema = if @schema_type == :json_table
      Csvlint::Schema.from_json_table(@schema_url || "http://example.org ", JSON.parse(@schema_json))
    else
      Csvlint::Schema.from_csvw_metadata(@schema_url || "http://example.org ", JSON.parse(@schema_json))
    end
  end

  @validator = Csvlint::Validator.new(@url, @csv_options, @schema)
  @info_messages = @validator.info_messages
end

Then(/^there should be (\d+) info messages?$/) do |num|
  expect(@info_messages.count).to eq(num.to_i)
end

Then(/^one of the messages should have the type "(.*?)"$/) do |msg_type|
  expect(@info_messages.find { |x| x.type == msg_type.to_sym }).to be_present
end
