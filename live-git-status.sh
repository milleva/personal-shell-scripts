#!/usr/bin/env bash
# live-git-status.sh — live-updating concise summary of `git status`
# Usage: live-git-status.sh [interval_seconds]   (default: 2)

interval=${1:-2}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository"
  exit 1
fi

# --no-optional-locks: never take .git/index.lock, so polling can't
# collide with git commands another tool (e.g. Claude Code) is running
g() { git --no-optional-locks "$@"; }

render() {
  # Branch (or detached HEAD)
  local branch
  branch=$(g symbolic-ref --short -q HEAD || echo "(detached at $(g rev-parse --short HEAD))")

  # Relationship to upstream (as of last fetch)
  local sync upstream ahead behind
  if upstream=$(g rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
    read -r behind ahead < <(g rev-list --left-right --count '@{u}...HEAD')
    if [[ $ahead -eq 0 && $behind -eq 0 ]]; then
      sync="up to date with $upstream"
    else
      sync="$upstream:"
      [[ $ahead -gt 0 ]]  && sync+=" ahead $ahead"
      [[ $behind -gt 0 ]] && sync+=" behind $behind"
    fi
  else
    sync="no upstream"
  fi

  # Count changes from porcelain output (XY = staged/unstaged status columns)
  local staged=0 unstaged=0 untracked=0 conflicts=0 line x y
  while IFS= read -r line; do
    x=${line:0:1}; y=${line:1:1}
    if [[ "$x$y" == "??" ]]; then
      ((untracked++))
    elif [[ "$x" == "U" || "$y" == "U" || "$x$y" == "AA" || "$x$y" == "DD" ]]; then
      ((conflicts++))
    else
      [[ "$x" != " " ]] && ((staged++))
      [[ "$y" != " " ]] && ((unstaged++))
    fi
  done < <(g status --porcelain --untracked-files=all)

  echo
  echo "$branch ($sync)"
  echo
  if (( staged + unstaged + untracked + conflicts == 0 )); then
    echo "Working tree clean"
    return
  fi
  echo "Staged:     $staged"
  echo "Unstaged:   $unstaged"
  echo "Untracked:  $untracked"
  (( conflicts > 0 )) && echo "Conflicts:  $conflicts"
  return 0
}

# Hide the cursor while running; restore it on exit / Ctrl-C
tput civis 2>/dev/null
trap 'tput cnorm 2>/dev/null; echo' EXIT
trap 'exit 0' INT TERM

last=""
while true; do
  out=$(render)
  # Only redraw when something changed, so the screen doesn't flicker
  if [[ "$out" != "$last" ]]; then
    printf '\033[H\033[2J'   # move cursor home + clear screen
    printf '%s\n\n' "$out"
    printf 'Last change %s · every %ss · Ctrl-C to quit\n' "$(date +%H:%M:%S)" "$interval"
    last=$out
  fi
  sleep "$interval"
done