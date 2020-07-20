require "spec_helper"

describe Csvlint::Csvw::DateFormat do
  it "should parse dates that match yyyy-MM-dd correctly" do
    format = Csvlint::Csvw::DateFormat.new("yyyy-MM-dd")
    expect(format.parse("2015-03-22")[:dateTime]).to eql(Date.new(2015, 3, 22))
    expect(format.parse("2015-02-30")).to eql(nil)
    expect(format.parse("22/03/2015")).to eq(nil)
  end

  it "should parse times that match HH:mm:ss correctly" do
    format = Csvlint::Csvw::DateFormat.new("HH:mm:ss")
    expect(format.parse("12:34:56")).to eql({hour: 12, minute: 34, second: 56.0, string: "12:34:56", dateTime: DateTime.new(0, 1, 1, 12, 34, 56.0, "+00:00")})
    expect(format.parse("22/03/2015")).to eq(nil)
  end

  it "should parse times that match HH:mm:ss.SSS correctly" do
    format = Csvlint::Csvw::DateFormat.new("HH:mm:ss.SSS")
    expect(format.parse("12:34:56")).to eql({hour: 12, minute: 34, second: 56.0, string: "12:34:56", dateTime: DateTime.new(0, 1, 1, 12, 34, 56.0, "+00:00")})
    expect(format.parse("12:34:56.78")).to eql({hour: 12, minute: 34, second: 56.78, string: "12:34:56.78", dateTime: DateTime.new(0, 1, 1, 12, 34, 56.78, "+00:00")})
    expect(format.parse("12:34:56.789")).to eql({hour: 12, minute: 34, second: 56.789, string: "12:34:56.789", dateTime: DateTime.new(0, 1, 1, 12, 34, 56.789, "+00:00")})
    expect(format.parse("12:34:56.7890")).to eql(nil)
    expect(format.parse("22/03/2015")).to eq(nil)
  end

  it "should parse dateTimes that match yyyy-MM-ddTHH:mm:ss correctly" do
    format = Csvlint::Csvw::DateFormat.new("yyyy-MM-ddTHH:mm:ss")
    expect(format.parse("2015-03-15T15:02:37")[:dateTime]).to eql(DateTime.new(2015, 3, 15, 15, 2, 37))
    expect(format.parse("12:34:56")).to eql(nil)
    expect(format.parse("22/03/2015")).to eq(nil)
  end

  it "should parse dateTimes that match yyyy-MM-ddTHH:mm:ss.S correctly" do
    format = Csvlint::Csvw::DateFormat.new("yyyy-MM-ddTHH:mm:ss.S")
    expect(format.parse("2015-03-15T15:02:37")[:dateTime]).to eql(DateTime.new(2015, 3, 15, 15, 2, 37.0))
    expect(format.parse("2015-03-15T15:02:37.4")[:dateTime]).to eql(DateTime.new(2015, 3, 15, 15, 2, 37.4))
    expect(format.parse("2015-03-15T15:02:37.45")).to eql(nil)
    expect(format.parse("12:34:56")).to eql(nil)
    expect(format.parse("22/03/2015")).to eq(nil)
  end

  it "should parse dateTimes that match M/d/yyyy HH:mm correctly" do
    format = Csvlint::Csvw::DateFormat.new("M/d/yyyy HH:mm")
    expect(format.parse("2015-03-15T15:02:37")).to eql(nil)
    expect(format.parse("3/15/2015 15:02")[:dateTime]).to eql(DateTime.new(2015, 3, 15, 15, 2))
  end
end
