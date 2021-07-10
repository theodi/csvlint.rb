require 'csvlint'
require 'stringio'
require 'json'

csv_schema = <<JSON
{
  "@context": "http://www.w3.org/ns/csvw",
  "null": true,
  "tables": [{
  "url1": "naplan_student_csv_csvw.csv",
  "tableSchema": {
     "columns": [
      {"name": "LocalId", "datatype": {"base": "string"}},
      {"name": "FamilyName", "datatype": {"base": "string"}},
      {"name": "GivenName", "datatype": {"base": "string"}},
      {"name": "Homegroup", "datatype": {"base": "string"}},
      {"name": "ClassCode", "datatype": {"base": "string"}},
      {"name": "ASLSchoolId", "datatype": {"base": "string"}},
      {"name": "SchoolLocalId", "datatype": {"base": "string"}},
      {"name": "LocalCampusId", "datatype": {"base": "string"}},
      {"name": "EmailAddress", "datatype": {"base": "string"}},
      {"name": "ReceiveAdditionalInformation", "datatype": {"base": "boolean", "format": "Y|N"}},
      {"name": "StaffSchoolRole", "datatype": {"base": "string"}}
    ]}}]
}
JSON
require 'json'
csv_schema = Csvlint::Schema.from_csvw_metadata("http://example.com", JSON.parse(csv_schema))
csv = <<CSV
LocalId,GivenName,FamilyName,Homegroup,ClassCode,ASLSchoolId,SchoolLocalId,LocalCampusId,EmailAddress,ReceiveAdditionalInformation,StaffSchoolRole
fjghh371,Treva,Seefeldt,7E,"7D,7E",knptb460,046129,01,tseefeldt@example.com,Y,teacher
CSV

validator = Csvlint::Validator.new( StringIO.new( csv ) , {}, csv_schema)
puts  "a" if validator.valid?
validator.errors.each {|e| puts "Row: #{e.row} Col: #{e.column}, Category #{e.category}: Type #{e.type}, Content #{e.content}, Constraints: #{e.constraints}" }
