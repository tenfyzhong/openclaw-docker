# Home Directory Persistence Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make whole-home `/home/node` mounting the only Compose runtime mode and guarantee `node:node` ownership for `/home/node`, while documenting how to migrate from the older split-mount layout.

**Architecture:** Keep a single `openclaw-gateway` service in `docker-compose.yml` with whole-home persistence through `OPENCLAW_HOME_DIR`, normalize `/home/node` ownership in the image and entrypoint, and describe legacy split-mount migration in `README.md`. Verify the behavior with bats tests before changing Dockerfile, Compose, and README.

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

- [ ] **Step 2: Write the failing test for whole-home compose support without legacy split-mount compatibility**

```bash
setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"
}

@test "docker-compose mounts /home/node from OPENCLAW_HOME_DIR by default" {
  run grep -F '      - ${OPENCLAW_HOME_DIR:-./openclaw-home}:/home/node' "$COMPOSE_FILE"
  [ "$status" -eq 0 ]
}

@test "docker-compose does not keep legacy split-mount compatibility" {
  run grep -F 'openclaw-gateway-legacy' "$COMPOSE_FILE"
  [ "$status" -eq 1 ]

  run grep -F 'OPENCLAW_CONFIG_DIR' "$COMPOSE_FILE"
  [ "$status" -eq 1 ]

  run grep -F 'OPENCLAW_WORKSPACE_DIR' "$COMPOSE_FILE"
  [ "$status" -eq 1 ]
}

@test "docker-compose does not need a separate whole-home compose file" {
  run test ! -e "$REPO_ROOT/docker-compose.home.yml"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 3: Run the tests to verify they fail for the expected reason**

Run: `bats tests/dockerfile-entrypoint.bats tests/docker-compose.bats`
Expected: FAIL because `docker-compose.yml` still includes legacy split-mount compatibility content.

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

### Task 3: Keep only whole-home Compose runtime and document migration

**Files:**
- Modify: `docker-compose.yml`
- Modify: `README.md`
- Modify: `tests/docker-compose.bats`
- Test: `tests/docker-compose.bats`

- [ ] **Step 1: Make `docker-compose.yml` a single whole-home service**

```yaml
x-openclaw-gateway-base: &openclaw-gateway-base
  image: tenfyzhong/openclaw:${OPENCLAW_VERSION:-latest}
  ...

services:
  openclaw-gateway:
    image: tenfyzhong/openclaw:${OPENCLAW_VERSION:-latest}
    ...
    volumes:
      - ${OPENCLAW_HOME_DIR:-./openclaw-home}:/home/node
```

- [ ] **Step 2: Update README with legacy mode, whole-home mode, and migration guidance**

```markdown
## Persistence Modes

- `OPENCLAW_HOME_DIR` -> `/home/node`
- README also explains how to copy state from the old split-mount layout.
```

- [ ] **Step 3: Run the compose bats tests**

Run: `bats tests/docker-compose.bats`
Expected: PASS

- [ ] **Step 4: Commit the compose and documentation changes**

```bash
git add docker-compose.yml README.md tests/docker-compose.bats
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

Run: `rg -n "OPENCLAW_HOME_DIR|OPENCLAW_CONFIG_DIR|OPENCLAW_WORKSPACE_DIR|/home/node|legacy" README.md docker-compose.yml docs/superpowers/specs/2026-04-09-home-node-persistence-design.md docs/superpowers/plans/2026-04-09-home-node-persistence.md`
Expected: all documented variables and mount paths match the implementation exactly

- [ ] **Step 4: Commit the verification checkpoint if additional fixes were needed**

```bash
git add Dockerfile docker-compose.yml README.md tests/dockerfile-entrypoint.bats tests/docker-compose.bats
git commit -s -m "chore: finalize home persistence verification"
```
