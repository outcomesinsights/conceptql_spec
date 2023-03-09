require "dotenv"
require "sequelizer"
require "conceptql"
require_relative "../lib/annotater"

Dotenv.load!

class Runner
  include Sequelizer

  attr_reader :cdb, :stmt
  def initialize(stmt)
    @stmt = stmt
    @cdb = ConceptQL::Database.new(db)
  end

  def run
    puts Annotater.new(cdb, stmt).annotate
  end
end

Runner.new(JSON.parse(ARGV[0])).run