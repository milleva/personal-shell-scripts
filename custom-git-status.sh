#!/usr/bin/env bash
# custom-git-status.sh — concise summary of `git status`

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository"
  exit 1
fi

# Branch (or detached HEAD)
branch=$(git symbolic-ref --short -q HEAD || echo "(detached at $(git rev-parse --short HEAD))")

# Relationship to upstream
sync=""
if upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
  read -r behind ahead < <(git rev-list --left-right --count '@{u}...HEAD')
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
staged=0; unstaged=0; untracked=0; conflicts=0
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
done < <(git status --porcelain --untracked-files=all)

echo
echo "On branch: $branch ($sync)"
echo
if (( staged + unstaged + untracked + conflicts == 0 )); then
  echo "Working tree clean"
  exit 0
fi
echo "Staged:     $staged"
echo "Unstaged:   $unstaged"
echo "Untracked:  $untracked"
(( conflicts > 0 )) && echo "Merge conflicts:             $conflicts"
echo
exit 0
