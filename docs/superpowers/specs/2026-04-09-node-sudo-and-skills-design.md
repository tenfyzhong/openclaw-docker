# Node Sudo and Skills Installation Design

## Context

The current image runs the `larksuite/cli` skills installation during build as `root`:

- `npm install -g --no-audit --no-fund ... @larksuite/cli`
- `npx skills add larksuite/cli -y -g`

Although `/home/node` ownership is normalized afterwards, the installation is still performed from the root execution context rather than the `node` user context.

The image also does not currently provide `sudo`, and the `node` user is not configured for passwordless sudo access.

## Goals

- Install `sudo` in the image.
- Allow the `node` user to run `sudo` without a password.
- Ensure `larksuite/cli` skills are installed using the `node` user context with `HOME=/home/node`.
- Keep the existing image behavior for the globally installed CLIs unchanged unless required by the new behavior.

## Non-Goals

- No change to the fixed runtime identity: user `node`, group `node`, home `/home/node`.
- No change to the whole-home Compose persistence model.
- No broader privilege model redesign beyond enabling passwordless sudo for `node`.

## Approaches Considered

### Approach A: Run all CLI and skills installation as `node`

This is the cleanest user-context story, but it requires changing the global npm install flow, binary link ownership assumptions, and likely the install prefix handling. The scope is larger than necessary.

### Approach B: Keep global CLI installation as `root`, run only `skills add` as `node`

This isolates the behavior change to exactly what is needed:

- `sudo` package and sudoers configuration are added by `root`
- global CLI installation stays unchanged
- `skills add` runs as `node` with `HOME=/home/node`

This is the chosen approach.

### Approach C: Keep running `skills add` as `root`, then chown the resulting files

This would still not be a real `node`-context installation. It only changes ownership after the fact, so it does not satisfy the requirement.

## Chosen Design

### Sudo Support

The Dockerfile will install `sudo` and add a dedicated sudoers drop-in for `node`.

Implementation direction:

- Add `sudo` to the apt package list.
- Create `/etc/sudoers.d/node-nopasswd`.
- The file content is:

```text
node ALL=(ALL) NOPASSWD:ALL
```

- Set the file mode to `0440`.

This keeps the sudo configuration explicit and avoids editing `/etc/sudoers` directly.

### Skills Installation Context

The Dockerfile will keep the global npm install running as `root`, but the `larksuite/cli` skills installation will run as `node`.

Implementation direction:

- Keep:

```bash
npm install -g --no-audit --no-fund opencode-ai @openai/codex @anthropic-ai/claude-code @larksuite/cli
```

- Replace the current root-context `npx skills add ...` call with a `gosu node:node` call.
- Ensure `HOME=/home/node` is explicitly set for that command.

Expected shape:

```bash
gosu node:node env HOME=/home/node npx skills add larksuite/cli -y -g
```

This makes the skills installation land in the `node` user’s home-based configuration paths.

### Ownership Expectations

The existing `/home/node` ownership normalization remains in place after the CLI and skills setup block.

This is still useful because:

- the build step uses `root` for package installation
- the image should continue to guarantee `node:node` ownership for `/home/node`

## Test Plan

Tests will be added first in `tests/dockerfile-entrypoint.bats` to assert:

- `sudo` is included in the apt package install list
- the Dockerfile writes a `node ALL=(ALL) NOPASSWD:ALL` sudoers rule
- the Dockerfile runs `npx skills add larksuite/cli -y -g` via `gosu node:node`
- the skills install command explicitly sets `HOME=/home/node`

After implementation:

- run `bats tests/dockerfile-entrypoint.bats`
- run the existing Compose-related bats suite to confirm no unintended regressions in adjacent assertions

## Risks and Mitigations

### Risk: passwordless sudo broadens privilege inside the container

Mitigation:

- This is an explicit requested behavior.
- Limit the change to the `node` user only and document it through the Dockerfile implementation.

### Risk: `npx skills add` under `node` cannot find the globally installed CLI package

Mitigation:

- Keep the global npm install unchanged first.
- Verify the Dockerfile command shape with tests and then validate via image build if needed.

### Risk: partial environment propagation changes where skills are installed

Mitigation:

- Set `HOME=/home/node` explicitly on the `gosu node:node` invocation instead of relying on inherited environment behavior.
