require "spec_helper"

describe Csvlint::Csvw::NumberFormat do
  it "should correctly parse #,##0.##" do
    format = Csvlint::Csvw::NumberFormat.new("#,##0.##")
    expect(format.pattern).to eq("#,##0.##")
    expect(format.prefix).to eq("")
    expect(format.numeric_part).to eq("#,##0.##")
    expect(format.suffix).to eq("")
    expect(format.grouping_separator).to eq(",")
    expect(format.decimal_separator).to eq(".")
    expect(format.primary_grouping_size).to eq(3)
    expect(format.secondary_grouping_size).to eq(3)
    expect(format.fractional_grouping_size).to eq(0)
  end

  it "should correctly parse ###0.#####" do
    format = Csvlint::Csvw::NumberFormat.new("###0.#####")
    expect(format.primary_grouping_size).to eq(0)
    expect(format.secondary_grouping_size).to eq(0)
    expect(format.fractional_grouping_size).to eq(0)
  end

  it "should correctly parse ###0.0000#" do
    format = Csvlint::Csvw::NumberFormat.new("###0.0000#")
    expect(format.primary_grouping_size).to eq(0)
    expect(format.secondary_grouping_size).to eq(0)
    expect(format.fractional_grouping_size).to eq(0)
  end

  it "should correctly parse #,##,###,####" do
    format = Csvlint::Csvw::NumberFormat.new("#,##,###,####")
    expect(format.primary_grouping_size).to eq(4)
    expect(format.secondary_grouping_size).to eq(3)
    expect(format.fractional_grouping_size).to eq(0)
  end

  it "should correctly parse #,##0.###,#" do
    format = Csvlint::Csvw::NumberFormat.new("#,##0.###,#")
    expect(format.primary_grouping_size).to eq(3)
    expect(format.secondary_grouping_size).to eq(3)
    expect(format.fractional_grouping_size).to eq(3)
  end

  it "should correctly parse #0.###E#0" do
    format = Csvlint::Csvw::NumberFormat.new("#0.###E#0")
    expect(format.prefix).to eq("")
    expect(format.numeric_part).to eq("#0.###E#0")
    expect(format.suffix).to eq("")
  end

  it "should match numbers that match ##0 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("##0")
    expect(format.match("1")).to eq(true)
    expect(format.match("12")).to eq(true)
    expect(format.match("123")).to eq(true)
    expect(format.match("1234")).to eq(true)
    expect(format.match("1,234")).to eq(false)
    expect(format.match("123.4")).to eq(false)
  end

  it "should match numbers that match #,#00 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#,#00")
    expect(format.match("1")).to eq(false)
    expect(format.match("12")).to eq(true)
    expect(format.match("123")).to eq(true)
    expect(format.match("1234")).to eq(false)
    expect(format.match("1,234")).to eq(true)
    expect(format.match("1,234,568")).to eq(true)
    expect(format.match("12,34,568")).to eq(false)
    expect(format.match("12,34")).to eq(false)
    expect(format.match("123.4")).to eq(false)
  end

  it "should match numbers that match #,000 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#,000")
    expect(format.match("1")).to eq(false)
    expect(format.match("12")).to eq(false)
    expect(format.match("123")).to eq(true)
    expect(format.match("1234")).to eq(false)
    expect(format.match("1,234")).to eq(true)
    expect(format.match("1,234,568")).to eq(true)
    expect(format.match("12,34,568")).to eq(false)
    expect(format.match("12,34")).to eq(false)
    expect(format.match("123.4")).to eq(false)
  end

  it "should match numbers that match #,##,#00 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#,##,#00")
    expect(format.match("1")).to eq(false)
    expect(format.match("12")).to eq(true)
    expect(format.match("123")).to eq(true)
    expect(format.match("1234")).to eq(false)
    expect(format.match("1,234")).to eq(true)
    expect(format.match("1,234,568")).to eq(false)
    expect(format.match("12,34,568")).to eq(true)
    expect(format.match("12,34")).to eq(false)
    expect(format.match("123.4")).to eq(false)
  end

  it "should match numbers that match #0.# correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#0.#")
    expect(format.match("1")).to eq(true)
    expect(format.match("12")).to eq(true)
    expect(format.match("12.3")).to eq(true)
    expect(format.match("12.34")).to eq(false)
    expect(format.match("1234.5")).to eq(true)
    expect(format.match("1,234.5")).to eq(false)
  end

  it "should match numbers that match #0.0 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#0.0")
    expect(format.match("1")).to eq(false)
    expect(format.match("12")).to eq(false)
    expect(format.match("12.3")).to eq(true)
    expect(format.match("12.34")).to eq(false)
    expect(format.match("1234.5")).to eq(true)
    expect(format.match("1,234.5")).to eq(false)
  end

  it "should match numbers that match #0.0# correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#0.0#")
    expect(format.match("1")).to eq(false)
    expect(format.match("12")).to eq(false)
    expect(format.match("12.3")).to eq(true)
    expect(format.match("12.34")).to eq(true)
    expect(format.match("12.345")).to eq(false)
  end

  it "should match numbers that match #0.0#,# correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#0.0#,#")
    expect(format.match("1")).to eq(false)
    expect(format.match("12.3")).to eq(true)
    expect(format.match("12.34")).to eq(true)
    expect(format.match("12.345")).to eq(false)
    expect(format.match("12.34,5")).to eq(true)
    expect(format.match("12.34,56")).to eq(false)
    expect(format.match("12.34,567")).to eq(false)
    expect(format.match("12.34,56,7")).to eq(false)
  end

  it "should match numbers that match #0.###E#0 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#0.###E#0")
    expect(format.match("1")).to eq(false)
    expect(format.match("12.3")).to eq(false)
    expect(format.match("12.34")).to eq(false)
    expect(format.match("12.3E4")).to eq(true)
    expect(format.match("12.3E45")).to eq(true)
    expect(format.match("12.34E5")).to eq(true)
  end

  it "should parse numbers that match ##0 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("##0")
    expect(format.parse("-1")).to eql(-1)
    expect(format.parse("1")).to eql(1)
    expect(format.parse("12")).to eql(12)
    expect(format.parse("123")).to eql(123)
    expect(format.parse("1234")).to eql(1234)
    expect(format.parse("1,234")).to eq(nil)
    expect(format.parse("123.4")).to eq(nil)
  end

  it "should parse numbers that match #,#00 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#,#00")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("12")).to eql(12)
    expect(format.parse("123")).to eql(123)
    expect(format.parse("1234")).to eq(nil)
    expect(format.parse("1,234")).to eql(1234)
    expect(format.parse("1,234,568")).to eql(1234568)
    expect(format.parse("12,34,568")).to eq(nil)
    expect(format.parse("12,34")).to eq(nil)
    expect(format.parse("123.4")).to eq(nil)
  end

  it "should parse numbers that match #,000 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#,000")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("12")).to eq(nil)
    expect(format.parse("123")).to eql(123)
    expect(format.parse("1234")).to eq(nil)
    expect(format.parse("1,234")).to eql(1234)
    expect(format.parse("1,234,568")).to eql(1234568)
    expect(format.parse("12,34,568")).to eq(nil)
    expect(format.parse("12,34")).to eq(nil)
    expect(format.parse("123.4")).to eq(nil)
  end

  it "should parse numbers that match #0,000 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#0,000")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("12")).to eq(nil)
    expect(format.parse("123")).to eql(nil)
    expect(format.parse("1234")).to eq(nil)
    expect(format.parse("1,234")).to eql(1234)
    expect(format.parse("1,234,568")).to eql(1234568)
    expect(format.parse("12,34,568")).to eq(nil)
    expect(format.parse("12,34")).to eq(nil)
    expect(format.parse("123.4")).to eq(nil)
  end

  it "should parse numbers that match #,##,#00 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#,##,#00")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("12")).to eql(12)
    expect(format.parse("123")).to eql(123)
    expect(format.parse("1234")).to eq(nil)
    expect(format.parse("1,234")).to eql(1234)
    expect(format.parse("12,345")).to eql(12345)
    expect(format.parse("1,234,568")).to eq(nil)
    expect(format.parse("12,34,568")).to eql(1234568)
    expect(format.parse("12,34")).to eq(nil)
    expect(format.parse("123.4")).to eq(nil)
  end

  it "should parse numbers that match #,00,000 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#,00,000")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("12")).to eql(nil)
    expect(format.parse("123")).to eql(nil)
    expect(format.parse("1234")).to eq(nil)
    expect(format.parse("1,234")).to eql(nil)
    expect(format.parse("12,345")).to eql(12345)
    expect(format.parse("1,234,568")).to eq(nil)
    expect(format.parse("1,34,568")).to eql(134568)
    expect(format.parse("12,34,568")).to eql(1234568)
    expect(format.parse("1,23,45,678")).to eql(12345678)
    expect(format.parse("12,34")).to eq(nil)
    expect(format.parse("123.4")).to eq(nil)
  end

  it "should parse numbers that match 0,00,000 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("0,00,000")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("12")).to eql(nil)
    expect(format.parse("123")).to eql(nil)
    expect(format.parse("1234")).to eq(nil)
    expect(format.parse("1,234")).to eql(nil)
    expect(format.parse("12,345")).to eql(nil)
    expect(format.parse("1,234,568")).to eq(nil)
    expect(format.parse("1,34,568")).to eql(134568)
    expect(format.parse("12,34,568")).to eql(1234568)
    expect(format.parse("1,23,45,678")).to eql(12345678)
    expect(format.parse("12,34")).to eq(nil)
    expect(format.parse("123.4")).to eq(nil)
  end

  it "should parse numbers that match #0.# correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#0.#")
    expect(format.parse("1")).to eql(1.0)
    expect(format.parse("12")).to eql(12.0)
    expect(format.parse("12.3")).to eql(12.3)
    expect(format.parse("12.34")).to eq(nil)
    expect(format.parse("1234.5")).to eql(1234.5)
    expect(format.parse("1,234.5")).to eq(nil)
  end

  it "should parse numbers that match #0.0 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#0.0")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("12")).to eq(nil)
    expect(format.parse("12.3")).to eql(12.3)
    expect(format.parse("12.34")).to eq(nil)
    expect(format.parse("1234.5")).to eql(1234.5)
    expect(format.parse("1,234.5")).to eq(nil)
  end

  it "should parse numbers that match #0.0# correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#0.0#")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("12")).to eq(nil)
    expect(format.parse("12.3")).to eql(12.3)
    expect(format.parse("12.34")).to eql(12.34)
    expect(format.parse("12.345")).to eq(nil)
  end

  it "should parse numbers that match #0.0#,# correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#0.0#,#")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("12.3")).to eql(12.3)
    expect(format.parse("12.34")).to eql(12.34)
    expect(format.parse("12.345")).to eq(nil)
    expect(format.parse("12.34,5")).to eql(12.345)
    expect(format.parse("12.34,56")).to eql(nil)
    expect(format.parse("12.34,567")).to eq(nil)
    expect(format.parse("12.34,56,7")).to eql(nil)
  end

  it "should parse numbers that match 0.0##,### correctly" do
    format = Csvlint::Csvw::NumberFormat.new("0.0##,###")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("12.3")).to eql(12.3)
    expect(format.parse("12.34")).to eql(12.34)
    expect(format.parse("12.345")).to eq(12.345)
    expect(format.parse("12.3456")).to eql(nil)
    expect(format.parse("12.345,6")).to eql(12.3456)
    expect(format.parse("12.34,56")).to eql(nil)
    expect(format.parse("12.345,67")).to eq(12.34567)
    expect(format.parse("12.345,678")).to eql(12.345678)
    expect(format.parse("12.345,67,8")).to eql(nil)
  end

  it "should parse numbers that match 0.###,### correctly" do
    format = Csvlint::Csvw::NumberFormat.new("0.###,###")
    expect(format.parse("1")).to eq(1)
    expect(format.parse("12.3")).to eql(12.3)
    expect(format.parse("12.34")).to eql(12.34)
    expect(format.parse("12.345")).to eq(12.345)
    expect(format.parse("12.3456")).to eql(nil)
    expect(format.parse("12.345,6")).to eql(12.3456)
    expect(format.parse("12.34,56")).to eql(nil)
    expect(format.parse("12.345,67")).to eq(12.34567)
    expect(format.parse("12.345,678")).to eql(12.345678)
    expect(format.parse("12.345,67,8")).to eql(nil)
  end

  it "should parse numbers that match 0.000,### correctly" do
    format = Csvlint::Csvw::NumberFormat.new("0.000,###")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("12.3")).to eql(nil)
    expect(format.parse("12.34")).to eql(nil)
    expect(format.parse("12.345")).to eq(12.345)
    expect(format.parse("12.3456")).to eql(nil)
    expect(format.parse("12.345,6")).to eql(12.3456)
    expect(format.parse("12.34,56")).to eql(nil)
    expect(format.parse("12.345,67")).to eq(12.34567)
    expect(format.parse("12.345,678")).to eql(12.345678)
    expect(format.parse("12.345,67,8")).to eql(nil)
  end

  it "should parse numbers that match 0.000,0# correctly" do
    format = Csvlint::Csvw::NumberFormat.new("0.000,0#")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("12.3")).to eql(nil)
    expect(format.parse("12.34")).to eql(nil)
    expect(format.parse("12.345")).to eq(nil)
    expect(format.parse("12.3456")).to eql(nil)
    expect(format.parse("12.345,6")).to eql(12.3456)
    expect(format.parse("12.34,56")).to eql(nil)
    expect(format.parse("12.345,67")).to eq(12.34567)
    expect(format.parse("12.345,678")).to eql(nil)
    expect(format.parse("12.345,67,8")).to eql(nil)
  end

  it "should parse numbers that match 0.000,0## correctly" do
    format = Csvlint::Csvw::NumberFormat.new("0.000,0##")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("12.3")).to eql(nil)
    expect(format.parse("12.34")).to eql(nil)
    expect(format.parse("12.345")).to eq(nil)
    expect(format.parse("12.3456")).to eql(nil)
    expect(format.parse("12.345,6")).to eql(12.3456)
    expect(format.parse("12.34,56")).to eql(nil)
    expect(format.parse("12.345,67")).to eq(12.34567)
    expect(format.parse("12.345,678")).to eql(12.345678)
    expect(format.parse("12.345,67,8")).to eql(nil)
  end

  it "should parse numbers that match 0.000,000 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("0.000,000")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("12.3")).to eql(nil)
    expect(format.parse("12.34")).to eql(nil)
    expect(format.parse("12.345")).to eq(nil)
    expect(format.parse("12.3456")).to eql(nil)
    expect(format.parse("12.345,6")).to eql(nil)
    expect(format.parse("12.34,56")).to eql(nil)
    expect(format.parse("12.345,67")).to eq(nil)
    expect(format.parse("12.345,678")).to eql(12.345678)
    expect(format.parse("12.345,67,8")).to eql(nil)
  end

  it "should parse numbers that match #0.###E#0 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("#0.###E#0")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("12.3")).to eq(nil)
    expect(format.parse("12.34")).to eq(nil)
    expect(format.parse("12.3E4")).to eql(12.3E4)
    expect(format.parse("12.3E45")).to eql(12.3E45)
    expect(format.parse("12.34E5")).to eql(12.34E5)
  end

  it "should parse numbers that match %000 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("%000")
    expect(format.parse("%001")).to eq(0.01)
    expect(format.parse("%012")).to eq(0.12)
    expect(format.parse("%123")).to eq(1.23)
    expect(format.parse("%1234")).to eq(12.34)
  end

  it "should parse numbers that match -0 correctly" do
    format = Csvlint::Csvw::NumberFormat.new("-0")
    expect(format.parse("1")).to eq(nil)
    expect(format.parse("-1")).to eq(-1)
    expect(format.parse("-12")).to eq(-12)
  end

  it "should parse numbers normally when there is no pattern" do
    format = Csvlint::Csvw::NumberFormat.new
    expect(format.parse("1")).to eql(1)
    expect(format.parse("-1")).to eql(-1)
    expect(format.parse("12.3")).to eql(12.3)
    expect(format.parse("12.34")).to eql(12.34)
    expect(format.parse("12.3E4")).to eql(12.3E4)
    expect(format.parse("12.3E45")).to eql(12.3E45)
    expect(format.parse("12.34E5")).to eql(12.34E5)
    expect(format.parse("12.34e5")).to eql(12.34E5)
    expect(format.parse("-12.34")).to eql(-12.34)
    expect(format.parse("1,234")).to eq(nil)
    expect(format.parse("NaN").nan?).to eq(true)
    expect(format.parse("INF")).to eql(Float::INFINITY)
    expect(format.parse("-INF")).to eql(-Float::INFINITY)
    expect(format.parse("123456.789F10")).to eq(nil)
  end

  it "should parse numbers including grouping separators when they are specified" do
    format = Csvlint::Csvw::NumberFormat.new(nil, ",")
    expect(format.parse("1")).to eql(1)
    expect(format.parse("12.3")).to eql(12.3)
    expect(format.parse("12.34")).to eql(12.34)
    expect(format.parse("12.3E4")).to eql(12.3E4)
    expect(format.parse("12.3E45")).to eql(12.3E45)
    expect(format.parse("12.34E5")).to eql(12.34E5)
    expect(format.parse("1,234")).to eql(1234)
    expect(format.parse("1,234,567")).to eql(1234567)
    expect(format.parse("1,,234")).to eq(nil)
    expect(format.parse("NaN").nan?).to eq(true)
    expect(format.parse("INF")).to eql(Float::INFINITY)
    expect(format.parse("-INF")).to eql(-Float::INFINITY)
  end

  it "should parse numbers including decimal separators when they are specified" do
    format = Csvlint::Csvw::NumberFormat.new(nil, " ", ",")
    expect(format.parse("1")).to eql(1)
    expect(format.parse("12,3")).to eql(12.3)
    expect(format.parse("12,34")).to eql(12.34)
    expect(format.parse("12,3E4")).to eql(12.3E4)
    expect(format.parse("12,3E45")).to eql(12.3E45)
    expect(format.parse("12,34E5")).to eql(12.34E5)
    expect(format.parse("1 234")).to eql(1234)
    expect(format.parse("1 234 567")).to eql(1234567)
    expect(format.parse("1  234")).to eq(nil)
  end
end
