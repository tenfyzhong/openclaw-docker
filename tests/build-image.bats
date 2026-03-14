#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT_PATH="$REPO_ROOT/scripts/build-image.sh"

  TEST_BIN="$BATS_TEST_TMPDIR/bin"
  DOCKER_LOG_FILE="$BATS_TEST_TMPDIR/docker.log"

  mkdir -p "$TEST_BIN"
  cat >"$TEST_BIN/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_LOG_FILE"
EOF
  chmod +x "$TEST_BIN/docker"
}

@test "build-image script builds image tag and major build arg from release tag" {
  run env \
    PATH="$TEST_BIN:$PATH" \
    DOCKER_LOG_FILE="$DOCKER_LOG_FILE" \
    "$SCRIPT_PATH" --tag v2026.3.11.2

  [ "$status" -eq 0 ]
  [[ "$output" == *"Built local image: tenfyzhong/openclaw:2026.3.11.2"* ]]

  run cat "$DOCKER_LOG_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"build --build-arg OPENCLAW_VERSION=2026.3.11 -t tenfyzhong/openclaw:2026.3.11.2 "* ]]
  [[ "$output" == *"/openclaw-docker"* ]]
}

@test "build-image script defaults to latest when no tag is provided" {
  run env \
    PATH="$TEST_BIN:$PATH" \
    DOCKER_LOG_FILE="$DOCKER_LOG_FILE" \
    "$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Built local image: tenfyzhong/openclaw:latest"* ]]

  run cat "$DOCKER_LOG_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"build --build-arg OPENCLAW_VERSION=latest -t tenfyzhong/openclaw:latest "* ]]
  [[ "$output" == *"/openclaw-docker"* ]]
}

@test "build-image script rejects unsupported tag format" {
  run env \
    PATH="$TEST_BIN:$PATH" \
    DOCKER_LOG_FILE="$DOCKER_LOG_FILE" \
    "$SCRIPT_PATH" --tag 2026.3

  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported tag format"* ]]
}
