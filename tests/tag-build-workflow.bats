#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORKFLOW_FILE="$REPO_ROOT/.github/workflows/tag-build.yml"
}

@test "tag-build workflow configures multi-arch platforms" {
  run grep -E '^[[:space:]]*platforms:[[:space:]]*linux/amd64,linux/arm64[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}

@test "tag-build workflow sets up QEMU before buildx" {
  qemu_line="$(grep -nE '^[[:space:]]*uses:[[:space:]]*docker/setup-qemu-action@v3[[:space:]]*$' "$WORKFLOW_FILE" | cut -d: -f1)"
  buildx_line="$(grep -nE '^[[:space:]]*uses:[[:space:]]*docker/setup-buildx-action@v3[[:space:]]*$' "$WORKFLOW_FILE" | cut -d: -f1)"

  [ -n "$qemu_line" ]
  [ -n "$buildx_line" ]
  [ "$qemu_line" -lt "$buildx_line" ]

  run grep -E '^[[:space:]]*uses:[[:space:]]*docker/setup-qemu-action@v3[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}
