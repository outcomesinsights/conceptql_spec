#!/bin/bash

while inotifywait -e close_write README.cql.md ; do
  ./prep_readme.sh ; 
  pandoc README.md > README.html
done