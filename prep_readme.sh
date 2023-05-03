#!/bin/bash

if [[ $1 == "--clean" ]]; then
  echo "Cleaning house"
  rm -rf .??????????????* README
fi

bundle exec sequelizer config
bundle exec ruby exe/knit.rb README.cql.md && \
doctoc --github --notitle README.md && \
bundle exec mdl README.md