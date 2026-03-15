#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_REPO_URL="${OPENCLAW_UPSTREAM_REPO_URL:-https://github.com/openclaw/openclaw.git}"
UPSTREAM_TAGS_FILE="${OPENCLAW_UPSTREAM_TAGS_FILE:-}"

usage() {
  cat <<'USAGE'
Usage: scripts/create-tag.sh [--major <major-version>]

Options:
  --major <major-version>  Use a specific major version (accepts 2026.3.11 or v2026.3.11)
  -h, --help               Show this help message
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

ensure_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "must run inside a git repository"
}

normalize_major_tag() {
  local raw="$1"
  local trimmed="${raw#v}"

  if [[ ! "$trimmed" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "invalid major version '$raw'. Expected format: 2026.3.11 or v2026.3.11"
  fi

  echo "v$trimmed"
}

normalize_upstream_major_tags() {
  sed -n \
    -e 's/^\(v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p' \
    -e 's/^\(v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)-[0-9][0-9]*$/\1/p' \
    | sort -u
}

load_upstream_major_tags() {
  if [[ -n "$UPSTREAM_TAGS_FILE" ]]; then
    [[ -f "$UPSTREAM_TAGS_FILE" ]] || die "OPENCLAW_UPSTREAM_TAGS_FILE does not exist: $UPSTREAM_TAGS_FILE"
    normalize_upstream_major_tags < "$UPSTREAM_TAGS_FILE"
    return 0
  fi

  git ls-remote --tags --refs "$UPSTREAM_REPO_URL" 'v*' \
    | awk '{print $2}' \
    | sed -n 's|^refs/tags/\(v[^[:space:]]\+\)$|\1|p' \
    | normalize_upstream_major_tags
}

resolve_major_tag() {
  local requested_major="$1"
  local upstream_tags="$2"

  if [[ -n "$requested_major" ]]; then
    local normalized
    normalized="$(normalize_major_tag "$requested_major")"
    if ! grep -Fxq "$normalized" <<<"$upstream_tags"; then
      die "major version '$normalized' does not exist in openclaw/openclaw"
    fi
    echo "$normalized"
    return 0
  fi

  local latest_major
  latest_major="$(printf '%s\n' "$upstream_tags" | sort -V | tail -n 1)"
  [[ -n "$latest_major" ]] || die "cannot resolve latest major tag from openclaw/openclaw"
  echo "$latest_major"
}

compute_next_tag() {
  local major_tag="$1"
  local escaped_major
  escaped_major="${major_tag//./\\.}"

  local has_major=0
  if git rev-parse -q --verify "refs/tags/$major_tag" >/dev/null; then
    has_major=1
  fi

  if [[ "$has_major" -eq 0 ]]; then
    if git tag -l | grep -Eq "^${escaped_major}\.[0-9]+$"; then
      local max_patch_without_major
      max_patch_without_major="$(git tag -l \
        | sed -n "s/^${escaped_major}\.\([0-9]\+\)$/\1/p" \
        | sort -n \
        | tail -n 1)"
      echo "${major_tag}.$((max_patch_without_major + 1))"
      return 0
    fi

    echo "$major_tag"
    return 0
  fi

  local max_patch
  max_patch="$(git tag -l \
    | sed -n "s/^${escaped_major}\.\([0-9]\+\)$/\1/p" \
    | sort -n \
    | tail -n 1)"

  if [[ -z "$max_patch" ]]; then
    echo "${major_tag}.1"
  else
    echo "${major_tag}.$((max_patch + 1))"
  fi
}

main() {
  ensure_git_repo

  local requested_major=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --major)
        [[ $# -ge 2 ]] || die "--major requires a value"
        requested_major="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done

  git fetch --tags origin >/dev/null

  local upstream_tags
  upstream_tags="$(load_upstream_major_tags)"
  [[ -n "$upstream_tags" ]] || die "no major tags found in openclaw/openclaw"

  local major_tag
  major_tag="$(resolve_major_tag "$requested_major" "$upstream_tags")"

  local new_tag
  new_tag="$(compute_next_tag "$major_tag")"

  if git rev-parse -q --verify "refs/tags/$new_tag" >/dev/null; then
    die "tag '$new_tag' already exists locally"
  fi

  git tag "$new_tag"
  echo "Created local tag: $new_tag"
}

main "$@"
