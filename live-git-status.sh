#!/usr/bin/env bash
# live-git-status.sh — live-updating, colorful git status with per-file line counts
# Usage: live-git-status.sh [interval_seconds]   (default: 2)

interval=${1:-2}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository"
  exit 1
fi
cd "$(git rev-parse --show-toplevel)" || exit 1   # all paths are repo-relative

# Colors
R=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
MAGENTA=$'\033[35m'; CYAN=$'\033[36m'

# --no-optional-locks: never take .git/index.lock, so polling can't
# collide with git commands another tool (e.g. Claude Code) is running
g() { git --no-optional-locks "$@"; }

# "dir/" dimmed, "file.ext" bold
fmt_path() {
  local p=$1
  if [[ $p == */* ]]; then
    printf '%s%s%s%s%s' "$DIM" "${p%/*}/" "$R$BOLD" "${p##*/}" "$R"
  else
    printf '%s%s%s' "$BOLD" "$p" "$R"
  fi
}

# "+12 -3" in green/red (zero sides omitted)
fmt_counts() {
  local a=$1 d=$2 out=""
  if [[ $a == - ]]; then printf '%sbinary%s' "$DIM" "$R"; return; fi
  if (( a == 0 && d == 0 )); then printf '%sno line changes%s' "$DIM" "$R"; return; fi
  (( a > 0 )) && out+="${GREEN}+$a${R}"
  (( d > 0 )) && out+="${out:+ }${RED}-$d${R}"
  printf '%s' "$out"
}

# Emit "added<TAB>deleted<TAB>path<TAB>old_path" per file from git diff
# (pass --cached for staged). Skips conflicted files.
numstat() {
  local rec a d path old new
  while IFS= read -r -d '' rec; do
    IFS=$'\t' read -r a d path <<< "$rec"
    old=""
    if [[ -z $path ]]; then            # rename: old and new paths follow
      IFS= read -r -d '' old
      IFS= read -r -d '' new
      path=$new
    fi
    [[ $conflict_list == *$'\n'"$path"$'\n'* ]] && continue
    printf '%s\t%s\t%s\t%s\n' "$a" "$d" "$path" "$old"
  done < <(g diff "$@" --numstat -z)
}

# Same format for untracked files: every line counts as added
untracked_stat() {
  local f
  while IFS= read -r -d '' f; do
    if [[ -s $f ]] && ! grep -Iq . "$f"; then
      printf '%s\t%s\t%s\t\n' - - "$f"
    else
      printf '%s\t%s\t%s\t\n' "$(awk 'END{print NR}' "$f")" 0 "$f"
    fi
  done < <(g ls-files --others --exclude-standard -z)
}

# Render a section from numstat-format lines on stdin
section() {
  local title=$1 color=$2 body="" n=0 ta=0 td=0 a d p o
  while IFS=$'\t' read -r a d p o; do
    ((n++))
    body+="  ${color}•${R} $(fmt_path "$p")"
    [[ -n $o ]] && body+=" ${DIM}← $o${R}"
    body+=$'\n'"      $(fmt_counts "$a" "$d")"$'\n'
    [[ $a != - ]] && ((ta += a, td += d))
  done
  (( n == 0 )) && return
  printf '%s%s%s %s(%d)%s  %s\n%s' "$BOLD$color" "$title" "$R" "$DIM" "$n" "$R" \
    "$(fmt_counts "$ta" "$td")" "$body"
}

render() {
  # Branch (or detached HEAD)
  local branch
  branch=$(g symbolic-ref --short -q HEAD || echo "(detached at $(g rev-parse --short HEAD))")

  # Relationship to upstream (as of last fetch)
  local sync sync_color=$DIM upstream ahead behind
  if upstream=$(g rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
    read -r behind ahead < <(g rev-list --left-right --count '@{u}...HEAD')
    if [[ $ahead -eq 0 && $behind -eq 0 ]]; then
      sync="up to date with $upstream"
    else
      sync="$upstream:"
      [[ $ahead -gt 0 ]]  && sync+=" ahead $ahead"
      [[ $behind -gt 0 ]] && sync+=" behind $behind"
      sync_color=$YELLOW
    fi
  else
    sync="no upstream"
  fi

  echo
  printf '%s%s%s %s(%s)%s\n\n' "$BOLD$CYAN" "$branch" "$R" "$sync_color" "$sync" "$R"

  # Conflicted files (listed separately, excluded from other sections)
  local conflict_list=$'\n' conflicts="" f
  while IFS= read -r -d '' f; do conflict_list+="$f"$'\n'; done \
    < <(g diff --name-only --diff-filter=U -z)
  if [[ $conflict_list != $'\n' ]]; then
    conflicts="${BOLD}${RED}Conflicts${R}"
    while IFS= read -r f; do
      [[ -n $f ]] && conflicts+=$'\n'"  ${RED}✗${R} $(fmt_path "$f")"
    done <<< "$conflict_list"
  fi

  local staged unstaged untracked s any=0
  staged=$(numstat --cached | section "Staged" "$GREEN")
  unstaged=$(numstat | section "Unstaged" "$YELLOW")
  untracked=$(untracked_stat | section "Untracked" "$MAGENTA")

  for s in "$conflicts" "$staged" "$unstaged" "$untracked"; do
    [[ -n $s ]] && { printf '%s\n\n' "$s"; any=1; }
  done
  (( any )) || printf '%s✓ Working tree clean%s\n' "$GREEN" "$R"
}

# Hide the cursor while running; restore it on exit / Ctrl-C
tput civis 2>/dev/null
trap 'tput cnorm 2>/dev/null; echo' EXIT
trap 'exit 0' INT TERM

last=""
while true; do
  out=$(render)
  rows=$(tput lines 2>/dev/null || echo 50)
  key="$rows|$out"
  # Only redraw when something changed (or the window resized) to avoid flicker
  if [[ $key != "$last" ]]; then
    # Trim to the window height so the header never scrolls off
    max=$(( rows - 3 ))
    total=$(printf '%s\n' "$out" | wc -l)
    if (( total > max && max > 1 )); then
      out="$(printf '%s\n' "$out" | head -n $(( max - 1 )))"$'\n'"${DIM}… $(( total - max + 1 )) more lines (enlarge the window)${R}"
    fi
    printf '\033[H\033[2J'   # cursor home + clear screen
    printf '%s\n\n' "$out"
    printf '%sLast change %s · every %ss · Ctrl-C to quit%s' \
      "$DIM" "$(date +%H:%M:%S)" "$interval" "$R"
    last=$key
  fi
  sleep "$interval"
done