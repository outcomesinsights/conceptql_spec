test:
    bundle install --quiet
    mdl README.md

bundle-update *ARGS:
    bundle update {{ARGS}}

# Start the test-data database that README.md's results come from (see .env.example)
db-up:
    docker compose up -d --wait test_data

db-down:
    docker compose down

# Regenerate README.md from README.cql.md; needs CONCEPTQL_DIAGRAM_CLI (Appendix D)
readme *ARGS: db-up
    ./prep_readme.sh {{ARGS}}
