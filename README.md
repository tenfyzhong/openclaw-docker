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
| `OPENCLAW_IMAGE` | `openclaw:local` | Image name used by Compose |
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

## Security Notes

- The default bind mode is `lan`. Ensure your host firewall and network policy are appropriate.
- Use a strong, private `OPENCLAW_GATEWAY_TOKEN` for non-local environments.
- Keep mounted config directories private because they contain authentication token data.

## License

This project is licensed under the MIT License. See `LICENSE` for details.
