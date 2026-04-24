#!/usr/bin/env bash
# git-ai-trace — extract recap blocks from git log.
#
# Regenerates a chronological overview from the recap blocks embedded
# in commit messages. Output goes to stdout.
#
# Usage:
#   ./recap-log.sh > AI_CONTRIB.md           # all commits
#   ./recap-log.sh v1.0..HEAD                # a range
#   ./recap-log.sh --since=2026-01-01        # time window
#   ./recap-log.sh --author=alice            # by author
#
# Any argument is passed through to `git log`.

set -euo pipefail

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "not a git repository" >&2
  exit 1
fi

SEP="__RECAP_SEPARATOR_$$__"

echo "# Session recaps"
echo
echo "_Generated from git log on $(date -u +%Y-%m-%d). Derived view — regenerate with \`./recap-log.sh\`._"
echo

git log --pretty=format:"${SEP}%n%H%n%ai%n%an%n%s%n%b" "$@" \
  | awk -v sep="$SEP" '
    BEGIN { RS = sep "\n"; FS = "\n" }
    NR == 1 { next }
    {
      sha = $1
      date = $2
      author = $3
      subject = $4
      body = ""
      for (i = 5; i <= NF; i++) body = body $i "\n"

      start = index(body, "--- session-recap ---")
      end = index(body, "--- end-recap ---")
      if (start == 0 || end == 0 || end < start) next

      block = substr(body, start + length("--- session-recap ---") + 1,
                     end - start - length("--- session-recap ---") - 1)

      short_date = substr(date, 1, 10)
      short_sha = substr(sha, 1, 8)
      print "## " short_date " — " subject
      print ""
      print "_" short_sha " · " author "_"
      print ""
      gsub(/^\n+|\n+$/, "", block)
      print block
      print ""
      print "---"
      print ""
    }
  '
