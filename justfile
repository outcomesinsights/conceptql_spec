test:
    bundle install --quiet
    mdl README.md

bundle-update *ARGS:
    bundle update {{ARGS}}
