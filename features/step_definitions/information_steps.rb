Given(/^the content type is "(.*?)"$/) do |arg1|
  @content_type = "text/csv"
end

Then(/^the "(.*?)" should be "(.*?)"$/) do |type, encoding|
  validator = Csvlint::Validator.new(@url, default_csv_options)
  expect(validator.send(type.to_sym)).to eq(encoding)
end

Then(/^the metadata content type should be "(.*?)"$/) do |content_type|
  validator = Csvlint::Validator.new(@url, default_csv_options)
  expect(validator.headers["content-type"]).to eq(content_type)
end
