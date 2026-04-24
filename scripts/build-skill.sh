#!/usr/bin/env bash
# Build the distributable .skill bundle.
#
# Produces dist/git-ai-trace.skill — a ZIP with a top-level git-ai-trace/
# directory mirroring the repo layout (SKILL.md, README.md, hooks/,
# scripts/recap-log.sh, hooks/README.md). Consumed by release.yml and
# by release-it's after:bump hook.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

DIST_DIR="dist"
STAGE_DIR="${DIST_DIR}/stage"
BUNDLE_NAME="git-ai-trace"
OUTPUT="${DIST_DIR}/${BUNDLE_NAME}.skill"

rm -rf "$STAGE_DIR" "$OUTPUT"
mkdir -p "$STAGE_DIR/$BUNDLE_NAME/hooks/claude-code" \
         "$STAGE_DIR/$BUNDLE_NAME/hooks/git" \
         "$STAGE_DIR/$BUNDLE_NAME/scripts"

cp SKILL.md README.md "$STAGE_DIR/$BUNDLE_NAME/"
cp hooks/README.md "$STAGE_DIR/$BUNDLE_NAME/hooks/"
cp hooks/claude-code/pre-commit-recap.sh "$STAGE_DIR/$BUNDLE_NAME/hooks/claude-code/"
cp hooks/git/prepare-commit-msg hooks/git/commit-msg "$STAGE_DIR/$BUNDLE_NAME/hooks/git/"
cp scripts/recap-log.sh "$STAGE_DIR/$BUNDLE_NAME/scripts/"

chmod +x "$STAGE_DIR/$BUNDLE_NAME/hooks/claude-code/pre-commit-recap.sh" \
         "$STAGE_DIR/$BUNDLE_NAME/hooks/git/prepare-commit-msg" \
         "$STAGE_DIR/$BUNDLE_NAME/hooks/git/commit-msg" \
         "$STAGE_DIR/$BUNDLE_NAME/scripts/recap-log.sh"

(cd "$STAGE_DIR" && zip -rqX "../${BUNDLE_NAME}.skill" "$BUNDLE_NAME")

rm -rf "$STAGE_DIR"

SIZE=$(wc -c < "$OUTPUT")
echo "Built $OUTPUT ($SIZE bytes)"
