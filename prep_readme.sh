#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ -z "${CONCEPTQL_DIAGRAM_CLI:-}" ]]; then
  echo "CONCEPTQL_DIAGRAM_CLI is not set: point it at the Jigsaw Diagram Editor's" >&2
  echo "frontend/lib/conceptql-diagram/cli/bin/conceptql-diagram.js (see Appendix D of README.cql.md)." >&2
  exit 1
fi

# Run Ruby through mise so the version pinned in mise.toml is the one that
# runs, even when another Ruby's bin directory sits earlier on PATH.
if command -v mise >/dev/null; then
  ruby_env=(mise exec --)
else
  ruby_env=()
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

"${ruby_env[@]}" ruby --version
"${ruby_env[@]}" bundle exec sequelizer config
"${ruby_env[@]}" bundle exec ruby exe/knit.rb README.cql.md
"${doctoc[@]}" --github --notitle README.md
"${ruby_env[@]}" bundle exec mdl README.md
