Given(/^I have a CSV with the following content:$/) do |string|
  @csv = string.to_s
end

Given(/^it has a Link header holding "(.*?)"$/) do |link|
  @link = "#{link}; type=\"application/csvm+json\""
end

Given(/^it is stored at the url "(.*?)"$/) do |url|
  @url = url
  content_type = @content_type || "text/csv"
  charset = @encoding || "UTF-8"
  headers = {"Content-Type" => "#{content_type}; charset=#{charset}"}
  headers["Link"] = @link if @link
  stub_request(:get, url).to_return(status: 200, body: @csv, headers: headers)
  stub_request(:get, URI.join(url, "/.well-known/csvm")).to_return(status: 404)
  stub_request(:get, url + "-metadata.json").to_return(status: 404)
  stub_request(:get, URI.join(url, "csv-metadata.json")).to_return(status: 404)
end

Given(/^it is stored at the url "(.*?)" with no character set$/) do |url|
  @url = url
  content_type = @content_type || "text/csv"
  stub_request(:get, url).to_return(status: 200, body: @csv, headers: {"Content-Type" => content_type.to_s})
  stub_request(:get, URI.join(url, "/.well-known/csvm")).to_return(status: 404)
  stub_request(:get, url + "-metadata.json").to_return(status: 404)
  stub_request(:get, URI.join(url, "csv-metadata.json")).to_return(status: 404)
end

When(/^I ask if the CSV is valid$/) do
  @csv_options ||= default_csv_options
  @validator = Csvlint::Validator.new(@url, @csv_options)
  @valid = @validator.valid?
end

Then(/^I should get the value of true$/) do
  expect(@valid).to be(true)
end

Then(/^I should get the value of false$/) do
  expect(@valid).to be(false)
end
