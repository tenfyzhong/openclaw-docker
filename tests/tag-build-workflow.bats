#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORKFLOW_FILE="$REPO_ROOT/.github/workflows/tag-build.yml"
}

@test "tag-build workflow builds and pushes a single multi-platform image with cache" {
  run grep -E '^[[:space:]]*build-and-push:[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*platforms:[[:space:]]*linux/amd64,linux/arm64[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*cache-from:[[:space:]]*type=gha,scope=openclaw-docker[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*cache-to:[[:space:]]*type=gha,scope=openclaw-docker,mode=max[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E 'tenfyzhong/openclaw:\$\{\{ needs.parse-tag.outputs.image_tag \}\}[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E 'tenfyzhong/openclaw:latest[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}

@test "tag-build workflow no longer uses per-arch jobs or manual manifest assembly" {
  run bash -lc '! grep -qF "build-and-push-arch:" "$1"' bash "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run bash -lc '! grep -qF "publish-manifest:" "$1"' bash "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run bash -lc '! grep -qF "docker buildx imagetools create" "$1"' bash "$WORKFLOW_FILE"
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
