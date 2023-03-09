require "conceptql"
require_relative "fake_annotater"
    
class Annotater
  attr_reader :cdb, :stmt

  def initialize(cdb, stmt)
    @stmt = stmt
    @cdb = cdb
  end
  
  def annotate
    query(stmt).annotate
  rescue
    puts $!.message
    puts $!.backtrace.join("\n")
    p stmt
    FakeAnnotater.new(stmt).annotate
  end

  def query(stmt)
    cdb.query(stmt)
  end
end