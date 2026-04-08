#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WRAPPER_PATH="$REPO_ROOT/scripts/openclaw-wrapper.sh"
  REAL_BIN="$BATS_TEST_TMPDIR/openclaw-real"

  cat >"$REAL_BIN" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == *"--json"* ]]; then
  cat <<'JSON'
{
  "logFile": "/tmp/openclaw-999/openclaw-2026-04-08.log",
  "service": {
    "label": "systemd",
    "loaded": false,
    "loadedText": "enabled",
    "notLoadedText": "disabled",
    "command": null,
    "runtime": {
      "status": "unknown",
      "detail": "systemctl not available; systemd user services are required on Linux."
    },
    "configAudit": {
      "ok": true,
      "issues": []
    }
  },
  "config": {
    "cli": {
      "path": "/home/node/.openclaw/openclaw.json",
      "exists": true,
      "valid": true
    },
    "daemon": {
      "path": "/home/node/.openclaw/openclaw.json",
      "exists": true,
      "valid": true
    }
  },
  "gateway": {
    "bindMode": "lan",
    "bindHost": "0.0.0.0",
    "port": 28789,
    "portSource": "env/config",
    "probeUrl": "ws://127.0.0.1:28789"
  },
  "rpc": {
    "ok": true,
    "url": "ws://127.0.0.1:28789"
  }
}
JSON
  exit 0
fi

cat >&2 <<'ERR'
systemd user services unavailable.
systemd user services are unavailable; install/enable systemd or run the gateway under your supervisor.
If you're in a container, run the gateway in the foreground instead of `openclaw gateway`.
ERR

cat <<'OUT'
Service: systemd (disabled)
File logs: /tmp/openclaw-999/openclaw-2026-04-08.log

Config (cli): ~/.openclaw/openclaw.json
Config (service): ~/.openclaw/openclaw.json

Gateway: bind=lan (0.0.0.0), port=28789 (env/config)
Probe target: ws://127.0.0.1:28789
Dashboard: http://172.21.0.2:28789/
Probe note: bind=lan listens on 0.0.0.0 (all interfaces); probing via 127.0.0.1.

Runtime: unknown (systemctl not available; systemd user services are required on Linux.)
RPC probe: ok

Troubles: run openclaw status
Troubleshooting: https://docs.openclaw.ai/troubleshooting
OUT
EOF
  chmod +x "$REAL_BIN"
}

@test "wrapper rewrites healthy container gateway status output" {
  run env OPENCLAW_REAL_BIN="$REAL_BIN" "$WRAPPER_PATH" gateway status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Service: container (foreground)"* ]]
  [[ "$output" == *"Runtime: running (container foreground)"* ]]
  [[ "$output" == *"RPC probe: ok"* ]]
  [[ "$output" != *"systemd user services unavailable."* ]]
}

@test "wrapper rewrites healthy container gateway status json" {
  run env OPENCLAW_REAL_BIN="$REAL_BIN" "$WRAPPER_PATH" gateway status --json

  [ "$status" -eq 0 ]
  [[ "$output" == *'"label": "container"'* ]]
  [[ "$output" == *'"loaded": true'* ]]
  [[ "$output" == *'"status": "running"'* ]]
  [[ "$output" == *'"detail": "container foreground"'* ]]
}
