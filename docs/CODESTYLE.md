# Code style

## Dockerfile

`hadolint` passes with `.hadolint.yaml`, whose every ignored rule carries its reason. A `RUN` does
not pipe: not every builder honours a `SHELL` with `pipefail`, so a failing first stage would go
unseen. A downloaded binary is checked against its publisher's signature or checksums before use.

## Markdown

`markdownlint-cli2` with `.markdownlint-cli2.jsonc` passes.

## Commits

Conventional commits; `cliff.toml` turns their subjects into `CHANGELOG.md`.
