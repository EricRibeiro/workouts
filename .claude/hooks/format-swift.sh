#!/usr/bin/env bash
# PostToolUse hook: format a .swift file right after Claude edits or writes it.
# Keeps `./dev lint` green without a separate step. Fails open on anything unexpected.
set -u
file=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -n "$file" && "$file" == *.swift && -f "$file" ]] || exit 0
xcrun swift-format format --in-place "$file" >/dev/null 2>&1 || true
exit 0
