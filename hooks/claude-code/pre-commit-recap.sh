#!/usr/bin/env bash
# git-ai-trace — Claude Code PreToolUse hook.
#
# Intercepts `git commit -m "..."` (or -F, --message) and blocks if the
# inline message lacks a valid recap block.
#
# A valid recap block:
#   - is delimited by `--- session-recap ---` and `--- end-recap ---`
#   - contains a non-empty `What changed:` line
#   - contains a `Moments:` line followed by at least one `- actor: text`
#     entry, where actor is human, claude, or both
#
# When the developer uses `git commit` without -m (editor flow), this
# hook cannot see the message — it has not been typed yet. That case is
# handled by the native git hooks in ../git/.
#
# Escape hatches:
#   - [no-recap] marker in the subject line
#   - merge, revert, --amend --no-edit
#   - all staged files match trivial patterns (see below)

set -euo pipefail

TRIVIAL_PATTERNS=(
  '^\.gitignore$'
  '^README\.md$'
  '^CHANGELOG\.md$'
  '^\.claude/'
  '^LICENSE$'
)

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Not a git commit? Nothing to check.
if ! echo "$COMMAND" | grep -qE '(^|[[:space:];&|])git[[:space:]]+commit(\s|$)'; then
  exit 0
fi

# Explicit opt-out.
if echo "$COMMAND" | grep -qE '\[no-recap\]'; then
  exit 0
fi

# Merges, amend-no-edit, reverts: no recap needed.
if echo "$COMMAND" | grep -qE '(--amend.*--no-edit|--no-edit.*--amend|git[[:space:]]+revert|git[[:space:]]+merge)'; then
  exit 0
fi

# Must be in a git repo.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# Extract the message from -m/--message/-F. If the developer used -F -
# (stdin heredoc), we can't see it from tool_input alone — defer.
if echo "$COMMAND" | grep -qE '(-F[[:space:]]+-|--file[[:space:]]+-)'; then
  exit 0
fi

MESSAGE=$(echo "$COMMAND" | python3 -c '
import sys, shlex
cmd = sys.stdin.read()
try:
    tokens = shlex.split(cmd)
except ValueError:
    print("", end="")
    sys.exit(0)
msg_parts = []
i = 0
while i < len(tokens):
    t = tokens[i]
    if t in ("-m", "--message") and i + 1 < len(tokens):
        msg_parts.append(tokens[i + 1])
        i += 2
    elif t.startswith("--message="):
        msg_parts.append(t[len("--message="):])
        i += 1
    elif t.startswith("-m") and len(t) > 2:
        msg_parts.append(t[2:])
        i += 1
    else:
        i += 1
print("\n\n".join(msg_parts), end="")
' 2>/dev/null || echo "")

# No -m at all? Editor flow — git hooks will handle it.
if [ -z "$MESSAGE" ]; then
  exit 0
fi

# Trivial-only staged paths: let it through.
STAGED=$(git diff --cached --name-only 2>/dev/null || echo "")
if [ -n "$STAGED" ]; then
  all_trivial=true
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    matched=false
    for pat in "${TRIVIAL_PATTERNS[@]}"; do
      if echo "$file" | grep -qE "$pat"; then
        matched=true
        break
      fi
    done
    if ! $matched; then
      all_trivial=false
      break
    fi
  done <<< "$STAGED"
  if $all_trivial; then
    exit 0
  fi
fi

# Validate the block.
if ! echo "$MESSAGE" | grep -qF -- "--- session-recap ---"; then
  cat >&2 <<EOF
Commit blocked by git-ai-trace hook: no recap block in the commit message.

Use the git-ai-trace skill to produce a recap block, then rebuild the
commit message. The block looks like:

  --- session-recap ---
  What changed: <one line about the diff>
  Moments:
  - human: <observed action>
  - claude: <observed action>
  ADR: <link>   # optional, omit if none
  --- end-recap ---

Only record presences (what was said, proposed, rejected, generated).
Do not record absences (silent review, unverbalized decisions).

Escape hatches:
  - add [no-recap] to the commit subject for trivial commits
  - use --amend --no-edit for true no-op amends
EOF
  exit 2
fi

if ! echo "$MESSAGE" | grep -qF -- "--- end-recap ---"; then
  cat >&2 <<EOF
Commit blocked by git-ai-trace hook: recap block is not closed.

Add --- end-recap --- after the last entry.
EOF
  exit 2
fi

# Extract the block body.
BLOCK=$(echo "$MESSAGE" | awk '/--- session-recap ---/{flag=1; next} /--- end-recap ---/{flag=0} flag')

# What changed: must be present and non-empty.
WHAT_LINE=$(echo "$BLOCK" | grep -E '^What changed:' || true)
if [ -z "$WHAT_LINE" ]; then
  echo "git-ai-trace: missing 'What changed:' line in recap block." >&2
  exit 2
fi
WHAT_VALUE=$(echo "$WHAT_LINE" | sed -E 's/^What changed:[[:space:]]*//' | tr -d '[:space:]')
if [ -z "$WHAT_VALUE" ]; then
  echo "git-ai-trace: 'What changed:' is empty. Describe what lands in the commit." >&2
  exit 2
fi

# Moments: must have at least one `- actor: text` entry.
if ! echo "$BLOCK" | grep -qE '^Moments:'; then
  echo "git-ai-trace: missing 'Moments:' line in recap block." >&2
  exit 2
fi

MOMENT_COUNT=$(echo "$BLOCK" | grep -cE '^-[[:space:]]+(human|claude|both):[[:space:]]+.+$' || true)
if [ "$MOMENT_COUNT" -eq 0 ]; then
  cat >&2 <<EOF
git-ai-trace: no moments recorded under 'Moments:'.

At least one moment is required. Each moment is a line starting with
'-' followed by an actor (human, claude, or both), then ': ', then the
observed action. Example:

  Moments:
  - human: rejected Redis-queue option as over-engineering
  - claude: wrote the SQL patch

If the session had no notable moments, the commit is likely trivial —
use [no-recap] in the subject instead.
EOF
  exit 2
fi

exit 0
