#!/bin/sh
set -eu

plugin_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
state_dir=$(mktemp -d)
trap 'rm -rf "$fixture" "$state_dir"' EXIT

git -C "$fixture" init -q -b main
git -C "$fixture" config user.name "AI Review Test"
git -C "$fixture" config user.email "test@example.invalid"
printf '%s\n' 'before' > "$fixture/tracked.txt"
printf '%s\n' 'remove me' > "$fixture/deleted.txt"
git -C "$fixture" add tracked.txt deleted.txt
git -C "$fixture" commit -qm "fixture"

printf '%s\n' 'after' > "$fixture/tracked.txt"
rm "$fixture/deleted.txt"
printf '%s\n' 'new file' > "$fixture/added.txt"

cd "$plugin_root"
AI_REVIEW_TEST_REPO="$fixture" AI_REVIEW_TEST_STATE="$state_dir" \
  nvim -u tests/minimal_init.lua -i NONE --headless "+luafile tests/test.lua" +qa
