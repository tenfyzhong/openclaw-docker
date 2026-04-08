# syntax=docker/dockerfile:1.7

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG OPENCLAW_VERSION=latest

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      gnupg \
      gosu \
      hostname \
      openssl \
      procps && \
    rm -rf /var/lib/apt/lists/*

# Install OpenClaw from the official installer script (no source COPY).
RUN curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard --version "${OPENCLAW_VERSION}"

# Ensure openclaw is discoverable from a stable path.
RUN /bin/bash -lc 'set -euo pipefail; \
    OPENCLAW_BIN="$(command -v openclaw || true)"; \
    if [[ -z "$OPENCLAW_BIN" && -x /root/.npm-global/bin/openclaw ]]; then \
      OPENCLAW_BIN=/root/.npm-global/bin/openclaw; \
    fi; \
    if [[ -z "$OPENCLAW_BIN" && -x /root/.local/bin/openclaw ]]; then \
      OPENCLAW_BIN=/root/.local/bin/openclaw; \
    fi; \
    if [[ -z "$OPENCLAW_BIN" ]]; then \
      echo "openclaw command not found after installer" >&2; \
      exit 1; \
    fi; \
    ln -sf "$OPENCLAW_BIN" /usr/local/bin/openclaw; \
    openclaw --help >/dev/null'

RUN if ! getent group node >/dev/null; then \
      groupadd --system node || groupadd node; \
    fi && \
    if ! id -u node >/dev/null 2>&1; then \
      useradd --system --create-home --gid node --shell /bin/bash node || \
      useradd --create-home --gid node --shell /bin/bash node; \
    fi

RUN cat > /usr/local/bin/openclaw-entrypoint.sh <<'ENTRYPOINT_EOF'
#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_USER="node"
OPENCLAW_GROUP="node"
OPENCLAW_HOME="/home/node"
OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-${OPENCLAW_HOME}/.openclaw}"
OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR}/openclaw.json}"
OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-${OPENCLAW_STATE_DIR}/workspace}"
OPENCLAW_GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-lan}"
OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
OPENCLAW_INIT_GATEWAY_MODE="${OPENCLAW_INIT_GATEWAY_MODE:-local}"
OPENCLAW_STDOUT_LOG_PATH="${OPENCLAW_STDOUT_LOG_PATH:-${OPENCLAW_STATE_DIR}/logs/openclaw.stdout.log}"
OPENCLAW_STDERR_LOG_PATH="${OPENCLAW_STDERR_LOG_PATH:-${OPENCLAW_STATE_DIR}/logs/openclaw.stderr.log}"

bool_to_json() {
  local raw="${1:-}"
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    1|true|yes|on)
      printf 'true'
      ;;
    *)
      printf 'false'
      ;;
  esac
}

FALLBACK_ENV_RAW="${OPENCLAW_GATEWAY_CONTROLUI_DANGEROUSLY_ALLOW_HOST_HEADER_ORIGIN_FALLBACK:-${OPENCLAW_CONTROLUI_DANGEROUSLY_ALLOW_HOST_HEADER_ORIGIN_FALLBACK:-false}}"
OPENCLAW_GATEWAY_CONTROLUI_DANGEROUSLY_ALLOW_HOST_HEADER_ORIGIN_FALLBACK_JSON="$(bool_to_json "$FALLBACK_ENV_RAW")"
export OPENCLAW_GATEWAY_CONTROLUI_DANGEROUSLY_ALLOW_HOST_HEADER_ORIGIN_FALLBACK_JSON

DEFAULT_ALLOWED_ORIGINS="[\"http://127.0.0.1:${OPENCLAW_GATEWAY_PORT}\"]"
OPENCLAW_INIT_CONTROL_UI_ALLOWED_ORIGINS="${OPENCLAW_INIT_CONTROL_UI_ALLOWED_ORIGINS:-${DEFAULT_ALLOWED_ORIGINS}}"
export OPENCLAW_INIT_CONTROL_UI_ALLOWED_ORIGINS

mkdir_state_dirs() {
  mkdir -p "$OPENCLAW_STATE_DIR"
  mkdir -p "$OPENCLAW_WORKSPACE_DIR"
  mkdir -p "$OPENCLAW_STATE_DIR/identity"
  mkdir -p "$OPENCLAW_STATE_DIR/agents/main/agent"
  mkdir -p "$OPENCLAW_STATE_DIR/agents/main/sessions"
  mkdir -p "$OPENCLAW_STATE_DIR/logs"
  mkdir -p "$(dirname "$OPENCLAW_STDOUT_LOG_PATH")"
  mkdir -p "$(dirname "$OPENCLAW_STDERR_LOG_PATH")"
  touch "$OPENCLAW_STDOUT_LOG_PATH" "$OPENCLAW_STDERR_LOG_PATH"
  mkdir -p "$OPENCLAW_WORKSPACE_DIR/.openclaw"
}

fix_permissions() {
  if [[ "$(id -u)" -ne 0 ]]; then
    return 0
  fi

  # Keep ownership fixes scoped to OpenClaw state paths to avoid rewriting
  # unrelated workspace content on bind mounts.
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

generate_gateway_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    node -e "process.stdout.write(require('node:crypto').randomBytes(32).toString('hex'))"
  fi
}

read_config_gateway_token() {
  if [[ ! -f "$OPENCLAW_CONFIG_PATH" ]]; then
    return 0
  fi

  OPENCLAW_CONFIG_PATH="$OPENCLAW_CONFIG_PATH" node <<'NODE'
const fs = require("node:fs");
const configPath = process.env.OPENCLAW_CONFIG_PATH;
try {
  const cfg = JSON.parse(fs.readFileSync(configPath, "utf8"));
  const token = cfg?.gateway?.auth?.token;
  if (typeof token === "string" && token.trim()) {
    process.stdout.write(token.trim());
  }
} catch {
  // Keep startup resilient if user config is malformed.
}
NODE
}

write_initial_config() {
  OPENCLAW_CONFIG_PATH="$OPENCLAW_CONFIG_PATH" \
  OPENCLAW_GATEWAY_BIND="$OPENCLAW_GATEWAY_BIND" \
  OPENCLAW_GATEWAY_PORT="$OPENCLAW_GATEWAY_PORT" \
  OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN" \
  OPENCLAW_INIT_GATEWAY_MODE="$OPENCLAW_INIT_GATEWAY_MODE" \
  OPENCLAW_INIT_CONTROL_UI_ALLOWED_ORIGINS="$OPENCLAW_INIT_CONTROL_UI_ALLOWED_ORIGINS" \
  OPENCLAW_GATEWAY_CONTROLUI_DANGEROUSLY_ALLOW_HOST_HEADER_ORIGIN_FALLBACK_JSON="$OPENCLAW_GATEWAY_CONTROLUI_DANGEROUSLY_ALLOW_HOST_HEADER_ORIGIN_FALLBACK_JSON" \
  node <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const configPath = process.env.OPENCLAW_CONFIG_PATH;
const bind = process.env.OPENCLAW_GATEWAY_BIND || "lan";
const mode = process.env.OPENCLAW_INIT_GATEWAY_MODE || "local";
const token = process.env.OPENCLAW_GATEWAY_TOKEN || "";
const parsedPort = Number.parseInt(process.env.OPENCLAW_GATEWAY_PORT || "18789", 10);
const gatewayPort = Number.isFinite(parsedPort) && parsedPort > 0 ? parsedPort : 18789;
const defaultOrigins = [`http://127.0.0.1:${gatewayPort}`];

let allowedOrigins = defaultOrigins;
const rawAllowedOrigins = (process.env.OPENCLAW_INIT_CONTROL_UI_ALLOWED_ORIGINS || "").trim();
if (rawAllowedOrigins.length > 0) {
  try {
    const parsed = JSON.parse(rawAllowedOrigins);
    if (Array.isArray(parsed)) {
      const normalized = parsed
        .filter((value) => typeof value === "string")
        .map((value) => value.trim())
        .filter(Boolean);
      if (normalized.length > 0) {
        allowedOrigins = normalized;
      }
    }
  } catch {
    // Keep default origins when env JSON is invalid.
  }
}

const fallback =
  (process.env.OPENCLAW_GATEWAY_CONTROLUI_DANGEROUSLY_ALLOW_HOST_HEADER_ORIGIN_FALLBACK_JSON || "false") ===
  "true";

const config = {
  gateway: {
    mode,
    bind,
    auth: {
      token,
    },
    controlUi: {
      allowedOrigins,
      dangerouslyAllowHostHeaderOriginFallback: fallback,
    },
  },
};

fs.mkdirSync(path.dirname(configPath), { recursive: true });
fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
NODE
}

ensure_config() {
  if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
    export OPENCLAW_GATEWAY_TOKEN
  fi

  if [[ ! -f "$OPENCLAW_CONFIG_PATH" ]]; then
    if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
      OPENCLAW_GATEWAY_TOKEN="$(generate_gateway_token)"
      export OPENCLAW_GATEWAY_TOKEN
    fi
    write_initial_config
    echo "openclaw: wrote initial config to $OPENCLAW_CONFIG_PATH"
  elif [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
    OPENCLAW_GATEWAY_TOKEN="$(read_config_gateway_token || true)"
    if [[ -n "$OPENCLAW_GATEWAY_TOKEN" ]]; then
      export OPENCLAW_GATEWAY_TOKEN
    fi
  fi
}

run_as_node() {
  local cmd=("$@")
  if [[ "$(id -u)" -eq 0 ]]; then
    exec gosu node:node "${cmd[@]}" >>"$OPENCLAW_STDOUT_LOG_PATH" 2>>"$OPENCLAW_STDERR_LOG_PATH"
  fi
  exec "${cmd[@]}" >>"$OPENCLAW_STDOUT_LOG_PATH" 2>>"$OPENCLAW_STDERR_LOG_PATH"
}

main() {
  if [[ "$#" -eq 0 ]]; then
    set -- gateway
  fi

  local subcommand="$1"
  shift || true

  if [[ "$subcommand" == "gateway" ]]; then
    mkdir_state_dirs
    fix_permissions
    ensure_config
    run_as_node openclaw gateway --allow-unconfigured --bind "$OPENCLAW_GATEWAY_BIND" --port "$OPENCLAW_GATEWAY_PORT" "$@"
  else
    run_as_node openclaw "$subcommand" "$@"
  fi
}

main "$@"
ENTRYPOINT_EOF

RUN mkdir -p /usr/local/libexec

COPY scripts/openclaw-wrapper.sh /usr/local/libexec/openclaw-wrapper.sh

RUN rm -f /usr/local/bin/openclaw && \
    install -m 755 /usr/local/libexec/openclaw-wrapper.sh /usr/local/bin/openclaw && \
    chmod 755 /usr/local/bin/openclaw-entrypoint.sh && \
    mkdir -p /home/node/.openclaw/workspace && \
    chown -R node:node /home/node

ENV NODE_ENV=production
ENV HOME=/home/node
ENV OPENCLAW_CONTAINER_HINT=openclaw-gateway

RUN /bin/bash -lc 'set -euo pipefail; \
    if ! command -v npm >/dev/null; then \
      echo "npm command not found; cannot install developer CLIs" >&2; \
      exit 1; \
    fi; \
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
      if [[ -z "$CLI_BIN" ]]; then \
        echo "$cmd command not found after npm install" >&2; \
        exit 1; \
      fi; \
      ln -sf "$CLI_BIN" "/usr/local/bin/$cmd"; \
      "/usr/local/bin/$cmd" --help >/dev/null; \
    done'

USER node

EXPOSE 18789 18790

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
  CMD node -e "const p=process.env.OPENCLAW_GATEWAY_PORT||'18789';fetch('http://127.0.0.1:'+p+'/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/local/bin/openclaw-entrypoint.sh"]
CMD ["gateway"]
