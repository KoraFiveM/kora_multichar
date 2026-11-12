#!/usr/bin/env bash
set -uo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lua_bin="${LUA:-lua}"
status=0

for file in "$test_dir"/smoke/*.lua; do
    echo "== $(basename "$file" .lua) =="
    if ! "$lua_bin" "$file"; then status=1; fi
    echo
done

exit "$status"
