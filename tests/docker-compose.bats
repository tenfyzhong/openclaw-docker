#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"
}

@test "docker-compose uses image tag variable" {
  run grep -E '^[[:space:]]*image:[[:space:]]*tenfyzhong/openclaw:\$\{OPENCLAW_VERSION:-latest\}[[:space:]]*$' "$COMPOSE_FILE"
  [ "$status" -eq 0 ]
}

@test "docker-compose does not define build node" {
  run grep -E '^[[:space:]]*build:[[:space:]]*$' "$COMPOSE_FILE"
  [ "$status" -eq 1 ]
}
