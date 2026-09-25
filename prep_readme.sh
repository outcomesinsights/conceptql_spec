#!/bin/bash
set -euo pipefail

if [[ -z "${CONCEPTQL_DIAGRAM_CLI:-}" ]]; then
  echo "CONCEPTQL_DIAGRAM_CLI is not set: point it at the Jigsaw Diagram Editor's" >&2
  echo "frontend/lib/conceptql-diagram/cli/bin/conceptql-diagram.js (see Appendix D of README.cql.md)." >&2
  exit 1
fi

if [[ ${1:-} == "--clean" ]]; then
  echo "Cleaning house"
  rm -rf .??????????????* README
fi

if command -v doctoc >/dev/null; then
  doctoc=(doctoc)
else
  doctoc=(npx --yes doctoc)
fi

bundle exec sequelizer config
bundle exec ruby exe/knit.rb README.cql.md
"${doctoc[@]}" --github --notitle README.md
bundle exec mdl README.md
