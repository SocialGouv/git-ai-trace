#!/usr/bin/env bash
# Smoke test for the git-ai-trace hooks.
#
# Spins up a scratch git repo, then runs the commit-msg hook against a
# battery of messages (missing recap, valid recap, [no-recap] escape,
# empty What changed, Moments without actor). Exits non-zero on any
# unexpected outcome.
#
# Run locally: `bash scripts/test-hooks.sh`

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_COMMIT_MSG="$REPO_ROOT/hooks/git/commit-msg"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
git init -q
git config user.email test@example.com
git config user.name "Test"

echo "hello" > src.txt
git add src.txt

pass=0
fail=0

run_case() {
  local desc="$1" expected="$2" msg_file="$3"
  set +e
  "$HOOK_COMMIT_MSG" "$msg_file" >/dev/null 2>&1
  local rc=$?
  set -e
  if [ "$expected" = "pass" ] && [ "$rc" -eq 0 ]; then
    echo "PASS: $desc"
    pass=$((pass + 1))
  elif [ "$expected" = "fail" ] && [ "$rc" -ne 0 ]; then
    echo "PASS: $desc (rejected as expected)"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected=$expected, rc=$rc)"
    fail=$((fail + 1))
  fi
}

cat > msg-no-recap <<'EOF'
feat: add thing
EOF
run_case "rejects message with no recap block" fail msg-no-recap

cat > msg-valid <<'EOF'
feat: add thing

--- session-recap ---
What changed: Added src.txt.
Moments:
- human: asked for src.txt
- claude: wrote src.txt
--- end-recap ---
EOF
run_case "accepts valid recap block" pass msg-valid

cat > msg-norecap-escape <<'EOF'
chore: version bump [no-recap]
EOF
run_case "accepts [no-recap] escape hatch" pass msg-norecap-escape

cat > msg-empty-what <<'EOF'
feat: add thing

--- session-recap ---
What changed:
Moments:
- human: something
--- end-recap ---
EOF
run_case "rejects empty 'What changed:'" fail msg-empty-what

cat > msg-no-actor <<'EOF'
feat: add thing

--- session-recap ---
What changed: Added src.txt.
Moments:
- note: no actor here
--- end-recap ---
EOF
run_case "rejects Moments without valid actor line" fail msg-no-actor

cat > msg-unclosed <<'EOF'
feat: add thing

--- session-recap ---
What changed: Added src.txt.
Moments:
- human: did something
EOF
run_case "rejects unclosed recap block" fail msg-unclosed

echo
echo "Summary: $pass passed, $fail failed."
[ "$fail" -eq 0 ]
