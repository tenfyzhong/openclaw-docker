#!/usr/bin/env bash
set -euo pipefail

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-docker}"

usage() {
  cat <<'USAGE'
Usage: scripts/compose.sh [compose-args...]

Wrapper to run docker-compose or podman-compose based on CONTAINER_RUNTIME.

Environment Variables:
  CONTAINER_RUNTIME  Container runtime to use (docker or podman). Default: docker

Examples:
  ./scripts/compose.sh up -d
  ./scripts/compose.sh down
  CONTAINER_RUNTIME=podman ./scripts/compose.sh up -d
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

main() {
  if [[ $# -eq 1 ]] && [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
  fi

  local compose_cmd

  case "$CONTAINER_RUNTIME" in
    docker)
      if command -v docker >/dev/null 2>&1; then
        if docker compose version >/dev/null 2>&1; then
          compose_cmd="docker compose"
        elif command -v docker-compose >/dev/null 2>&1; then
          compose_cmd="docker-compose"
        else
          die "docker compose or docker-compose not found"
        fi
      else
        die "docker command not found"
      fi
      ;;
    podman)
      if command -v podman >/dev/null 2>&1; then
        if podman compose version >/dev/null 2>&1; then
          compose_cmd="podman compose"
        elif command -v podman-compose >/dev/null 2>&1; then
          compose_cmd="podman-compose"
        else
          die "podman compose or podman-compose not found"
        fi
      else
        die "podman command not found"
      fi
      ;;
    *)
      die "unsupported CONTAINER_RUNTIME: $CONTAINER_RUNTIME (must be docker or podman)"
      ;;
  esac

  echo "Using: $compose_cmd" >&2
  exec $compose_cmd "$@"
}

main "$@"
