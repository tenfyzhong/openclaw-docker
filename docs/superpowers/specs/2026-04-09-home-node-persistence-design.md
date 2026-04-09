# Home Directory Persistence Compatibility Design

## Context

The current image and Compose setup have two related problems:

1. The image build leaves root-owned files and directories under `/home/node`, because build steps run as `root` after `HOME` is set to `/home/node`.
2. The default Compose persistence only mounts `/home/node/.openclaw` and `/home/node/.openclaw/workspace`, so other runtime state created in `/home/node` is not persisted.

This causes runtime failures when tools inside the container need to create or update files in `/home/node`, and it also causes state loss for files that live outside `.openclaw`.

## Goals

- Ensure `/home/node` itself is owned by `node:node` in the built image.
- Ensure files and directories created during image build under `/home/node` do not remain owned by `root`.
- Preserve backward compatibility for the existing mount model based on `OPENCLAW_CONFIG_DIR` and `OPENCLAW_WORKSPACE_DIR`.
- Add a supported way to mount the entire `/home/node` directory from the host.
- Document both persistence modes and the migration path in `README.md`.

## Non-Goals

- No change to the fixed runtime identity: user `node`, group `node`, home `/home/node`.
- No removal of the existing `.openclaw`-based persistence mode.
- No unrelated refactor of gateway bootstrap, logging, or CLI wrapper behavior.

## Approaches Considered

### Approach A: Replace the old mount model with a single `/home/node` mount

This is the simplest runtime model, but it is not acceptable because it breaks existing users who already depend on `OPENCLAW_CONFIG_DIR` and `OPENCLAW_WORKSPACE_DIR`.

### Approach B: Keep only the old mount model and extend permission repair

This avoids Compose changes, but it does not solve the persistence gap for files outside `.openclaw`. It addresses only part of the problem.

### Approach C: Support both mount models and recommend whole-home mounting

This keeps current users working while giving new users a correct default path for complete persistence. This is the chosen approach.

## Chosen Design

### Image Build Ownership

The Dockerfile will ensure that any build step writing into `/home/node` does not leave root-owned artifacts behind.

Implementation direction:

- Keep `/home/node` created before runtime and explicitly owned by `node:node`.
- After the build steps that install developer CLIs and skills, normalize ownership for `/home/node` back to `node:node`.
- Add tests that assert:
  - `/home/node` is owned by `node:node`
  - the Dockerfile contains an ownership normalization step after the root-run install phase

### Runtime Permission Repair

The entrypoint permission repair will guarantee that `/home/node` itself is owned by `node:node`.

Implementation direction:

- Continue to avoid broad recursive ownership changes on arbitrary bind-mounted workspace content.
- Ensure the entrypoint fixes ownership for:
  - `/home/node`
  - the state directory paths already managed today
  - any container-managed directories under `/home/node` that are expected to be writable by the `node` user

The intent is to guarantee container usability without recursively rewriting unrelated user project content under mounted workspaces.

### Compose Persistence Modes

Two supported modes will be documented.

#### Legacy mode

Legacy mode remains available and keeps the current variables:

- `OPENCLAW_CONFIG_DIR`
- `OPENCLAW_WORKSPACE_DIR`

This mode persists `.openclaw` state and workspace content only.

#### Whole-home mode

A new optional variable will be introduced for mounting an entire host directory to `/home/node`.

Proposed variable:

- `OPENCLAW_HOME_DIR`

Behavior:

- When users want full persistence, they will mount one host directory to `/home/node`.
- This mode is recommended for new deployments because it also preserves `.npm`, `.agents`, `.codex`, `.cache`, and other home-directory content.

Compatibility rule:

- The Compose configuration and documentation must make it clear that whole-home mode and legacy split mounts are alternative persistence strategies and should not be used together.

### README Compatibility Documentation

`README.md` will be updated to explain:

- Why whole-home mounting is recommended
- How to keep using the legacy mount mode unchanged
- How to switch from legacy mode to whole-home mode
- What data each mode persists
- That `/home/node` and its managed contents are expected to be writable by the `node` user

The migration guidance should include a concrete example layout showing:

- old mode: host config dir and host workspace dir
- new mode: one host home dir mounted to `/home/node`

## Test Plan

Tests will be added or updated before implementation changes:

- `tests/dockerfile-entrypoint.bats`
  - assert `/home/node` ownership normalization is present
  - assert normalization happens after the root-run package install block
- `tests/docker-compose.bats`
  - assert legacy mount variables remain supported
  - assert whole-home mount support is documented in Compose configuration
- `README.md`
  - covered by existing file-based assertions only if needed; otherwise validated through direct content review and final verification

## Risks and Mitigations

### Risk: users enable both mount models at once

Mitigation:

- Document them as mutually exclusive.
- Keep Compose structure straightforward so the active mount strategy is obvious.

### Risk: recursive chown over large bind mounts slows startup or modifies host ownership too broadly

Mitigation:

- Limit recursive ownership repair to container-managed state paths.
- Only guarantee direct ownership for `/home/node` itself and managed subdirectories.

### Risk: documentation and implementation drift

Mitigation:

- Update README in the same change set as Dockerfile and Compose updates.
- Verify the documented environment variables and mount targets match the final files exactly.
