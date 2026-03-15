# openclaw-docker

Containerized OpenClaw Gateway setup with Docker and Docker Compose.

This repository provides:

- A production-oriented `Dockerfile` based on Ubuntu 24.04
- Automatic OpenClaw installation from the official installer
- Preinstalled Lark tools CLI (`@larksuite/openclaw-lark-tools`) for direct in-container use
- A startup entrypoint that initializes `openclaw.json` on first run
- Persistent config/workspace volumes for local development and daily use
- A ready-to-run `docker-compose.yml` service definition

## Repository Layout

- `Dockerfile`: image build and gateway entrypoint script
- `docker-compose.yml`: local runtime configuration
- `scripts/build-image.sh`: local image build/tag helper for Compose
- `scripts/create-tag.sh`: local release tag creation helper
- `.github/workflows/tag-build.yml`: builds and pushes Docker image on tag push
- `.github/workflows/sync-upstream-major.yml`: manual workflow to sync latest upstream major tag
- `.github/workflows/bats-tests.yml`: runs bats unit tests for release and workflow guardrails
- `tests/create-tag.bats`: unit tests for release tag script
- `tests/build-image.bats`: unit tests for local image build/tag script
- `tests/docker-compose.bats`: unit tests for compose image-only guardrails
- `tests/tag-build-workflow.bats`: unit tests for Docker image publish workflow guardrails
- `LICENSE`: MIT license

## Prerequisites

- Docker Engine with Docker Compose v2 (or Podman with podman-compose)
- Network access during image build (for package install and OpenClaw installer)

## Using Podman Instead of Docker

This project supports both Docker and Podman. To use Podman:

1. Install Podman and podman-compose:
```bash
sudo apt-get install podman uidmap
pip install podman-compose
```

2. Set the `CONTAINER_RUNTIME` environment variable:
```bash
export CONTAINER_RUNTIME=podman
```

3. Use the provided wrapper script for compose commands:
```bash
./scripts/compose.sh up -d
./scripts/compose.sh ps
./scripts/compose.sh down
```

Or use podman-compose directly:
```bash
podman-compose up -d
```

For building images with Podman:
```bash
CONTAINER_RUNTIME=podman ./scripts/build-image.sh
```

## Quick Start

1. Build local image for the default tag (`latest`):

```bash
./scripts/build-image.sh
```

2. Start service:

```bash
docker compose up -d
# Or use the wrapper script: ./scripts/compose.sh up -d
```

3. Check container status:

```bash
docker compose ps
# Or: ./scripts/compose.sh ps
```

4. Check gateway health endpoint:

```bash
curl http://127.0.0.1:18789/healthz
```

5. Read gateway logs:

```bash
docker compose exec openclaw-gateway tail -f /home/node/.openclaw/logs/openclaw.stdout.log
docker compose exec openclaw-gateway tail -f /home/node/.openclaw/logs/openclaw.stderr.log
# Or: ./scripts/compose.sh exec openclaw-gateway tail -f /home/node/.openclaw/logs/openclaw.stdout.log
```

6. Stop service:

```bash
docker compose down
# Or: ./scripts/compose.sh down
```

## First-Time Onboarding in Container

After the first startup, enter the container and run onboarding:

```bash
docker compose exec openclaw-gateway bash
openclaw onboard
```

Notes for first-time setup:

- During onboarding, the gateway process may restart.
- If your current terminal session is interrupted, enter the container again and run `openclaw onboard` again.
- Existing onboarding progress is reused from persisted config, so you only need to complete the remaining steps.

## Preinstalled Lark Tools CLI

The image preinstalls `@larksuite/openclaw-lark-tools`. Inside the running container, use:

```bash
docker compose exec -u node openclaw-gateway feishu-plugin-onboard install
# Alias (same command):
docker compose exec -u node openclaw-gateway openclaw-lark-tools install
```

This is equivalent to `npx -y @larksuite/openclaw-lark-tools install`, but without downloading the CLI package each time.

## Persistence and Default Paths

By default, Compose maps the following host directories:

- `./.docker/openclaw/config` -> `/home/node/.openclaw`
- `./.docker/openclaw/workspace` -> `/home/node/.openclaw/workspace`

The container entrypoint creates these directories automatically when needed.

Gateway process output is redirected to files inside the state volume:

- stdout: `/home/node/.openclaw/logs/openclaw.stdout.log`
- stderr: `/home/node/.openclaw/logs/openclaw.stderr.log`

## First-Run Config Initialization

If `/home/node/.openclaw/openclaw.json` does not exist, the entrypoint generates it with:

- `gateway.mode` from `OPENCLAW_INIT_GATEWAY_MODE` (default: `local`)
- `gateway.bind` from `OPENCLAW_GATEWAY_BIND` (default: `lan`)
- `gateway.auth.token` from `OPENCLAW_GATEWAY_TOKEN`, or auto-generated when empty
- `gateway.controlUi.allowedOrigins` from `OPENCLAW_INIT_CONTROL_UI_ALLOWED_ORIGINS`, or `http://127.0.0.1:<port>` by default

If a token is generated automatically, it is persisted in `openclaw.json` and reused on later starts.

## Main Environment Variables

You can place these in a `.env` file next to `docker-compose.yml`.

| Variable | Default | Description |
| --- | --- | --- |
| `OPENCLAW_VERSION` | `latest` | Runtime image tag in Compose (also used by `scripts/build-image.sh` when `--tag` is omitted) |
| `OPENCLAW_GATEWAY_BIND` | `lan` | Gateway bind strategy passed to `openclaw gateway --bind` |
| `OPENCLAW_GATEWAY_PORT` | `18789` | Gateway HTTP port |
| `OPENCLAW_BRIDGE_PORT` | `18790` | Bridge port exposed by Compose |
| `OPENCLAW_GATEWAY_TOKEN` | empty | Gateway auth token. If empty and config missing, one is generated |
| `OPENCLAW_INIT_GATEWAY_MODE` | `local` | Initial `gateway.mode` for generated config |
| `OPENCLAW_INIT_CONTROL_UI_ALLOWED_ORIGINS` | auto | JSON array string for allowed control UI origins |
| `OPENCLAW_GATEWAY_CONTROLUI_DANGEROUSLY_ALLOW_HOST_HEADER_ORIGIN_FALLBACK` | `false` | Initial fallback behavior in generated config |
| `OPENCLAW_STDOUT_LOG_PATH` | `/home/node/.openclaw/logs/openclaw.stdout.log` | OpenClaw process stdout log file path |
| `OPENCLAW_STDERR_LOG_PATH` | `/home/node/.openclaw/logs/openclaw.stderr.log` | OpenClaw process stderr log file path |
| `OPENCLAW_ALLOW_INSECURE_PRIVATE_WS` | empty | Forwarded to container runtime environment |
| `OPENCLAW_CONFIG_DIR` | `./.docker/openclaw/config` | Host directory for OpenClaw state/config |
| `OPENCLAW_WORKSPACE_DIR` | `./.docker/openclaw/workspace` | Host directory for workspace |
| `CLAUDE_AI_SESSION_KEY` | empty | Optional key forwarded into container |
| `CLAUDE_WEB_SESSION_KEY` | empty | Optional key forwarded into container |
| `CLAUDE_WEB_COOKIE` | empty | Optional cookie forwarded into container |

## Getting the Current Gateway Token

If you did not set `OPENCLAW_GATEWAY_TOKEN` manually, inspect the generated config:

```bash
jq -r '.gateway.auth.token' ./.docker/openclaw/config/openclaw.json
```

If `jq` is not installed:

```bash
grep -n '"token"' ./.docker/openclaw/config/openclaw.json
```

## Local Image Build and Run

Build image with helper script:

```bash
./scripts/build-image.sh --tag 2026.3.11.2
```

Or build manually:

```bash
docker build --build-arg OPENCLAW_VERSION=2026.3.11 -t tenfyzhong/openclaw:2026.3.11.2 .
```

When using Compose with a custom tag, use the same `OPENCLAW_VERSION` value:

```bash
OPENCLAW_VERSION=2026.3.11.2 docker compose up -d
```

Run container directly:

```bash
docker run --rm -it \
  -p 18789:18789 -p 18790:18790 \
  -e OPENCLAW_GATEWAY_BIND=lan \
  -v "$PWD/.docker/openclaw/config:/home/node/.openclaw" \
  -v "$PWD/.docker/openclaw/workspace:/home/node/.openclaw/workspace" \
  tenfyzhong/openclaw:2026.3.11.2 gateway
```

## Release Tag and Image Automation

### Create a local release tag

Use the script from repository root:

```bash
./scripts/create-tag.sh
```

Optional: force a specific major version:

```bash
./scripts/create-tag.sh --major 2026.3.11
```

Script behavior:

- Always runs `git fetch --tags origin` first
- Major version source is `openclaw/openclaw` release tags:
  - `vX.Y.Z`
  - `vX.Y.Z-N` (treated as major `vX.Y.Z`)
  - Pre-release tags like `-beta.*` are ignored
- If `--major` is provided, it must exist in `openclaw/openclaw`
- If local repo does not have `vX.Y.Z`, it creates `vX.Y.Z`
- If local repo already has `vX.Y.Z`, it creates the next patch tag `vX.Y.Z.N` (auto increment)
- It only creates local tag; push is manual

Push manually when ready:

```bash
git push origin <tag>
```

### Auto build on tag push

Workflow: `.github/workflows/tag-build.yml`

- Trigger: `git push` of tag matching `v*`
- Docker tags pushed:
  - `tenfyzhong/openclaw:<git-tag-without-v>`
  - `tenfyzhong/openclaw:latest`
- Platforms:
  - `linux/amd64`
  - `linux/arm64`
- Build arg `OPENCLAW_VERSION` always uses major base (`X.Y.Z`)
  - Example: git tag `v2026.3.11.2` builds with `OPENCLAW_VERSION=2026.3.11`
  - Both tags are published as multi-arch manifest lists on Docker Hub

### Manual multi-arch push to Docker Hub

```bash
docker login -u "$DOCKERHUB_USERNAME"
docker buildx create --name openclaw-multiarch --driver docker-container --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg OPENCLAW_VERSION=2026.3.11 \
  -t tenfyzhong/openclaw:2026.3.11-local \
  --push \
  .
```

If buildx builder already exists, reuse it and skip `docker buildx create`.

### Manual sync entry (GitHub Actions)

Workflow: `.github/workflows/sync-upstream-major.yml`

Run manually from GitHub:

1. Open repository `Actions`
2. Select `Sync Latest Upstream Major Tag`
3. Click `Run workflow`

Behavior:

- Fetches latest stable major tag from `openclaw/openclaw`
- Runs `git fetch --tags origin`
- If this repo already has that major tag, exits with no changes
- If missing, creates and pushes that major tag
- Pushed tag triggers `tag-build.yml` to build/push Docker image

## Required GitHub Secrets

Configure repository secrets in `Settings` -> `Secrets and variables` -> `Actions`:

- `DOCKERHUB_USERNAME`: Docker Hub username
- `DOCKERHUB_TOKEN`: Docker Hub access token (for `docker/login-action`)
- `RELEASE_PUSH_TOKEN`: GitHub token used by manual sync workflow to push tags

### How to create `RELEASE_PUSH_TOKEN`

Recommended: Fine-grained personal access token.

1. GitHub avatar -> `Settings`
2. `Developer settings` -> `Personal access tokens` -> `Fine-grained tokens`
3. Click `Generate new token`
4. Set token name and expiration
5. `Repository access`: select only this repository
6. `Repository permissions`:
   - `Contents`: `Read and write`
   - `Metadata`: `Read-only` (default)
7. Generate token and copy it immediately
8. Go back to repository `Settings` -> `Secrets and variables` -> `Actions`
9. `New repository secret`
10. Name: `RELEASE_PUSH_TOKEN`
11. Value: the generated token

After saving, rerun `Sync Latest Upstream Major Tag` workflow.

## Run release script tests

```bash
bats tests/*.bats
```

CI workflow `Bats Unit Tests` runs automatically on:

- All pull requests targeting `main`
- Pushes to `main`

## Protect `main` branch on GitHub

To require CI success before merge and block direct pushes:

1. Go to repository `Settings` -> `Branches` -> `Add branch protection rule`
2. Set `Branch name pattern` to `main`
3. Enable `Require a pull request before merging`
4. Enable `Require status checks to pass before merging`
5. Select status check `Bats Unit Tests / bats`
6. Enable `Require branches to be up to date before merging` (recommended)
7. Enable `Include administrators` (recommended)
8. Disable direct push by enabling `Restrict who can push to matching branches` and leaving only trusted automation/users
9. Keep `Allow force pushes` and `Allow deletions` disabled

## Security Notes

- The default bind mode is `lan`. Ensure your host firewall and network policy are appropriate.
- Use a strong, private `OPENCLAW_GATEWAY_TOKEN` for non-local environments.
- Keep mounted config directories private because they contain authentication token data.

## License

This project is licensed under the MIT License. See `LICENSE` for details.
