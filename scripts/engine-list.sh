#!/usr/bin/env bash
# The signed engine list, without the signing: check one build's details, and
# put that build at the top of the list.
#
#   scripts/engine-list.sh validate
#   scripts/engine-list.sh add engines.json
#
# Everything comes from the environment, as engine.yml passes it:
#
#   ENGINE      ginko or kitsunebi
#   PLATFORM    darwin-aarch64, the only key the agent reads
#   VERSION     for ginko, the Chromium version: the agent reports it to sites
#   URL         https; to validate, where the zip is now; to add, the mirror
#   SHA         SHA-256 of the zip
#   EXECUTABLE  path inside the install directory
#   STRIP       optional: the zip's single top-level directory
#   MIN_APP     optional: the oldest Kitsune that runs it, x.y.z
#   NOTES       optional: what changed
#
# The list is read by crates/kitsune-agent/src/engines.rs in kitsune-browser.
# Builds are newest first, and the agent compares versions only as strings, so
# the order of this list is the order of the runs that made it. Adding a version
# that is already listed moves it to the top rather than listing it twice.
#
# STRIP and EXECUTABLE are joined onto a directory on every Mac that installs
# the build, so they must stay inside it: relative, no `..`, no backslash.
set -euo pipefail

fail() { echo "::error::$*" >&2; exit 1; }

# One or more segments of letters, digits, space and `._+-`, none of them `.`
# or `..`.
relative_path() {
  local segment='[A-Za-z0-9._+ -]+'
  [[ "$1" =~ ^$segment(/$segment)*$ ]] || return 1
  [[ "/$1/" != */./* && "/$1/" != */../* ]]
}

validate() {
  case "${ENGINE:-}" in ginko|kitsunebi) ;; *) fail "bad engine: ${ENGINE:-}" ;; esac
  [[ "${PLATFORM:-}" == darwin-aarch64 ]] || fail "bad platform: ${PLATFORM:-}"
  [[ "${VERSION:-}" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ ]] || fail "bad version"
  [[ "${SHA:-}" =~ ^[0-9a-f]{64}$ ]] || fail "bad sha256"
  [[ "${URL:-}" == https://* ]] || fail "the url must be https"
  relative_path "${EXECUTABLE:-}" || fail "bad executable: it must be a relative path inside the install directory"
  [[ -z "${STRIP:-}" ]] || relative_path "$STRIP" || fail "bad strip_prefix: it must be a relative path"
  [[ -z "${MIN_APP:-}" || "$MIN_APP" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "bad min_app"
}

add() {
  local file="$1"
  validate
  [[ -f "$file" ]] || fail "$file does not exist"
  jq \
    --arg engine "$ENGINE" --arg platform "$PLATFORM" \
    --arg version "$VERSION" --arg url "$URL" --arg sha "$SHA" \
    --arg strip "${STRIP:-}" --arg executable "$EXECUTABLE" \
    --arg min "${MIN_APP:-}" --arg notes "${NOTES:-}" \
    '.serial += 1
     | .engines[$engine][$platform] =
       ([{version: $version, url: $url, sha256: $sha, executable: $executable}
         + (if $strip == "" then {} else {strip_prefix: $strip} end)
         + (if $min == "" then {} else {min_app: $min} end)
         + (if $notes == "" then {} else {notes: $notes} end)]
        + ((.engines[$engine][$platform] // []) | map(select(.version != $version))))' \
    "$file" > "$file.next"
  mv "$file.next" "$file"
}

case "${1:-}" in
  validate) validate ;;
  add) add "${2:?add needs the list file}" ;;
  *) echo "usage: $0 validate | add <engines.json>" >&2; exit 2 ;;
esac
