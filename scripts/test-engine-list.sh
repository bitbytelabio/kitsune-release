#!/usr/bin/env bash
# Tests for engine-list.sh. No network, no secrets: check.yml runs it on every
# pull request.
#
#   scripts/test-engine-list.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/engine-list.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { echo "ok   $1"; }
flunk() { echo "FAIL $1" >&2; failures=$((failures + 1)); }
# expect NAME ACTUAL WANTED
expect() { if [ "$2" = "$3" ]; then pass "$1"; else flunk "$1: got $2, wanted $3"; fi; }

mirror="https://github.com/bitbytelabio/kitsune-release/releases/download"

ginko_155() {
  ENGINE=ginko PLATFORM=darwin-aarch64 VERSION=155.0.8059.31 \
  URL="$mirror/engine-ginko-155.0.8059.31/ginko-155.0.8059.31-darwin-aarch64.zip" \
  SHA=58176ba9b3e9cfd74029165bdf716c636e618af17a48bd905fe6d5f1552d901a \
  STRIP=apostate-155.0.8059.31-macos-arm64 \
  EXECUTABLE=Chromium.app/Contents/MacOS/Chromium \
  "$@"
}

kitsunebi_158() {
  ENGINE=kitsunebi PLATFORM=darwin-aarch64 VERSION=158.0.1-beta.41 \
  URL="$mirror/engine-kitsunebi-158.0.1-beta.41/kitsunebi-158.0.1-beta.41-darwin-aarch64.zip" \
  SHA=9038f86d666c9780b6fff199d488737b8596c01f24e3e517845a0ecfb0cf8add \
  EXECUTABLE=Camoufox.app/Contents/MacOS/camoufox \
  "$@"
}

# The list as published on 2026-11-07, after the two seeding runs.
cat > "$work/published.json" <<'JSON'
{
  "serial": 2,
  "engines": {
    "ginko": {
      "darwin-aarch64": [
        {
          "version": "155.0.8059.31",
          "url": "https://github.com/bitbytelabio/kitsune-release/releases/download/engine-ginko-155.0.8059.31/ginko-155.0.8059.31-darwin-aarch64.zip",
          "sha256": "58176ba9b3e9cfd74029165bdf716c636e618af17a48bd905fe6d5f1552d901a",
          "executable": "Chromium.app/Contents/MacOS/Chromium",
          "strip_prefix": "apostate-155.0.8059.31-macos-arm64"
        }
      ]
    },
    "kitsunebi": {
      "darwin-aarch64": [
        {
          "version": "158.0.1-beta.41",
          "url": "https://github.com/bitbytelabio/kitsune-release/releases/download/engine-kitsunebi-158.0.1-beta.41/kitsunebi-158.0.1-beta.41-darwin-aarch64.zip",
          "sha256": "9038f86d666c9780b6fff199d488737b8596c01f24e3e517845a0ecfb0cf8add",
          "executable": "Camoufox.app/Contents/MacOS/camoufox"
        }
      ]
    }
  }
}
JSON

# 1. The two seeding runs, from an empty list, give the published list.
list="$work/list.json"
echo '{"serial":0,"engines":{}}' > "$list"
ginko_155 "$script" add "$list"
kitsunebi_158 "$script" add "$list"
if diff <(jq -S . "$work/published.json") <(jq -S . "$list") >/dev/null; then
  pass "seeding from empty gives the published list"
else
  flunk "seeding from empty gives the published list"
fi

# 2. A newer build goes on top and the older one stays.
ginko_155 env VERSION=158.0.8127.18 STRIP=ginko-158.0.8127.18-macos-arm64 \
  MIN_APP=0.7.0 NOTES="Chromium 158" "$script" add "$list"
expect "serial goes up by one" "$(jq .serial "$list")" 3
expect "newest first" \
  "$(jq -r '.engines.ginko["darwin-aarch64"] | map(.version) | join(",")' "$list")" "158.0.8127.18,155.0.8059.31"
expect "optional fields are written when given" \
  "$(jq -r '.engines.ginko["darwin-aarch64"][0] | "\(.min_app) \(.notes)"' "$list")" "0.7.0 Chromium 158"
expect "optional fields are left out when empty" \
  "$(jq '.engines.ginko["darwin-aarch64"][1] | has("min_app") or has("notes")' "$list")" false
expect "other engines are untouched" \
  "$(jq '.engines.kitsunebi["darwin-aarch64"] | length' "$list")" 1

# 3. Adding a listed version again moves it to the top instead of repeating it.
ginko_155 "$script" add "$list"
expect "a repeated version moves to the top, once" \
  "$(jq -r '.engines.ginko["darwin-aarch64"] | map(.version) | join(",")' "$list")" "155.0.8059.31,158.0.8127.18"

# 4. What must be refused, and the list is not touched when it is.
before="$(cat "$list")"
refuse() {
  local name="$1"; shift
  if ginko_155 env "$@" "$script" add "$list" 2>/dev/null; then
    flunk "refuses $name"
  else
    pass "refuses $name"
  fi
}
refuse "an executable with .."        'EXECUTABLE=../Chromium'
refuse "an executable with .. inside" 'EXECUTABLE=Chromium.app/../../x'
refuse "an absolute executable"       'EXECUTABLE=/Applications/Chromium.app/Contents/MacOS/Chromium'
refuse "an executable with a backslash" 'EXECUTABLE=Chromium.app\Contents'
refuse "an empty executable"          'EXECUTABLE='
refuse "a strip_prefix of .."         'STRIP=..'
refuse "a strip_prefix ending in /"   'STRIP=ginko/'
refuse "a version with a slash"       'VERSION=1/2'
refuse "a version starting with a dot" 'VERSION=.1'
refuse "a short sha256"               'SHA=abc'
refuse "an uppercase sha256"          'SHA=58176BA9B3E9CFD74029165BDF716C636E618AF17A48BD905FE6D5F1552D901A'
refuse "a plain http url"             'URL=http://example.com/a.zip'
refuse "a min_app that is not x.y.z"  'MIN_APP=0.7'
refuse "an unknown engine"            'ENGINE=firefox'
refuse "another platform"             'PLATFORM=darwin-x86_64'
expect "a refused build leaves the list alone" "$(cat "$list")" "$before"

# 5. Names with spaces are fine: an app bundle is often called that.
if ginko_155 env 'EXECUTABLE=Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing' "$script" validate; then
  pass "accepts a path with spaces"
else
  flunk "accepts a path with spaces"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures failed" >&2
  exit 1
fi
echo "all passed"
