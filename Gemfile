source "https://rubygems.org"

ruby "~> 4.0"

gem "sequelizer", github: "outcomesinsights/sequelizer", branch: "main"
gem "conceptql", github: "outcomesinsights/conceptql", branch: "main"

gem "mdl"

# conceptql/utils.rb requires pry-byebug unguarded, but conceptql declares it
# only as a development dependency, so the bundle must supply it.
gem "pry-byebug", "~> 3.12"

gem "pg", "~> 1.6"

gem "facets", "~> 3.2"
