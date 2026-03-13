# openclaw-docker

Containerized OpenClaw Gateway setup with Docker and Docker Compose.

This repository provides:

- A production-oriented `Dockerfile` based on Ubuntu 24.04
- Automatic OpenClaw installation from the official installer
- A startup entrypoint that initializes `openclaw.json` on first run
- Persistent config/workspace volumes for local development and daily use
- A ready-to-run `docker-compose.yml` service definition

## Repository Layout

- `Dockerfile`: image build and gateway entrypoint script
- `docker-compose.yml`: local runtime configuration
- `scripts/create-tag.sh`: local release tag creation helper
- `.github/workflows/tag-build.yml`: builds and pushes Docker image on tag push
- `.github/workflows/sync-upstream-major.yml`: manual workflow to sync latest upstream major tag
- `.github/workflows/bats-tests.yml`: runs bats unit tests for release script changes
- `tests/create-tag.bats`: unit tests for release tag script
- `LICENSE`: MIT license

## Prerequisites

- Docker Engine with Docker Compose v2
- Network access during image build (for package install and OpenClaw installer)

## Quick Start

1. Build and start:

```bash
docker compose up -d --build
```

2. Check container status:

```bash
docker compose ps
```

3. Check gateway health endpoint:

```bash
curl http://127.0.0.1:18789/healthz
```

4. Read logs:

```bash
docker compose logs -f openclaw-gateway
```

5. Stop service:

```bash
docker compose down
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

## Persistence and Default Paths

By default, Compose maps the following host directories:

- `./.docker/openclaw/config` -> `/home/node/.openclaw`
- `./.docker/openclaw/workspace` -> `/home/node/.openclaw/workspace`

The container entrypoint creates these directories automatically when needed.

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
| `OPENCLAW_VERSION` | `latest` | OpenClaw version passed to image build (`install.sh --version`) |
| `OPENCLAW_GATEWAY_BIND` | `lan` | Gateway bind strategy passed to `openclaw gateway --bind` |
| `OPENCLAW_GATEWAY_PORT` | `18789` | Gateway HTTP port |
| `OPENCLAW_BRIDGE_PORT` | `18790` | Bridge port exposed by Compose |
| `OPENCLAW_GATEWAY_TOKEN` | empty | Gateway auth token. If empty and config missing, one is generated |
| `OPENCLAW_INIT_GATEWAY_MODE` | `local` | Initial `gateway.mode` for generated config |
| `OPENCLAW_INIT_CONTROL_UI_ALLOWED_ORIGINS` | auto | JSON array string for allowed control UI origins |
| `OPENCLAW_GATEWAY_CONTROLUI_DANGEROUSLY_ALLOW_HOST_HEADER_ORIGIN_FALLBACK` | `false` | Initial fallback behavior in generated config |
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

## Manual Image Build and Run

Build image:

```bash
docker build --build-arg OPENCLAW_VERSION=2026.3.11 -t openclaw:local .
```

Run container directly:

```bash
docker run --rm -it \
  -p 18789:18789 -p 18790:18790 \
  -e OPENCLAW_GATEWAY_BIND=lan \
  -v "$PWD/.docker/openclaw/config:/home/node/.openclaw" \
  -v "$PWD/.docker/openclaw/workspace:/home/node/.openclaw/workspace" \
  openclaw:local gateway
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
- Major version source is `openclaw/openclaw` stable tags only (`vX.Y.Z`, excludes `-beta.*`)
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
- Build arg `OPENCLAW_VERSION` always uses major base (`X.Y.Z`)
  - Example: git tag `v2026.3.11.2` builds with `OPENCLAW_VERSION=2026.3.11`

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
bats tests/create-tag.bats
```

CI workflow `Bats Unit Tests` runs automatically on pull requests that modify:

- `scripts/create-tag.sh`
- `tests/create-tag.bats`
- `.github/workflows/bats-tests.yml`

## Security Notes

- The default bind mode is `lan`. Ensure your host firewall and network policy are appropriate.
- Use a strong, private `OPENCLAW_GATEWAY_TOKEN` for non-local environments.
- Keep mounted config directories private because they contain authentication token data.

## License

This project is licensed under the MIT License. See `LICENSE` for details.
