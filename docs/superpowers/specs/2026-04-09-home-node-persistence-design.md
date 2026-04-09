# Home Directory Persistence Compatibility Design

## Context

The current image and Compose setup have two related problems:

1. The image build leaves root-owned files and directories under `/home/node`, because build steps run as `root` after `HOME` is set to `/home/node`.
2. The default Compose persistence only mounts `/home/node/.openclaw` and `/home/node/.openclaw/workspace`, so other runtime state created in `/home/node` is not persisted.

This causes runtime failures when tools inside the container need to create or update files in `/home/node`, and it also causes state loss for files that live outside `.openclaw`.

## Goals

- Ensure `/home/node` itself is owned by `node:node` in the built image.
- Ensure files and directories created during image build under `/home/node` do not remain owned by `root`.
- Add a supported way to mount the entire `/home/node` directory from the host.
- Document how users migrate from the previous split-mount layout into the `/home/node` whole-home layout in `README.md`.

## Non-Goals

- No change to the fixed runtime identity: user `node`, group `node`, home `/home/node`.
- No runtime compatibility layer in `docker-compose.yml` for the previous split-mount layout.
- No unrelated refactor of gateway bootstrap, logging, or CLI wrapper behavior.

## Approaches Considered

### Approach A: Replace the old mount model with a single `/home/node` mount

This is the simplest runtime model, but it is not acceptable because it breaks existing users who already depend on `OPENCLAW_CONFIG_DIR` and `OPENCLAW_WORKSPACE_DIR`.

### Approach B: Keep only the old mount model and extend permission repair

This avoids Compose changes, but it does not solve the persistence gap for files outside `.openclaw`. It addresses only part of the problem.

### Approach C: Use whole-home mounting only and document migration from the old layout

This keeps the Compose file simple and makes the runtime behavior unambiguous, while still giving existing users a documented path to move their data forward. This is the chosen approach.

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

### Compose Persistence

The current Compose file will support only whole-home mounting.

A new optional variable will be introduced for mounting an entire host directory to `/home/node`.

Proposed variable:

- `OPENCLAW_HOME_DIR`

Behavior:

- When users want full persistence, they will mount one host directory to `/home/node`.
- This mode is recommended for new deployments because it also preserves `.npm`, `.agents`, `.codex`, `.cache`, and other home-directory content.
In the Compose file, this mode is the default `openclaw-gateway` service.

Migration rule:

- The Compose configuration will not keep the old split mounts.
- The documentation must explain how to copy data from the previous `OPENCLAW_CONFIG_DIR` and `OPENCLAW_WORKSPACE_DIR` layout into the new `OPENCLAW_HOME_DIR` layout.

### README Compatibility Documentation

`README.md` will be updated to explain:

- Why whole-home mounting is recommended
- That the current Compose file mounts the full `/home/node` directory
- How to migrate from the old split-mount layout to whole-home mode
- What data is preserved in the whole-home layout
- That `/home/node` and its managed contents are expected to be writable by the `node` user

The migration guidance should include a concrete example layout showing:

- old layout: host config dir and host workspace dir
- new layout: one host home dir mounted to `/home/node`

## Test Plan

Tests will be added or updated before implementation changes:

- `tests/dockerfile-entrypoint.bats`
  - assert `/home/node` ownership normalization is present
  - assert normalization happens after the root-run package install block
- `tests/docker-compose.bats`
  - assert whole-home mount support is present in `docker-compose.yml`
  - assert legacy split-mount compatibility is absent from `docker-compose.yml`
- `README.md`
  - covered by existing file-based assertions only if needed; otherwise validated through direct content review and final verification

## Risks and Mitigations

### Risk: users migrating from the old split layout lose data during copy

Mitigation:

- Document the copy steps explicitly.
- Call out that both the old state directory and the separately mounted workspace directory must be copied into the new home directory.

### Risk: recursive chown over large bind mounts slows startup or modifies host ownership too broadly

Mitigation:

- Limit recursive ownership repair to container-managed state paths.
- Only guarantee direct ownership for `/home/node` itself and managed subdirectories.

### Risk: documentation and implementation drift

Mitigation:

- Update README in the same change set as Dockerfile and Compose updates.
- Verify the documented environment variables and mount targets match the final files exactly.
