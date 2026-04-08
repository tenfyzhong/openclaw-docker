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

@test "entrypoint hardcodes node user and home directory" {
  run grep -F 'OPENCLAW_USER="node"' "$DOCKERFILE"
  [ "$status" -eq 0 ]

  run grep -F 'OPENCLAW_GROUP="node"' "$DOCKERFILE"
  [ "$status" -eq 0 ]

  run grep -F 'OPENCLAW_HOME="/home/node"' "$DOCKERFILE"
  [ "$status" -eq 0 ]

  run grep -F 'USER node' "$DOCKERFILE"
  [ "$status" -eq 0 ]
}

@test "dockerfile switches to node after global npm install" {
  run bash -lc '
    set -euo pipefail
    user_line="$(grep -nF "USER node" "$1" | tail -n1 | cut -d: -f1)"
    npm_line="$(grep -nF "npm install -g --no-audit --no-fund opencode-ai @openai/codex @anthropic-ai/claude-code @larksuite/cli; \\" "$1" | tail -n1 | cut -d: -f1)"
    [[ -n "$user_line" ]]
    [[ -n "$npm_line" ]]
    (( npm_line < user_line ))
  ' bash "$DOCKERFILE"
  [ "$status" -eq 0 ]
}

@test "dockerfile installs the openclaw container status wrapper" {
  run grep -F 'COPY scripts/openclaw-wrapper.sh /usr/local/libexec/openclaw-wrapper.sh' "$DOCKERFILE"
  [ "$status" -eq 0 ]

  run grep -F 'rm -f /usr/local/bin/openclaw && \' "$DOCKERFILE"
  [ "$status" -eq 0 ]

  run grep -F 'install -m 755 /usr/local/libexec/openclaw-wrapper.sh /usr/local/bin/openclaw && \' "$DOCKERFILE"
  [ "$status" -eq 0 ]
}
