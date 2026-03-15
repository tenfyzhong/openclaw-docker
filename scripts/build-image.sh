#!/usr/bin/env bash
set -euo pipefail

IMAGE_REPO="${OPENCLAW_IMAGE_REPO:-tenfyzhong/openclaw}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-docker}"

usage() {
  cat <<'USAGE'
Usage: scripts/build-image.sh [--tag <tag>]

Build local container image for compose runtime.

Options:
  --tag <tag>  Build image tag. Supports latest, 2026.3.11, 2026.3.11.2 and v-prefixed forms.
               Default: value of OPENCLAW_VERSION or latest
  -h, --help   Show this help message

Environment Variables:
  CONTAINER_RUNTIME  Container runtime to use (docker or podman). Default: docker
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

resolve_tag() {
  local raw_tag="$1"

  if [[ "$raw_tag" == "latest" ]]; then
    IMAGE_TAG="latest"
    OPENCLAW_MAJOR="latest"
    return 0
  fi

  if [[ "$raw_tag" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+)(\.[0-9]+)?$ ]]; then
    IMAGE_TAG="${raw_tag#v}"
    OPENCLAW_MAJOR="${BASH_REMATCH[1]}"
    return 0
  fi

  die "unsupported tag format '$raw_tag'. Expected latest, 2026.3.11, 2026.3.11.2 (with optional v prefix)"
}

main() {
  local tag_input="${OPENCLAW_VERSION:-latest}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tag)
        [[ $# -ge 2 ]] || die "--tag requires a value"
        tag_input="$2"
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

  command -v "$CONTAINER_RUNTIME" >/dev/null 2>&1 || die "$CONTAINER_RUNTIME command not found"

  resolve_tag "$tag_input"

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local repo_root
  repo_root="$(cd "$script_dir/.." && pwd)"

  local image_ref="${IMAGE_REPO}:${IMAGE_TAG}"

  "$CONTAINER_RUNTIME" build \
    --build-arg "OPENCLAW_VERSION=${OPENCLAW_MAJOR}" \
    -t "$image_ref" \
    "$repo_root"

  echo "Built local image: $image_ref"
}

main "$@"
