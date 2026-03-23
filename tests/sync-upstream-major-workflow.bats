#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORKFLOW_FILE="$REPO_ROOT/.github/workflows/sync-upstream-major.yml"
}

@test "sync workflow tracks upstream version through repository file" {
  run grep -E '^[[:space:]]*UPSTREAM_VERSION_FILE:[[:space:]]*OPENCLAW_UPSTREAM_VERSION[[:space:]]*$' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E 'current_major="\$\(cat "\$\{UPSTREAM_VERSION_FILE\}"\)"' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}

@test "sync workflow commits version file before creating release tag" {
  run grep -E 'printf '\''%s\\n'\'' "\$\{LATEST_MAJOR\}" > "\$\{UPSTREAM_VERSION_FILE\}"' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E 'git add "\$\{UPSTREAM_VERSION_FILE\}"' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E 'git commit( -s)? -m "chore: sync upstream version to \${LATEST_MAJOR}"' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E 'git push origin HEAD:' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]

  run grep -E 'git tag "\$\{LATEST_MAJOR\}"' "$WORKFLOW_FILE"
  [ "$status" -eq 0 ]
}
