#!/usr/bin/env bash
# Runs the entrypoint against stand-ins for ghproj and curl on PATH; openssl and jq are the real ones.
# Usage: tests/entrypoint.sh [shell], the shell that runs the script under test (default: sh);
# a shell of several words, such as "busybox sh", is split on spaces.
set -euo pipefail

read -ra shell <<< "${1:-sh}"
entrypoint=$(cd "$(dirname "$0")/.." && pwd)/entrypoint
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

mkdir "$work/bin"
cat > "$work/bin/ghproj" <<'SH'
#!/bin/sh
echo "$* token=$GITHUB_TOKEN" >> "$WORK/ghproj.log"
exit "${GHPROJ_STATUS:-0}"
SH
cat > "$work/bin/curl" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >> "$WORK/curl.log"
[ -z "${CURL_FAILS:-}" ] || exit 22
echo '{"token":"ghs_minted","expires_at":"2099-01-01T00:00:00Z"}'
SH
chmod +x "$work/bin/ghproj" "$work/bin/curl"
openssl genrsa -out "$work/app.pem" 2048 2>/dev/null
openssl rsa -in "$work/app.pem" -pubout -out "$work/app.pub" 2>/dev/null
app=(GITHUB_APP_ID=12345 GITHUB_APP_INSTALLATION_ID=678 GITHUB_APP_PRIVATE_KEY_FILE="$work/app.pem")

run() {
  rm -f "$work"/*.log "$work/out"
  status=0
  env -i PATH="$work/bin:$PATH" WORK="$work" "$@" "${shell[@]}" "$entrypoint" > "$work/out" 2>&1 || status=$?
}

expect() {
  local name=$1
  shift
  if "$@"; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    sed 's/^/     /' "$work/out" "$work"/*.log 2>/dev/null || true
    failures=$((failures + 1))
  fi
}

not() { ! "$@"; }

run GITHUB_TOKEN=static
expect "runs ghproj add once with a static token" grep -qx "add token=static" "$work/ghproj.log"
expect "asks for no token when one is given" not test -e "$work/curl.log"
expect "exits 0 when ghproj does" test "$status" -eq 0

run GITHUB_TOKEN=static GHPROJ_STATUS=3
expect "exits with ghproj's status" test "$status" -eq 3

run
expect "refuses to start without credentials" test "$status" -eq 2
expect "names the credential settings" grep -q GITHUB_APP_ID "$work/out"
expect "does not run ghproj without credentials" not test -e "$work/ghproj.log"

run GITHUB_APP_ID=12345 GITHUB_APP_INSTALLATION_ID=678 GITHUB_APP_PRIVATE_KEY_FILE="$work/missing.pem"
expect "refuses a private key file it cannot read" test "$status" -eq 2
expect "names the private key setting" grep -q GITHUB_APP_PRIVATE_KEY_FILE "$work/out"

run "${app[@]}" CURL_FAILS=1
expect "exits 1 when no installation token comes back" test "$status" -eq 1
expect "does not run ghproj without a token" not test -e "$work/ghproj.log"
expect "says which settings to check when no token comes back" grep -q GITHUB_APP_INSTALLATION_ID "$work/out"

run "${app[@]}"
expect "hands ghproj the minted installation token" grep -qx "add token=ghs_minted" "$work/ghproj.log"
expect "asks GitHub for the token of the configured installation" \
  grep -qx "https://api.github.com/app/installations/678/access_tokens" "$work/curl.log"

b64url_decode() {
  local s
  s=$(printf '%s' "$1" | tr -- '-_' '+/')
  while [ $((${#s} % 4)) -ne 0 ]; do s="$s="; done
  printf '%s' "$s" | openssl base64 -d -A
}
jwt=$(sed -n 's/^Authorization: Bearer //p' "$work/curl.log" | head -n 1)
IFS=. read -r header payload signature <<< "$jwt"
printf '%s.%s' "$header" "$payload" > "$work/signed"
b64url_decode "$signature" > "$work/signature"
expect "signs the JWT with the app's private key" \
  openssl dgst -sha256 -verify "$work/app.pub" -signature "$work/signature" "$work/signed"
claims=$(b64url_decode "$payload")
expect "issues the JWT for the configured app" test "$(jq -r .iss <<< "$claims")" = 12345
expect "keeps the JWT within GitHub's ten-minute limit" \
  test $(($(jq .exp <<< "$claims") - $(jq .iat <<< "$claims"))) -le 600

[ "$failures" -eq 0 ] || { echo "$failures failed"; exit 1; }
