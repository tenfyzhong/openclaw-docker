#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT_PATH="$REPO_ROOT/scripts/create-tag.sh"
}

setup_test_repo() {
  local test_root="$BATS_TEST_TMPDIR/$1"
  REPO_DIR="$test_root/repo"
  ORIGIN_DIR="$test_root/origin.git"

  mkdir -p "$test_root"
  git init --bare "$ORIGIN_DIR" >/dev/null
  git init "$REPO_DIR" >/dev/null

  git -C "$REPO_DIR" config user.name "Test User"
  git -C "$REPO_DIR" config user.email "test@example.com"
  echo "seed" > "$REPO_DIR/seed.txt"
  git -C "$REPO_DIR" add seed.txt
  git -C "$REPO_DIR" commit --no-verify -m "seed" >/dev/null
  git -C "$REPO_DIR" branch -M main
  git -C "$REPO_DIR" remote add origin "$ORIGIN_DIR"
  git -C "$REPO_DIR" push -u origin main >/dev/null
}

write_upstream_tags() {
  local file
  file="$(mktemp "$BATS_TEST_TMPDIR/upstream-tags.XXXXXX")"
  printf '%s\n' "$@" > "$file"
  echo "$file"
}

@test "creates latest stable major tag when --major is not provided" {
  setup_test_repo "latest-major"
  tags_file="$(write_upstream_tags \
    "v2026.3.11-beta.1" \
    "v2026.3.11" \
    "v2026.3.12-beta.1" \
    "v2026.3.10")"

  cd "$REPO_DIR"
  run env OPENCLAW_UPSTREAM_TAGS_FILE="$tags_file" "$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Created local tag: v2026.3.11"* ]]

  run git -C "$REPO_DIR" tag --list "v2026.3.11"
  [ "$status" -eq 0 ]
  [ "$output" = "v2026.3.11" ]
}

@test "increments patch when major already exists" {
  setup_test_repo "patch-increment"
  tags_file="$(write_upstream_tags "v2026.3.11")"

  git -C "$REPO_DIR" tag v2026.3.11
  git -C "$REPO_DIR" tag v2026.3.11.1
  git -C "$REPO_DIR" tag v2026.3.11.3
  git -C "$REPO_DIR" push origin --tags >/dev/null

  cd "$REPO_DIR"
  run env OPENCLAW_UPSTREAM_TAGS_FILE="$tags_file" "$SCRIPT_PATH" --major 2026.3.11

  [ "$status" -eq 0 ]
  [[ "$output" == *"Created local tag: v2026.3.11.4"* ]]

  run git -C "$REPO_DIR" tag --list "v2026.3.11.4"
  [ "$status" -eq 0 ]
  [ "$output" = "v2026.3.11.4" ]
}

@test "fails when provided major does not exist upstream" {
  setup_test_repo "major-validation"
  tags_file="$(write_upstream_tags "v2026.3.10")"

  cd "$REPO_DIR"
  run env OPENCLAW_UPSTREAM_TAGS_FILE="$tags_file" "$SCRIPT_PATH" --major v2026.3.11

  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist in openclaw/openclaw"* ]]

  run git -C "$REPO_DIR" tag --list "v2026.3.11*"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "creates first patch when latest major already exists locally" {
  setup_test_repo "latest-major-patch"
  tags_file="$(write_upstream_tags "v2026.3.11" "v2026.3.10")"

  git -C "$REPO_DIR" tag v2026.3.11
  git -C "$REPO_DIR" push origin --tags >/dev/null

  cd "$REPO_DIR"
  run env OPENCLAW_UPSTREAM_TAGS_FILE="$tags_file" "$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Created local tag: v2026.3.11.1"* ]]

  run git -C "$REPO_DIR" tag --list "v2026.3.11.1"
  [ "$status" -eq 0 ]
  [ "$output" = "v2026.3.11.1" ]
}

@test "resolves major from upstream dash patch tags" {
  setup_test_repo "dash-patch-major"
  tags_file="$(write_upstream_tags "v2026.3.12" "v2026.3.13-1")"

  cd "$REPO_DIR"
  run env OPENCLAW_UPSTREAM_TAGS_FILE="$tags_file" "$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Created local tag: v2026.3.13"* ]]

  run git -C "$REPO_DIR" tag --list "v2026.3.13"
  [ "$status" -eq 0 ]
  [ "$output" = "v2026.3.13" ]
}

@test "accepts provided major when upstream has dash patch tag" {
  setup_test_repo "dash-patch-major-validation"
  tags_file="$(write_upstream_tags "v2026.3.13-1")"

  cd "$REPO_DIR"
  run env OPENCLAW_UPSTREAM_TAGS_FILE="$tags_file" "$SCRIPT_PATH" --major 2026.3.13

  [ "$status" -eq 0 ]
  [[ "$output" == *"Created local tag: v2026.3.13"* ]]

  run git -C "$REPO_DIR" tag --list "v2026.3.13"
  [ "$status" -eq 0 ]
  [ "$output" = "v2026.3.13" ]
}
