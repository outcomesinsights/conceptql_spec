require "dotenv"
require_relative "../lib/knitter"

Dotenv.load!

Knitter.new("README.cql.md").knit