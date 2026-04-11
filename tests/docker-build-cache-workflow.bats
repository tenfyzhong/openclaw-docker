#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORKFLOW_FILE="$REPO_ROOT/.github/workflows/docker-cache-warm.yml"
}

@test "docker cache warm workflow triggers on main push pull request and manual dispatch" {
  run grep -E '^[[:space:]]*push:[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*pull_request:[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*workflow_dispatch:[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*-[[:space:]]*main[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}

@test "docker cache warm workflow reads the tracked upstream version and writes shared cache" {
  run grep -F 'raw_major="$(tr -d '\''\n'\'' < OPENCLAW_UPSTREAM_VERSION)"' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -F 'echo "openclaw_major=${raw_major#v}" >>"$GITHUB_OUTPUT"' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*platforms:[[:space:]]*linux/amd64,linux/arm64[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*push:[[:space:]]*false[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*cache-from:[[:space:]]*type=gha,scope=openclaw-docker[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*cache-to:[[:space:]]*type=gha,scope=openclaw-docker,mode=max[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}

@test "docker cache warm workflow does not log in to Docker Hub" {
  run bash -lc '! grep -qF "docker/login-action@v3" "$1"' bash "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}
