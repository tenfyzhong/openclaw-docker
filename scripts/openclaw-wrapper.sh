#!/usr/bin/env bash
set -euo pipefail

REAL_OPENCLAW_BIN="${OPENCLAW_REAL_BIN:-/usr/bin/openclaw}"

has_arg() {
  local needle="$1"
  shift || true

  local arg
  for arg in "$@"; do
    if [[ "$arg" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
}

is_gateway_status_command() {
  local saw_gateway=0
  local arg

  for arg in "$@"; do
    case "$arg" in
      -h|--help)
        return 1
        ;;
      gateway)
        saw_gateway=1
        ;;
      status)
        if [[ "$saw_gateway" -eq 1 ]]; then
          return 0
        fi
        ;;
    esac
  done

  return 1
}

run_status_json() {
  if has_arg "--json" "$@"; then
    "$REAL_OPENCLAW_BIN" "$@"
    return
  fi

  "$REAL_OPENCLAW_BIN" "$@" --json
}

should_rewrite_status() {
  STATUS_JSON="$1" node <<'NODE'
const payload = JSON.parse(process.env.STATUS_JSON || "{}");
const runtime = payload?.service?.runtime ?? {};
const detail = typeof runtime.detail === "string" ? runtime.detail : "";
const rpcOk = payload?.rpc?.ok === true;

process.exit(
  rpcOk && runtime.status === "unknown" && detail.includes("systemctl not available")
    ? 0
    : 1,
);
NODE
}

rewrite_status_json() {
  STATUS_JSON="$1" node <<'NODE'
const payload = JSON.parse(process.env.STATUS_JSON || "{}");

payload.service = {
  ...(payload.service || {}),
  label: "container",
  loaded: true,
  loadedText: "foreground",
  notLoadedText: "not running",
  runtime: {
    ...(payload.service?.runtime || {}),
    status: "running",
    state: "active",
    detail: "container foreground",
  },
};

process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
NODE
}

render_status_text_from_json() {
  STATUS_JSON="$1" node <<'NODE'
const payload = JSON.parse(process.env.STATUS_JSON || "{}");

const formatConfigLine = (label, config) => {
  if (!config?.path) {
    return null;
  }

  const suffix = [
    config.exists === false ? "missing" : null,
    config.valid === false ? "invalid" : null,
  ]
    .filter(Boolean)
    .map((value) => `(${value})`)
    .join(" ");

  return `${label}: ${config.path}${suffix ? ` ${suffix}` : ""}`;
};

const lines = [];

lines.push("Service: container (foreground)");

if (payload.logFile) {
  lines.push(`File logs: ${payload.logFile}`);
  lines.push("");
}

const cliConfigLine = formatConfigLine("Config (cli)", payload.config?.cli);
if (cliConfigLine) {
  lines.push(cliConfigLine);
}

const daemonConfigLine = formatConfigLine("Config (service)", payload.config?.daemon);
if (daemonConfigLine) {
  lines.push(daemonConfigLine);
}

if (cliConfigLine || daemonConfigLine) {
  lines.push("");
}

if (payload.gateway) {
  const bindHost = payload.gateway.bindHost || "n/a";
  lines.push(
    `Gateway: bind=${payload.gateway.bindMode} (${bindHost}), port=${payload.gateway.port} (${payload.gateway.portSource})`,
  );
  lines.push(`Probe target: ${payload.gateway.probeUrl}`);
  if (payload.gateway.probeNote) {
    lines.push(`Probe note: ${payload.gateway.probeNote}`);
  }
  lines.push("");
}

lines.push("Runtime: running (container foreground)");
lines.push(`RPC probe: ${payload.rpc?.ok === true ? "ok" : "failed"}`);
lines.push("");
lines.push("Troubles: run openclaw status");
lines.push("Troubleshooting: https://docs.openclaw.ai/troubleshooting");

process.stdout.write(`${lines.join("\n")}\n`);
NODE
}

main() {
  if ! is_gateway_status_command "$@"; then
    exec "$REAL_OPENCLAW_BIN" "$@"
  fi

  local json_output
  if ! json_output="$(run_status_json "$@")"; then
    exit $?
  fi

  if ! should_rewrite_status "$json_output"; then
    if has_arg "--json" "$@"; then
      printf '%s\n' "$json_output"
      return
    fi

    exec "$REAL_OPENCLAW_BIN" "$@"
  fi

  if has_arg "--json" "$@"; then
    rewrite_status_json "$json_output"
    return
  fi

  local transformed_json
  transformed_json="$(rewrite_status_json "$json_output")"
  render_status_text_from_json "$transformed_json"
}

main "$@"
