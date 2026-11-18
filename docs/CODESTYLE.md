# Code style

## Shell

- The entrypoint is POSIX `sh`: the image runs it with busybox, and CI runs its tests under dash,
  bash and busybox sh. Tests are bash.
- `set -eu` in the entrypoint, `set -euo pipefail` in tests. Every script passes `shellcheck`
  without a disable directive.
- A settings error is reported on stderr, prefixed with the script's name and naming the variable,
  and exits 2.
- Every external command a test stands in for is a script in the test's own `PATH`; the real
  network is never reached.

## Dockerfile

`hadolint` passes with `.hadolint.yaml`, whose every ignored rule carries its reason. A `RUN` does
not pipe: not every builder honours a `SHELL` with `pipefail`, so a failing first stage would go
unseen. A downloaded binary is checked against its publisher's signature or checksums before use.

## Markdown

`markdownlint-cli2` with `.markdownlint-cli2.jsonc` passes.

## Commits

Conventional commits; `cliff.toml` turns their subjects into `CHANGELOG.md`.
