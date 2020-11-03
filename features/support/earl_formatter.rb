require "rdf"
require "rdf/turtle"

class EarlFormatter
  def initialize(step_mother, io, options)
    output = RDF::Resource.new("")
    @graph = RDF::Graph.new
    @graph << [CSVLINT, RDF.type, RDF::DOAP.Project]
    @graph << [CSVLINT, RDF.type, EARL.TestSubject]
    @graph << [CSVLINT, RDF.type, EARL.Software]
    @graph << [CSVLINT, RDF::DOAP.name, "csvlint"]
    @graph << [CSVLINT, RDF::DC.title, "csvlint"]
    @graph << [CSVLINT, RDF::DOAP.description, "CSV validator"]
    @graph << [CSVLINT, RDF::DOAP.homepage, RDF::Resource.new("https://github.com/theodi/csvlint.rb")]
    @graph << [CSVLINT, RDF::DOAP.license, RDF::Resource.new("https://raw.githubusercontent.com/theodi/csvlint.rb/master/LICENSE.md")]
    @graph << [CSVLINT, RDF::DOAP["programming-language"], "Ruby"]
    @graph << [CSVLINT, RDF::DOAP.implements, RDF::Resource.new("http://www.w3.org/TR/tabular-data-model/")]
    @graph << [CSVLINT, RDF::DOAP.implements, RDF::Resource.new("http://www.w3.org/TR/tabular-metadata/")]
    @graph << [CSVLINT, RDF::DOAP.developer, ODI]
    @graph << [CSVLINT, RDF::DOAP.maintainer, ODI]
    @graph << [CSVLINT, RDF::DOAP.documenter, ODI]
    @graph << [CSVLINT, RDF::FOAF.maker, ODI]
    @graph << [CSVLINT, RDF::DC.creator, ODI]
    @graph << [output, RDF::FOAF["primaryTopic"], CSVLINT]
    @graph << [output, RDF::DC.issued, DateTime.now]
    @graph << [output, RDF::FOAF.maker, ODI]
    @graph << [ODI, RDF.type, RDF::FOAF.Organization]
    @graph << [ODI, RDF.type, EARL.Assertor]
    @graph << [ODI, RDF::FOAF.name, "Open Data Institute"]
    @graph << [ODI, RDF::FOAF.homepage, "https://theodi.org/"]
  end

  def scenario_name(keyword, name, file_colon_line, source_indent)
    @test = RDF::Resource.new("http://www.w3.org/2013/csvw/tests/#{name.split(" ")[0]}")
  end

  def after_steps(steps)
    passed = true
    steps.each do |s|
      passed = false unless s.status == :passed
    end
    a = RDF::Node.new
    @graph << [a, RDF.type, EARL.Assertion]
    @graph << [a, EARL.assertedBy, ODI]
    @graph << [a, EARL.subject, CSVLINT]
    @graph << [a, EARL.test, @test]
    @graph << [a, EARL.mode, EARL.automatic]
    r = RDF::Node.new
    @graph << [a, EARL.result, r]
    @graph << [r, RDF.type, EARL.TestResult]
    @graph << [r, EARL.outcome, passed ? EARL.passed : EARL.failed]
    @graph << [r, RDF::DC.date, DateTime.now]
  end

  def after_features(features)
    RDF::Writer.for(:ttl).open("csvlint-earl.ttl", {prefixes: {"earl" => EARL}, standard_prefixes: true, canonicalize: true, literal_shorthand: true}) do |writer|
      writer << @graph
    end
  end

  private

  EARL = RDF::Vocabulary.new("http://www.w3.org/ns/earl#")
  ODI = RDF::Resource.new("https://theodi.org/")
  CSVLINT = RDF::Resource.new("https://github.com/theodi/csvlint.rb")
end
