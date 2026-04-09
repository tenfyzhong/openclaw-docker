# Home Directory Persistence Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the legacy `.openclaw` mount mode working while adding a supported whole-`/home/node` mount mode and guaranteeing `node:node` ownership for `/home/node`.

**Architecture:** Keep `docker-compose.yml` as the backward-compatible legacy definition, add a dedicated whole-home Compose file for the new persistence model, and normalize `/home/node` ownership in the image and entrypoint. Verify the behavior with bats tests before changing Dockerfile, Compose, and README.

**Tech Stack:** Dockerfile, Docker Compose YAML, Bash entrypoint, Bats tests, Markdown documentation

---

### Task 1: Add failing coverage for ownership normalization and whole-home compose support

**Files:**
- Modify: `tests/dockerfile-entrypoint.bats`
- Modify: `tests/docker-compose.bats`
- Test: `tests/dockerfile-entrypoint.bats`
- Test: `tests/docker-compose.bats`

- [ ] **Step 1: Write the failing test for `/home/node` ownership repair in the Dockerfile**

```bash
@test "entrypoint ensures /home/node is owned by node" {
  run grep -F 'chown node:node "$OPENCLAW_HOME"' "$DOCKERFILE"
  [ "$status" -eq 0 ]
}

@test "dockerfile normalizes /home/node ownership after root-run cli install" {
  run bash -lc '
    set -euo pipefail
    npm_line="$(grep -nF "npx skills add larksuite/cli -y -g; \\" "$1" | tail -n1 | cut -d: -f1)"
    fix_line="$(grep -nF "chown -R node:node /home/node" "$1" | tail -n1 | cut -d: -f1)"
    [[ -n "$npm_line" ]]
    [[ -n "$fix_line" ]]
    (( npm_line < fix_line ))
  ' bash "$DOCKERFILE"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Write the failing test for whole-home compose support while keeping legacy compose mounts**

```bash
setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"
  HOME_COMPOSE_FILE="$REPO_ROOT/docker-compose.home.yml"
}

@test "docker-compose keeps legacy config and workspace mounts" {
  run grep -F '      - ${OPENCLAW_CONFIG_DIR:-./openclaw-data}:/home/node/.openclaw' "$COMPOSE_FILE"
  [ "$status" -eq 0 ]

  run grep -F '      - ${OPENCLAW_WORKSPACE_DIR:-./openclaw-data/workspace}:/home/node/.openclaw/workspace' "$COMPOSE_FILE"
  [ "$status" -eq 0 ]
}

@test "whole-home compose file mounts /home/node from OPENCLAW_HOME_DIR" {
  run grep -F '      - ${OPENCLAW_HOME_DIR:-./openclaw-home}:/home/node' "$HOME_COMPOSE_FILE"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 3: Run the tests to verify they fail for the expected reason**

Run: `bats tests/dockerfile-entrypoint.bats tests/docker-compose.bats`
Expected: FAIL because `docker-compose.home.yml` does not exist yet and the Dockerfile does not yet normalize `/home/node` ownership after the CLI install block.

- [ ] **Step 4: Commit the red test changes after verifying the failure**

```bash
git add tests/dockerfile-entrypoint.bats tests/docker-compose.bats
git commit -s -m "test: cover home directory persistence modes"
```

### Task 2: Implement Dockerfile and entrypoint ownership guarantees

**Files:**
- Modify: `Dockerfile`
- Test: `tests/dockerfile-entrypoint.bats`

- [ ] **Step 1: Add the minimal implementation for `/home/node` ownership guarantees**

```dockerfile
fix_permissions() {
  if [[ "$(id -u)" -ne 0 ]]; then
    return 0
  fi

  chown node:node "$OPENCLAW_HOME" "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE_DIR"
  chown node:node \
    "$(dirname "$OPENCLAW_STDOUT_LOG_PATH")" \
    "$(dirname "$OPENCLAW_STDERR_LOG_PATH")" \
    "$OPENCLAW_STDOUT_LOG_PATH" \
    "$OPENCLAW_STDERR_LOG_PATH"
  find "$OPENCLAW_STATE_DIR" -xdev -exec chown node:node {} +
  if [[ -d "$OPENCLAW_WORKSPACE_DIR/.openclaw" ]]; then
    chown -R node:node "$OPENCLAW_WORKSPACE_DIR/.openclaw"
  fi
}

RUN /bin/bash -lc 'set -euo pipefail; \
    npm install -g --no-audit --no-fund opencode-ai @openai/codex @anthropic-ai/claude-code @larksuite/cli; \
    npx skills add larksuite/cli -y -g; \
    NPM_PREFIX="$(npm config get prefix)"; \
    NPM_BIN="${NPM_PREFIX%/}/bin"; \
    for cmd in opencode codex claude; do \
      CLI_BIN="$(command -v "$cmd" || true)"; \
      if [[ -z "$CLI_BIN" ]] && [[ -x "$NPM_BIN/$cmd" ]]; then \
        CLI_BIN="$NPM_BIN/$cmd"; \
      elif [[ -z "$CLI_BIN" ]] && [[ -x /root/.npm-global/bin/"$cmd" ]]; then \
        CLI_BIN=/root/.npm-global/bin/"$cmd"; \
      elif [[ -z "$CLI_BIN" ]] && [[ -x /root/.local/bin/"$cmd" ]]; then \
        CLI_BIN=/root/.local/bin/"$cmd"; \
      fi; \
      ln -sf "$CLI_BIN" "/usr/local/bin/$cmd"; \
      "/usr/local/bin/$cmd" --help >/dev/null; \
    done; \
    chown -R node:node /home/node'
```

- [ ] **Step 2: Run the focused Dockerfile bats tests**

Run: `bats tests/dockerfile-entrypoint.bats`
Expected: PASS

- [ ] **Step 3: Commit the ownership fix**

```bash
git add Dockerfile tests/dockerfile-entrypoint.bats
git commit -s -m "fix: normalize home ownership in image"
```

### Task 3: Add the whole-home Compose definition and document compatibility

**Files:**
- Create: `docker-compose.home.yml`
- Modify: `README.md`
- Modify: `tests/docker-compose.bats`
- Test: `tests/docker-compose.bats`

- [ ] **Step 1: Create the dedicated whole-home Compose file**

```yaml
services:
  openclaw-gateway:
    image: tenfyzhong/openclaw:${OPENCLAW_VERSION:-latest}
    environment:
      HOME: /home/node
      TERM: xterm-256color
      OPENCLAW_GATEWAY_BIND: ${OPENCLAW_GATEWAY_BIND:-lan}
      OPENCLAW_GATEWAY_PORT: ${OPENCLAW_GATEWAY_PORT:-18789}
      OPENCLAW_BRIDGE_PORT: ${OPENCLAW_BRIDGE_PORT:-18790}
      OPENCLAW_GATEWAY_TOKEN: ${OPENCLAW_GATEWAY_TOKEN:-}
      OPENCLAW_ALLOW_INSECURE_PRIVATE_WS: ${OPENCLAW_ALLOW_INSECURE_PRIVATE_WS:-}
      OPENCLAW_INIT_GATEWAY_MODE: ${OPENCLAW_INIT_GATEWAY_MODE:-local}
      OPENCLAW_INIT_CONTROL_UI_ALLOWED_ORIGINS: ${OPENCLAW_INIT_CONTROL_UI_ALLOWED_ORIGINS:-}
      OPENCLAW_GATEWAY_CONTROLUI_DANGEROUSLY_ALLOW_HOST_HEADER_ORIGIN_FALLBACK: ${OPENCLAW_GATEWAY_CONTROLUI_DANGEROUSLY_ALLOW_HOST_HEADER_ORIGIN_FALLBACK:-false}
      CLAUDE_AI_SESSION_KEY: ${CLAUDE_AI_SESSION_KEY:-}
      CLAUDE_WEB_SESSION_KEY: ${CLAUDE_WEB_SESSION_KEY:-}
      CLAUDE_WEB_COOKIE: ${CLAUDE_WEB_COOKIE:-}
    volumes:
      - ${OPENCLAW_HOME_DIR:-./openclaw-home}:/home/node
      # - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - "${OPENCLAW_GATEWAY_PORT:-18789}:${OPENCLAW_GATEWAY_PORT:-18789}"
      - "${OPENCLAW_BRIDGE_PORT:-18790}:${OPENCLAW_BRIDGE_PORT:-18790}"
    init: true
    restart: unless-stopped
    command: ["gateway"]
    healthcheck:
      test: ["CMD", "node", "-e", "const p=process.env.OPENCLAW_GATEWAY_PORT||'18789';fetch('http://127.0.0.1:'+p+'/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 20s
```

- [ ] **Step 2: Update README with legacy mode, whole-home mode, and migration guidance**

```markdown
## Persistence Modes

### Legacy mode

- `OPENCLAW_CONFIG_DIR` -> `/home/node/.openclaw`
- `OPENCLAW_WORKSPACE_DIR` -> `/home/node/.openclaw/workspace`

### Whole-home mode

- `OPENCLAW_HOME_DIR` -> `/home/node`
- Recommended for new deployments because it persists the entire home directory.

Do not enable both modes at the same time.
```

- [ ] **Step 3: Run the compose bats tests**

Run: `bats tests/docker-compose.bats`
Expected: PASS

- [ ] **Step 4: Commit the compose and documentation changes**

```bash
git add docker-compose.home.yml README.md tests/docker-compose.bats
git commit -s -m "feat: add whole-home compose persistence mode"
```

### Task 4: Run end-to-end verification for the changed surface

**Files:**
- Modify: none
- Test: `tests/dockerfile-entrypoint.bats`
- Test: `tests/docker-compose.bats`

- [ ] **Step 1: Run the changed bats suites together**

Run: `bats tests/dockerfile-entrypoint.bats tests/docker-compose.bats`
Expected: PASS

- [ ] **Step 2: Build the image and inspect ownership inside `/home/node`**

Run: `docker build -t openclaw-debug:home-fix .`
Expected: PASS

Run: `docker run --rm --entrypoint bash openclaw-debug:home-fix -lc 'find /home/node -maxdepth 3 \\( -type d -o -type f \\) -user root -print'`
Expected: no output

- [ ] **Step 3: Review docs and compose files for consistency**

Run: `rg -n "OPENCLAW_HOME_DIR|OPENCLAW_CONFIG_DIR|OPENCLAW_WORKSPACE_DIR|/home/node" README.md docker-compose.yml docker-compose.home.yml`
Expected: all documented variables and mount paths match the implementation exactly

- [ ] **Step 4: Commit the verification checkpoint if additional fixes were needed**

```bash
git add Dockerfile docker-compose.yml docker-compose.home.yml README.md tests/dockerfile-entrypoint.bats tests/docker-compose.bats
git commit -s -m "chore: finalize home persistence verification"
```
