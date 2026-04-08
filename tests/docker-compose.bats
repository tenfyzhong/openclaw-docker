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

@test "docker-compose maps published ports to the same configurable container ports" {
  run grep -F '      - "${OPENCLAW_GATEWAY_PORT:-18789}:${OPENCLAW_GATEWAY_PORT:-18789}"' "$COMPOSE_FILE"
  [ "$status" -eq 0 ]

  run grep -F '      - "${OPENCLAW_BRIDGE_PORT:-18790}:${OPENCLAW_BRIDGE_PORT:-18790}"' "$COMPOSE_FILE"
  [ "$status" -eq 0 ]
}
