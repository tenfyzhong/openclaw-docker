# Docker Build Cache Acceleration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the release workflow's cold per-architecture Docker builds with a cached multi-platform build path and add a cache-warming workflow that preheats the next release version.

**Architecture:** Collapse the current tag publish flow into one `docker/build-push-action@v6` multi-platform job so cache configuration and image publishing live in one place. Add a second workflow that reads `OPENCLAW_UPSTREAM_VERSION` and writes into the same GitHub Actions BuildKit cache scope without publishing images, then update the Dockerfile APT layer to use BuildKit cache mounts.

**Tech Stack:** GitHub Actions, Docker Buildx, BuildKit cache mounts, Bash, Bats

**Known Baseline:** `bats tests/*.bats` currently fails before any new changes at `tests/create-tag.bats` test `increments patch when major already exists`. Treat that as pre-existing until the human explicitly asks to fix it.

---

### Task 1: Add failing tests for the new release workflow shape

**Files:**
- Modify: `tests/tag-build-workflow.bats`
- Test: `tests/tag-build-workflow.bats`

- [ ] **Step 1: Replace the old matrix-manifest assertions with failing single-job cache assertions**

```bash
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
```

- [ ] **Step 2: Run the focused workflow tests to verify they fail for the expected reason**

Run: `bats tests/tag-build-workflow.bats`
Expected: FAIL because the workflow still defines `build-and-push-arch`, still uses a matrix, and does not define the shared `cache-from` and `cache-to` settings.

- [ ] **Step 3: Commit the red test change**

```bash
git add tests/tag-build-workflow.bats
git commit -s -m "test: cover cached multi-platform tag build"
```

### Task 2: Add failing tests for the cache warm workflow and Dockerfile cache mounts

**Files:**
- Create: `tests/docker-build-cache-workflow.bats`
- Modify: `tests/dockerfile-entrypoint.bats`
- Test: `tests/docker-build-cache-workflow.bats`
- Test: `tests/dockerfile-entrypoint.bats`

- [ ] **Step 1: Add a new failing Bats file for the warm-cache workflow**

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORKFLOW_FILE="$REPO_ROOT/.github/workflows/docker-cache-warm.yml"
}

@test "docker cache warm workflow triggers on main push pull request and manual dispatch" {
  run grep -E '^[[:space:]]*push:[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*pull_request:[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*workflow_dispatch:[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*-[[:space:]]*main[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}

@test "docker cache warm workflow reads the tracked upstream version and writes shared cache" {
  run grep -F 'raw_major="$(tr -d '\''\n'\'' < OPENCLAW_UPSTREAM_VERSION)"' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -F 'echo "openclaw_major=${raw_major#v}" >>"$GITHUB_OUTPUT"' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*platforms:[[:space:]]*linux/amd64,linux/arm64[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*push:[[:space:]]*false[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*cache-from:[[:space:]]*type=gha,scope=openclaw-docker[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*cache-to:[[:space:]]*type=gha,scope=openclaw-docker,mode=max[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}

@test "docker cache warm workflow does not log in to Docker Hub" {
  run bash -lc '! grep -qF "docker/login-action@v3" "$1"' bash "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Add a failing Dockerfile test for BuildKit APT cache mounts**

```bash
@test "dockerfile caches apt metadata and packages with buildkit mounts" {
  run grep -F 'RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \' "$DOCKERFILE"
  [ "$status" -eq 0 ]

  run grep -F '    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \' "$DOCKERFILE"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 3: Run the new focused tests to verify they fail correctly**

Run: `bats tests/docker-build-cache-workflow.bats tests/dockerfile-entrypoint.bats`
Expected: FAIL because `.github/workflows/docker-cache-warm.yml` does not exist and the Dockerfile still uses a plain `RUN apt-get update`.

- [ ] **Step 4: Commit the red test changes**

```bash
git add tests/docker-build-cache-workflow.bats tests/dockerfile-entrypoint.bats
git commit -s -m "test: cover docker cache warming"
```

### Task 3: Implement the cached multi-platform release workflow

**Files:**
- Modify: `.github/workflows/tag-build.yml`
- Test: `tests/tag-build-workflow.bats`

- [ ] **Step 1: Replace the matrix publish path with one cached multi-platform job**

```yaml
  build-and-push:
    needs: parse-tag
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build and push multi-platform image
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          platforms: linux/amd64,linux/arm64
          build-args: |
            OPENCLAW_VERSION=${{ needs.parse-tag.outputs.openclaw_major }}
          cache-from: type=gha,scope=openclaw-docker
          cache-to: type=gha,scope=openclaw-docker,mode=max
          tags: |
            tenfyzhong/openclaw:${{ needs.parse-tag.outputs.image_tag }}
            tenfyzhong/openclaw:latest

  create-github-release:
    needs:
      - parse-tag
      - build-and-push
```

- [ ] **Step 2: Run the release workflow tests**

Run: `bats tests/tag-build-workflow.bats`
Expected: PASS

- [ ] **Step 3: Commit the workflow implementation**

```bash
git add .github/workflows/tag-build.yml tests/tag-build-workflow.bats
git commit -s -m "ci: cache multi-platform tag builds"
```

### Task 4: Implement the cache warm workflow

**Files:**
- Create: `.github/workflows/docker-cache-warm.yml`
- Test: `tests/docker-build-cache-workflow.bats`

- [ ] **Step 1: Add the warm-cache workflow**

```yaml
name: Warm Docker Build Cache

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read

jobs:
  warm-cache:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Read OpenClaw major version
        id: version
        shell: bash
        run: |
          set -euo pipefail

          raw_major="$(tr -d '\n' < OPENCLAW_UPSTREAM_VERSION)"
          if [[ ! "$raw_major" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "Unsupported upstream version: $raw_major" >&2
            exit 1
          fi

          echo "openclaw_major=${raw_major#v}" >>"$GITHUB_OUTPUT"

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Warm Docker build cache
        uses: docker/build-push-action@v6
        with:
          context: .
          push: false
          platforms: linux/amd64,linux/arm64
          build-args: |
            OPENCLAW_VERSION=${{ steps.version.outputs.openclaw_major }}
          cache-from: type=gha,scope=openclaw-docker
          cache-to: type=gha,scope=openclaw-docker,mode=max
```

- [ ] **Step 2: Run the warm-cache workflow tests**

Run: `bats tests/docker-build-cache-workflow.bats`
Expected: PASS

- [ ] **Step 3: Commit the warm-cache workflow**

```bash
git add .github/workflows/docker-cache-warm.yml tests/docker-build-cache-workflow.bats
git commit -s -m "ci: warm docker build cache"
```

### Task 5: Implement Dockerfile BuildKit cache mounts

**Files:**
- Modify: `Dockerfile`
- Test: `tests/dockerfile-entrypoint.bats`

- [ ] **Step 1: Replace the plain APT layer with cache mounts**

```dockerfile
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      gnupg \
      gosu \
      hostname \
      openssl \
      procps \
      sudo
```

- [ ] **Step 2: Run the Dockerfile-focused bats tests**

Run: `bats tests/dockerfile-entrypoint.bats`
Expected: PASS

- [ ] **Step 3: Commit the Dockerfile cache change**

```bash
git add Dockerfile tests/dockerfile-entrypoint.bats
git commit -s -m "build: cache apt metadata in docker builds"
```

### Task 6: Verify the change set end to end

**Files:**
- Modify: none
- Test: `tests/tag-build-workflow.bats`
- Test: `tests/docker-build-cache-workflow.bats`
- Test: `tests/dockerfile-entrypoint.bats`

- [ ] **Step 1: Run the focused suites for this change**

Run: `bats tests/tag-build-workflow.bats tests/docker-build-cache-workflow.bats tests/dockerfile-entrypoint.bats`
Expected: PASS

- [ ] **Step 2: Build the image locally with BuildKit enabled**

Run: `DOCKER_BUILDKIT=1 docker build -t openclaw-debug:docker-cache .`
Expected: PASS

- [ ] **Step 3: Record the known unrelated baseline failure separately**

Run: `bats tests/*.bats`
Expected: FAIL only at `tests/create-tag.bats` test `increments patch when major already exists`, with the new cache-related tests still passing.

- [ ] **Step 4: Commit only if verification requires a follow-up fix**

```bash
git add Dockerfile .github/workflows/tag-build.yml .github/workflows/docker-cache-warm.yml tests/tag-build-workflow.bats tests/docker-build-cache-workflow.bats tests/dockerfile-entrypoint.bats
git commit -s -m "chore: finalize docker build cache verification"
```
