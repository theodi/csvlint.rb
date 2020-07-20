Given(/^I have a schema with the following content:$/) do |json|
  @schema_type = :json_table
  @schema_json = json
end

Given(/^I have metadata with the following content:$/) do |json|
  @schema_type = :csvw_metadata
  @schema_json = json
end

Given(/^I have a metadata file called "([^"]*)"$/) do |filename|
  @schema_type = :csvw_metadata
  @schema_json = File.read(File.join(File.dirname(__FILE__), "..", "fixtures", filename))
end

Given(/^the (schema|metadata) is stored at the url "(.*?)"$/) do |schema_type, schema_url|
  @schema_url = schema_url
  stub_request(:get, @schema_url).to_return(status: 200, body: @schema_json.to_str)
end

Given(/^there is a file at "(.*?)" with the content:$/) do |url, content|
  stub_request(:get, url).to_return(status: 200, body: content.to_str)
end

Given(/^I have a file called "(.*?)" at the url "(.*?)"$/) do |filename, url|
  content = File.read(File.join(File.dirname(__FILE__), "..", "fixtures", filename))
  content_type = /.csv$/.match?(filename) ? "text/csv" : "application/csvm+json"
  stub_request(:get, url).to_return(status: 200, body: content, headers: {"Content-Type" => "#{content_type}; charset=UTF-8"})
end

Given(/^there is no file at the url "(.*?)"$/) do |url|
  stub_request(:get, url).to_return(status: 404)
end
