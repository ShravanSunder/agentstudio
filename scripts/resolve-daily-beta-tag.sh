#!/usr/bin/env bash
set -euo pipefail

candidate_input="${1:?usage: resolve-daily-beta-tag.sh <candidate-sha> <run-number>}"
run_number="${2:?missing run number}"

if [[ ! "$run_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "run number must be a positive integer" >&2
  exit 1
fi

if ! candidate_sha="$(git rev-parse --verify "${candidate_input}^{commit}" 2>/dev/null)"; then
  echo "candidate commit does not exist: $candidate_input" >&2
  exit 1
fi

existing_beta_tag="$(
  git tag --points-at "$candidate_sha" --sort=-v:refname |
    grep -E '^v[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$' |
    head -1 || true
)"

if [[ -n "$existing_beta_tag" ]]; then
  printf 'should_tag=false\n'
  printf 'candidate_sha=%s\n' "$candidate_sha"
  printf 'tag=%s\n' "$existing_beta_tag"
  exit 0
fi

latest_stable_tag="$(
  git tag --sort=-v:refname |
    grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' |
    head -1 || true
)"

if [[ -z "$latest_stable_tag" ]]; then
  echo "no stable vMAJOR.MINOR.PATCH tag exists" >&2
  exit 1
fi

version="${latest_stable_tag#v}"
IFS='.' read -r major minor patch <<EOF
$version
EOF

next_patch=$((10#$patch + 1))
proposed_tag="v${major}.${minor}.${next_patch}-beta.${run_number}"

if proposed_tag_sha="$(git rev-parse --verify "refs/tags/${proposed_tag}^{commit}" 2>/dev/null)"; then
  if [[ "$proposed_tag_sha" == "$candidate_sha" ]]; then
    printf 'should_tag=false\n'
    printf 'candidate_sha=%s\n' "$candidate_sha"
    printf 'tag=%s\n' "$proposed_tag"
    exit 0
  fi

  echo "proposed beta tag already points at another commit: $proposed_tag" >&2
  exit 1
fi

printf 'should_tag=true\n'
printf 'candidate_sha=%s\n' "$candidate_sha"
printf 'tag=%s\n' "$proposed_tag"
