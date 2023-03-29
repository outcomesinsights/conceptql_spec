#!/bin/bash

if [[ $1 == "--clean" ]]; then
  echo "Cleaning house"
  rm -rf .??????????????* possibilities
fi

bundle exec sequelizer config
bundle exec ruby exe/knit.rb possibilities.cql.md && \
doctoc --github --notitle possibilities.md && \
mdl possibilities.md