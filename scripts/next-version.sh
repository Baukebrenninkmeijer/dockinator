#!/bin/bash
# Prints the next version tag from conventional commit subjects since the last v* tag,
# or nothing when no commit warrants a release.
#   feat: -> minor    fix:/perf: -> patch    type!: or "BREAKING CHANGE" -> major
# Usage: scripts/next-version.sh [major|minor|patch]   (an argument forces the level)
set -euo pipefail

cur="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo v0.0.0)"
range="$cur..HEAD"
git rev-parse -q --verify "refs/tags/$cur" >/dev/null || range="HEAD"

level="${1:-}"
if [[ -z "$level" ]]; then
  log="$(git log --format='%s%n%b%n--' "$range")"
  if grep -qE '^[a-z]+(\([^)]*\))?!:|^BREAKING[ -]CHANGE:' <<<"$log"; then level=major
  elif grep -qE '^feat(\([^)]*\))?:' <<<"$log"; then level=minor
  elif grep -qE '^(fix|perf)(\([^)]*\))?:' <<<"$log"; then level=patch
  else exit 0
  fi
fi

IFS=. read -r major minor patch <<<"${cur#v}"
case "$level" in
  major) echo "v$((major + 1)).0.0" ;;
  minor) echo "v$major.$((minor + 1)).0" ;;
  patch) echo "v$major.$minor.$((patch + 1))" ;;
  *) echo "unknown level: $level" >&2; exit 1 ;;
esac
