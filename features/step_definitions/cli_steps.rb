Given(/^I have stubbed stdin to contain "(.*?)"$/) do |file|
  expect(STDIN).to receive(:read).and_return(File.read(file))
end

Given(/^I have stubbed stdin to contain nothing$/) do
  expect(STDIN).to receive(:read).and_return(nil)
end

Then(/^nothing should be outputted to STDERR$/) do
  expect(STDERR).to_not receive(:puts)
end

Then(/^the output should contain JSON$/) do
  @json = JSON.parse(all_stdout)
  expect(@json["validation"]).to be_present
end

Then(/^the JSON should have a state of "(.*?)"$/) do |state|
  expect(@json["validation"]["state"]).to eq(state)
end

Then(/^the JSON should have (\d+) errors?$/) do |count|
  @index = count.to_i - 1
  expect(@json["validation"]["errors"].count).to eq(count.to_i)
end

Then(/^that error should have the "(.*?)" "(.*?)"$/) do |k, v|
  expect(@json["validation"]["errors"][@index][k].to_s).to eq(v)
end

Then(/^error (\d+) should have the "(.*?)" "(.*?)"$/) do |index, k, v|
  expect(@json["validation"]["errors"][index.to_i - 1][k].to_s).to eq(v)
end

Then(/^error (\d+) should have the constraint "(.*?)" "(.*?)"$/) do |index, k, v|
  expect(@json["validation"]["errors"][index.to_i - 1]["constraints"][k].to_s).to eq(v)
end
