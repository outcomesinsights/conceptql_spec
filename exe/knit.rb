require "dotenv"
require_relative "../lib/knitter"

Dotenv.load!

Knitter.new(ARGV[0]).knit