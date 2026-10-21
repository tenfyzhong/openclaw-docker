#!/usr/bin/env bats

setup() {
  DOCKERFILE="$BATS_TEST_DIRNAME/../Dockerfile"
}

@test "dockerfile pins the patched official Node runtime and retains Ubuntu" {
  run grep '^FROM ' "$DOCKERFILE"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = 'FROM node:24.22.1-bookworm-slim@sha256:1681862882da07ee5476fee047bcf34138833f1df42633bb25bcb0f438d5bf3d AS node-runtime' ]
  [ "${lines[1]}" = 'FROM ubuntu:24.04' ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "dockerfile provisions Node and retains the wrapper's global npm path before install" {
  installer_line="$(grep -nF 'https://openclaw.ai/install.sh' "$DOCKERFILE" | cut -d: -f1)"
  for required in \
    'libatomic1' 'libstdc++6' \
    'COPY --from=node-runtime /usr/local/bin/node /usr/local/bin/node' \
    'COPY --from=node-runtime /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm' \
    'ENV NPM_CONFIG_PREFIX=/usr' \
    '../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm' \
    '../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx'; do
    required_line="$(grep -nF "$required" "$DOCKERFILE" | cut -d: -f1)"
    [ -n "$required_line" ]
    [ "$required_line" -lt "$installer_line" ]
  done
}

@test "dockerfile checks exact Node and npm prefix before installation and as runtime user" {
  run grep -nF 'test "$(node --version)" = "v24.22.1"' "$DOCKERFILE"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  first_guard="${lines[0]%%:*}"
  last_guard="${lines[1]%%:*}"
  installer_line="$(grep -nF 'https://openclaw.ai/install.sh' "$DOCKERFILE" | cut -d: -f1)"
  user_line="$(grep -nF 'USER node' "$DOCKERFILE" | cut -d: -f1)"
  [ "$first_guard" -lt "$installer_line" ]
  [ "$last_guard" -gt "$user_line" ]
  run grep -Fc 'test "$(npm config get prefix)" = "/usr"' "$DOCKERFILE"
  [ "$output" = '2' ]
}

@test "runtime guard rejects old or replaced Node" {
  guard="$(grep -F 'RUN test "$(node --version)"' "$DOCKERFILE" | sed 's/^RUN //; s/ && \\$/ /')"
  for version in v24.22.0 v22.23.4 v26.12.1; do
    # Execute the exact Dockerfile guard with a local fake runtime, not an installer.
    run env VERSION="$version" GUARD="$guard" bash -c 'node() { printf "%s\n" "$VERSION"; }; eval "$GUARD"'
    [ "$status" -eq 1 ]
  done
  run env VERSION=v24.22.1 GUARD="$guard" bash -c 'node() { printf "%s\n" "$VERSION"; }; eval "$GUARD"'
  [ "$status" -eq 0 ]
}
