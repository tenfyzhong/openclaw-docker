#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  DOCKERFILE="$REPO_ROOT/Dockerfile"
}

@test "entrypoint defines default openclaw stdout/stderr log paths" {
  run grep -F 'OPENCLAW_STDOUT_LOG_PATH="${OPENCLAW_STDOUT_LOG_PATH:-${OPENCLAW_STATE_DIR}/logs/openclaw.stdout.log}"' "$DOCKERFILE"
  [ "$status" -eq 0 ]

  run grep -F 'OPENCLAW_STDERR_LOG_PATH="${OPENCLAW_STDERR_LOG_PATH:-${OPENCLAW_STATE_DIR}/logs/openclaw.stderr.log}"' "$DOCKERFILE"
  [ "$status" -eq 0 ]
}

@test "entrypoint creates openclaw log directory" {
  run grep -F 'mkdir -p "$OPENCLAW_STATE_DIR/logs"' "$DOCKERFILE"
  [ "$status" -eq 0 ]
}

@test "entrypoint redirects openclaw stdout/stderr to files" {
  run grep -F 'exec "${cmd[@]}" >>"$OPENCLAW_STDOUT_LOG_PATH" 2>>"$OPENCLAW_STDERR_LOG_PATH"' "$DOCKERFILE"
  [ "$status" -eq 0 ]
}

@test "dockerfile preinstalls openclaw lark tools cli" {
  run grep -F 'npm install -g @larksuite/openclaw-lark-tools' "$DOCKERFILE"
  [ "$status" -eq 0 ]

  run grep -F 'ln -sf "$LARK_TOOLS_BIN" /usr/local/bin/feishu-plugin-onboard' "$DOCKERFILE"
  [ "$status" -eq 0 ]

  run grep -F 'ln -sf "$LARK_TOOLS_BIN" /usr/local/bin/openclaw-lark-tools' "$DOCKERFILE"
  [ "$status" -eq 0 ]
}
