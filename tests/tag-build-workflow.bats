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

@test "tag-build workflow can create GitHub release on tag push" {
  run grep -E '^[[:space:]]*contents:[[:space:]]*write[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*uses:[[:space:]]*softprops/action-gh-release@v2[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}

@test "tag-build workflow release notes include docker usage" {
  run grep -E 'docker pull tenfyzhong/openclaw:\$\{\{ steps.vars.outputs.image_tag \}\}' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E 'OPENCLAW_VERSION=\$\{\{ steps.vars.outputs.image_tag \}\} docker compose up -d' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}
