# Node Sudo and Skills Installation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add passwordless sudo for the `node` user and install `larksuite/cli` skills using the `node` user context with `HOME=/home/node`.

**Architecture:** Keep the global CLI install flow in `Dockerfile` as root so the existing `/usr/local/bin` assumptions stay intact, then run only the `npx skills add larksuite/cli -y -g` step via `gosu node:node env HOME=/home/node`. Add a dedicated sudoers drop-in for `node` and verify the command shapes with bats before changing the Dockerfile.

**Tech Stack:** Dockerfile, Bash, apt, sudoers, gosu, Bats

---

### Task 1: Add failing Dockerfile tests for sudo support and node-context skills install

**Files:**
- Modify: `tests/dockerfile-entrypoint.bats`
- Test: `tests/dockerfile-entrypoint.bats`

- [ ] **Step 1: Write the failing tests**

```bash
@test "dockerfile installs sudo for the node user" {
  run grep -F '      sudo \' "$DOCKERFILE"
  [ "$status" -eq 0 ]
}

@test "dockerfile grants passwordless sudo to node" {
  run grep -F "node ALL=(ALL) NOPASSWD:ALL" "$DOCKERFILE"
  [ "$status" -eq 0 ]

  run grep -F "install -m 440 /dev/null /etc/sudoers.d/node-nopasswd" "$DOCKERFILE"
  [ "$status" -eq 0 ]
}

@test "dockerfile installs larksuite skills as node with node home" {
  run grep -F 'gosu node:node env HOME=/home/node npx skills add larksuite/cli -y -g; \' "$DOCKERFILE"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the test suite to verify the new assertions fail**

Run: `bats tests/dockerfile-entrypoint.bats`
Expected: FAIL because `sudo` is not installed, there is no `node` sudoers rule, and the `skills add` step still runs as root.

- [ ] **Step 3: Commit the red test changes**

```bash
git add tests/dockerfile-entrypoint.bats
git commit -s -m "test: cover node sudo and skills install context"
```

### Task 2: Implement passwordless sudo and node-context skills installation

**Files:**
- Modify: `Dockerfile`
- Test: `tests/dockerfile-entrypoint.bats`

- [ ] **Step 1: Add the minimal Dockerfile implementation**

```dockerfile
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      gnupg \
      gosu \
      hostname \
      openssl \
      procps \
      sudo && \
    rm -rf /var/lib/apt/lists/*

RUN install -m 440 /dev/null /etc/sudoers.d/node-nopasswd && \
    printf '%s\n' 'node ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/node-nopasswd

RUN /bin/bash -lc 'set -euo pipefail; \
    if ! command -v npm >/dev/null; then \
      echo "npm command not found; cannot install developer CLIs" >&2; \
      exit 1; \
    fi; \
    npm install -g --no-audit --no-fund opencode-ai @openai/codex @anthropic-ai/claude-code @larksuite/cli; \
    gosu node:node env HOME=/home/node npx skills add larksuite/cli -y -g; \
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
      if [[ -z "$CLI_BIN" ]]; then \
        echo "$cmd command not found after npm install" >&2; \
        exit 1; \
      fi; \
      ln -sf "$CLI_BIN" "/usr/local/bin/$cmd"; \
      "/usr/local/bin/$cmd" --help >/dev/null; \
    done; \
    chown -R node:node /home/node'
```

- [ ] **Step 2: Run the focused bats tests**

Run: `bats tests/dockerfile-entrypoint.bats`
Expected: PASS

- [ ] **Step 3: Commit the Dockerfile change**

```bash
git add Dockerfile tests/dockerfile-entrypoint.bats
git commit -s -m "fix: add node sudo and node-context skills install"
```

### Task 3: Verify image-level behavior

**Files:**
- Modify: none
- Test: `tests/dockerfile-entrypoint.bats`

- [ ] **Step 1: Re-run the relevant bats suites**

Run: `bats tests/dockerfile-entrypoint.bats tests/docker-compose.bats`
Expected: PASS

- [ ] **Step 2: Build the image**

Run: `docker build -t openclaw-debug:node-sudo .`
Expected: PASS

- [ ] **Step 3: Verify sudo configuration and node-owned skills paths in the built image**

Run: `docker run --rm --entrypoint bash openclaw-debug:node-sudo -lc 'sudo -n true && stat -c "%U:%G %n" /home/node/.agents && stat -c "%U:%G %n" /home/node/.agents/skills'`
Expected: PASS with `node:node` ownership for the reported `/home/node/.agents` paths

- [ ] **Step 4: Commit only if verification requires a follow-up fix**

```bash
git add Dockerfile tests/dockerfile-entrypoint.bats
git commit -s -m "chore: finalize node sudo verification"
```
