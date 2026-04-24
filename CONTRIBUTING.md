# Contributing to git-ai-trace

Thank you for considering a contribution. This document covers reporting issues, developing locally, and how releases happen.

## The dogfood rule

Every commit to this repo must itself carry a valid `--- session-recap ---` block, or opt out with `[no-recap]` in the subject for truly trivial commits (version bumps, typo fixes in docs, CI config tweaks with no logic change). A tool about commit-message recaps that does not use commit-message recaps loses all credibility, so this is non-negotiable.

If you're not using Claude Code, write the recap by hand following [`SKILL.md`](SKILL.md). The format is simple — two required fields (`What changed`, `Moments`), one optional (`ADR`), one line per moment, actor ∈ `human` / `claude` / `both`.

The `commit-msg` hook is activated automatically when you run `pnpm install` (via the `prepare` script setting `core.hooksPath` to `hooks/git`). Your commits will be rejected if the block is malformed.

## Reporting issues

The most useful issues are those with concrete, reproducible evidence. Two common cases:

### Recap degradation (the main thing we want to hear about)

Claude fused several distinct moments into one, invented a plausible-but-untraceable phrasing, or smoothed over a rejection. For reports:

- Paste the problematic recap.
- Quote or link the chat excerpt(s) that were *actually* said.
- Explain what the recap compressed or invented.

Example: *"Claude wrote `- human: iteratively refined the implementation across multiple exchanges`. The chat actually contains five distinct messages: (link 1) — rejected the first proposal; (link 2) — asked for option with Postgres; (link 3) — set batch size to 20; (link 4) — asked to drop the retry logic; (link 5) — approved the final SQL. The 'iteratively' word hides five concrete choices."*

### Hook bugs

The hook blocked a valid commit, let a malformed commit through, or crashed with an error. Include:

- The exact hook name (`pre-commit-recap.sh`, `prepare-commit-msg`, `commit-msg`).
- The commit message (scrubbed of sensitive content).
- The full hook output (stderr).
- Your OS, shell, and `git --version`.

## Local development

```bash
git clone https://github.com/SocialGouv/git-ai-trace
cd git-ai-trace
pnpm install     # installs release-it deps; activates core.hooksPath hooks/git
```

The `prepare` script wires `core.hooksPath` to `hooks/git`, so your clone dog-foods the tool from the first commit.

### Running the smoke test

```bash
bash scripts/test-hooks.sh
```

Spins up a scratch git repo and validates the `commit-msg` hook against six scenarios: missing recap, valid recap, `[no-recap]` escape hatch, empty `What changed`, malformed `Moments`, unclosed block. Must pass before submitting a PR.

### Building the distributable bundle

```bash
bash scripts/build-skill.sh
# produces dist/git-ai-trace.skill
```

This is what the release workflow ships as a GitHub Release asset. You shouldn't need to build it locally unless you're testing the packaging itself.

### Shellcheck

CI runs `shellcheck` on every shell script and git hook. If you add a new one, make sure it passes:

```bash
shellcheck hooks/claude-code/pre-commit-recap.sh \
           hooks/git/prepare-commit-msg hooks/git/commit-msg \
           scripts/*.sh
```

## Pull requests

- One concern per PR. Separate commits inside the PR are welcome; bundle them or keep them split as makes the history readable.
- Every commit needs a recap block (see dogfood rule above).
- Link the brainstorming or reasoning chat that produced the change, if one exists — optional but encouraged, in the spirit of what this tool preaches.
- Tests must pass. If you're changing hook behavior, add a case to `scripts/test-hooks.sh`.
- No backwards-compatibility shims for an unreleased format; the recap contract is under v0.x, breaking changes are allowed and expected.

## How releases happen

Releases are automated via `release-it` on PR merge to `main`:

1. Merge a PR with conventional-commit-style titles (`feat:`, `fix:`, `chore:`, etc.).
2. The `version.yml` workflow fires, obtains a token from SocialGouv's `token-bureau`, runs `pnpm release-it --ci`, which:
   - Bumps `version` in `package.json` per conventional commits.
   - Commits the bump with `chore: release v${version} [no-recap]` (the `[no-recap]` opts out of the recap requirement for the release commit).
   - Tags `v${version}` and pushes.
3. The tag push triggers `release.yml`, which builds `dist/git-ai-trace.skill`, computes its SHA256, and creates a GitHub Release with both as assets.

You do not run `release-it` locally. If you need to prepare a release manually, open a PR with the version bump and let the workflow take over.

## License

By contributing, you agree that your contributions will be licensed under the MIT License (see [`LICENSE`](LICENSE)).
