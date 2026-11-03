#!/usr/bin/env bash
# PreToolUse hook (Bash): block `git commit` unless `./dev check` passed after the last code change.
# `./dev check` touches .build/check.stamp on success; any changed file newer than it is unchecked.
# Docs-only commits pass. Fails open on anything unexpected (no jq, no input, no project dir).
set -u
cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ -n "$cmd" ]] || exit 0

re='(^|[;&|[:space:]])git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)'
[[ "$cmd" =~ $re ]] || exit 0

[[ -n "${CLAUDE_PROJECT_DIR:-}" ]] || exit 0
cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || exit 0

stamp=.build/check.stamp
changed=()
while IFS= read -r line; do
  path=${line:3}
  [[ "$path" == *" -> "* ]] && path=${path##* -> }
  path=${path#\"}
  path=${path%\"}
  case "$path" in
    "" | docs/* | .claude/* | .gitignore | README.md | *.md) continue ;;
  esac
  changed+=("$path")
done < <(git status --porcelain --untracked-files=all 2>/dev/null)

# Docs-only (or clean) commit: nothing that can affect the build or tests.
(( ${#changed[@]} > 0 )) || exit 0

if [[ ! -e "$stamp" ]]; then
  echo "dev: no passing ./dev check recorded; run ./dev check, then commit." >&2
  exit 2
fi

stale=()
for f in "${changed[@]}"; do
  [[ -e "$f" && "$f" -nt "$stamp" ]] && stale+=("$f")
done

if (( ${#stale[@]} > 0 )); then
  echo "dev: ./dev check has not passed since these changed:" >&2
  printf '%s\n' "${stale[@]}" >&2
  echo "run ./dev check, then commit." >&2
  exit 2
fi
exit 0
