#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORKFLOW_FILE="$REPO_ROOT/.github/workflows/tag-build.yml"
}

@test "tag-build workflow builds per-arch images in matrix" {
  run grep -E '^[[:space:]]*strategy:[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
  run grep -E '^[[:space:]]*matrix:[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
  run grep -E '^[[:space:]]*platform:[[:space:]]*linux/amd64[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
  run grep -E '^[[:space:]]*platform:[[:space:]]*linux/arm64[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}

@test "tag-build workflow creates multi-arch manifest from per-arch tags" {
  run grep -E 'docker buildx imagetools create' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
  run grep -E 'tenfyzhong/openclaw:\$\{\{ needs.parse-tag.outputs.image_tag \}\}-amd64' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
  run grep -E 'tenfyzhong/openclaw:\$\{\{ needs.parse-tag.outputs.image_tag \}\}-arm64' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
  run grep -E 'tenfyzhong/openclaw:\$\{\{ needs.parse-tag.outputs.image_tag \}\}' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
  run grep -E 'tenfyzhong/openclaw:latest' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}

@test "tag-build workflow can create GitHub release on tag push" {
  run grep -E '^[[:space:]]*contents:[[:space:]]*write[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*uses:[[:space:]]*softprops/action-gh-release@v2[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}

@test "tag-build workflow release notes include docker usage" {
  run grep -E 'docker pull tenfyzhong/openclaw:\$\{\{ needs.parse-tag.outputs.image_tag \}\}' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E 'OPENCLAW_VERSION=\$\{\{ needs.parse-tag.outputs.image_tag \}\} docker compose up -d' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}
