# Docker Build Cache Acceleration Design

## Context

The current release workflow builds and pushes one image per architecture and then assembles a manifest with `docker buildx imagetools create`.

That structure has two problems:

1. `docker/build-push-action@v6` is not configured with any remote cache backend, so every GitHub-hosted runner starts from a cold BuildKit cache.
2. The release path is optimized only for publishing tags. It does not pre-build the current OpenClaw major version on `main` or pull requests, so the first release build for a new version often pays the full cost.

The Dockerfile also leaves build performance on the table because the APT install layer does not use BuildKit cache mounts. Even when layer caching is available, package index and package download reuse can be better.

This repository already tracks the current upstream major version in `OPENCLAW_UPSTREAM_VERSION`, and the sync workflow updates that file before creating the matching tag. That file is the correct source of truth for cache warming.

## Goals

- Replace the current per-architecture publish flow with a single multi-platform build-and-push step.
- Add reusable BuildKit caching for GitHub Actions builds.
- Add a non-publishing cache warm workflow for `main`, pull requests, and manual dispatch.
- Warm the cache using the same OpenClaw major version that upcoming release tags will publish.
- Improve Dockerfile cache efficiency without changing runtime behavior.
- Cover the workflow and Dockerfile changes with Bats tests written before implementation.

## Non-Goals

- No change to published image names or tags.
- No change to runtime container behavior, entrypoint behavior, or Compose usage.
- No change to the upstream sync workflow beyond consuming its existing `OPENCLAW_UPSTREAM_VERSION` output file.
- No README update for this change set, because this repository does not currently have a `RELEASE.md` gate that would require it.

## Approaches Considered

### Approach A: Keep the current matrix publish flow and add cache settings

This is the smallest diff, but it keeps the publish path split across two architecture jobs and a manifest step. Cache reuse still exists, but the workflow stays more complex than necessary.

### Approach B: Replace the matrix with one multi-platform publish job and add a dedicated warm-cache workflow

This removes the manual manifest assembly, centralizes cache configuration, and makes the publish and warm paths share the same build definition. This is the chosen approach.

### Approach C: Introduce `docker buildx bake`

This would be reasonable if the repository were managing multiple images or more complex targets, but it adds extra indirection that is not justified by the current scope.

## Chosen Design

### Release Workflow

`.github/workflows/tag-build.yml` will keep the existing tag trigger and release creation behavior, but the image publish path will change to a single multi-platform job.

Implementation direction:

- Keep the existing `parse-tag` job.
- Replace the current matrix `build-and-push-arch` job and the `publish-manifest` job with one `build-and-push` job.
- In that job:
  - check out the repository
  - set up QEMU
  - set up Docker Buildx
  - log in to Docker Hub
  - run `docker/build-push-action@v6` once with:
    - `platforms: linux/amd64,linux/arm64`
    - `push: true`
    - tags for both `${image_tag}` and `latest`
    - `build-args: OPENCLAW_VERSION=${openclaw_major}`
    - shared `cache-from` / `cache-to` configuration

The GitHub release job will continue to run after a successful image publish, but it will no longer depend on a separate manifest creation job.

### Shared Build Cache Strategy

Builds will use the GitHub Actions cache backend with a stable scope, for example `scope=openclaw-docker`.

Implementation direction:

- Release workflow:
  - `cache-from: type=gha,scope=openclaw-docker`
  - `cache-to: type=gha,scope=openclaw-docker,mode=max`
- Warm-cache workflow:
  - use the same `cache-from` and `cache-to` settings
  - do not push images

This keeps the cache namespace stable so that PR, `main`, manual, and tag builds all contribute to and reuse the same BuildKit layer store.

### Warm-Cache Workflow

A new workflow will be added for cache warming.

Suggested file:

- `.github/workflows/docker-cache-warm.yml`

Trigger plan:

- `push` on `main`
- `pull_request` targeting `main`
- `workflow_dispatch`

Implementation direction:

- check out the repository
- read `OPENCLAW_UPSTREAM_VERSION`
- normalize the file value from `vX.Y.Z` to `X.Y.Z` for the build argument
- set up QEMU
- set up Docker Buildx
- run `docker/build-push-action@v6` with:
  - `platforms: linux/amd64,linux/arm64`
  - `push: false`
  - `build-args: OPENCLAW_VERSION` set to the normalized `OPENCLAW_UPSTREAM_VERSION` value
  - the shared `cache-from` / `cache-to` settings

The warm-cache workflow will not require Docker Hub login because it does not publish images.

### Dockerfile Cache Improvements

The Dockerfile will keep its current runtime behavior and layer ordering, but the APT install step will be updated to use BuildKit cache mounts.

Implementation direction:

- change the APT install `RUN` instruction to use cache mounts for:
  - `/var/cache/apt`
  - `/var/lib/apt/lists`
- keep the installed package list unchanged unless tests reveal a separate need
- avoid cache-clearing commands that would defeat mounted cache reuse for those paths

This should reduce repeated package metadata and package download work on GitHub-hosted runners while still keeping the final image content unchanged.

### Version Alignment Between Warm and Release Builds

The warm-cache workflow must use `OPENCLAW_UPSTREAM_VERSION` as its source of truth for `OPENCLAW_VERSION`.

Reasoning:

- `sync-upstream-major.yml` updates that file to the latest upstream major tag.
- `tag-build.yml` publishes the same upstream major version when the matching tag is pushed.
- warming `latest` or an unrelated version would not preheat the expensive installer layer for the next release.

## Test Plan

Tests will be updated before implementation changes.

- `tests/tag-build-workflow.bats`
  - assert the release workflow uses a single multi-platform build
  - assert `cache-from` and `cache-to` are configured
  - assert the old per-architecture manifest assembly is absent
- `tests/docker-build-cache-workflow.bats`
  - assert the warm-cache workflow file exists
  - assert it triggers on `push`, `pull_request`, and `workflow_dispatch`
  - assert it reads `OPENCLAW_UPSTREAM_VERSION`
  - assert it builds for both `linux/amd64` and `linux/arm64`
  - assert it sets `push: false`
  - assert it configures the shared cache scope
- `tests/dockerfile-entrypoint.bats`
  - assert the Dockerfile uses BuildKit cache mounts for APT paths

## Risks and Mitigations

### Risk: the first tag build for a newly synced upstream major still starts before the warm-cache workflow has populated the cache

Mitigation:

- keep the publish workflow fully functional without a preheated cache
- use a stable shared cache scope so later builds and patch tags reuse the warmed layers

### Risk: multi-platform single-job builds are slower when emulation is required

Mitigation:

- the job remains simpler than the current split-manifest flow
- shared remote cache should reduce repeated work enough to offset the structural change for normal runs

### Risk: APT cache mounts change the exact shell structure of the Dockerfile

Mitigation:

- keep package content unchanged
- cover the new cache mount syntax with file-based tests
- verify the Dockerfile still builds through the existing test and workflow checks
