# git-ai-trace

A Claude Code skill that embeds an honest, observation-only recap of human/AI collaboration inside each commit message — so the story of how the code was made travels with the code.

## Why

Codebases written with AI assistants raise a question that binary disclosure ("was AI used?") can't answer: **who actually drove what?** A developer who reframed the AI's first proposal three times exercised strong creative control, even if most keystrokes came from the model. A generated file that passed through without comment is a delegation, regardless of intent.

Percentages lie about this ("70% AI-written" is meaningless). Labels flatten it ("ACE" vs "HCE" forces every session into five bins). File-based logs lose it (a separate `AI_CONTRIB.md` breaks on rebase, generates merge conflicts, and drifts from the commits it tries to describe).

`git-ai-trace` takes a different path: a short block of **observed moments** — proposals, choices, rejections, generations — embedded directly in the commit message. Each moment is one line, pointable to a specific message in the chat. Absences are never recorded, only presences. The recap is incomplete by design, but it is honest.

## What a recap looks like

```
fix: prevent duplicate job processing under load

Workers were occasionally picking up the same job. Row-level
locking closes the race without adding infrastructure.

--- session-recap ---
What changed: Worker loop now claims jobs via SELECT FOR UPDATE SKIP
  LOCKED; batch size reduced from 100 to 20.
Moments:
- human: brought symptom (duplicate processing in prod logs) and initial hypothesis (lock contention)
- claude: diagnosed non-atomic SELECT+UPDATE across workers as root cause
- claude: proposed three remediation options (advisory lock, SKIP LOCKED, Redis queue) with trade-offs
- human: rejected Redis-queue option as over-engineering
- human: chose SKIP LOCKED option
- human: set batch size to 20
- claude: wrote the SQL patch
--- end-recap ---

Assisted-by: Claude Sonnet 4.6
```

A reader six months from now can reconstruct the shape of the session: what was suggested, what was rejected, why one option beat another. None of this is in the diff. None of it survives in a percentage. All of it survives in the commit.

## Design principles

The skill has three non-negotiable rules:

**Presences only.** The recap records what happened — proposals, rejections, generations, choices. It never records what didn't happen. No "human did not object", no "silently accepted", no "reviewed without feedback". Absences are invisible to an LLM reading the chat; recording them would be inference dressed as observation.

**Observable, not inferred.** Every moment must be pointable to a specific message in the chat. Evaluative framings ("cleverly proposed", "after productive discussion") are out. Motive claims ("chose option 2 because it was simpler") are out unless the reason was stated.

**In the commit, not in a file.** The recap lives in the commit message body, between `--- session-recap ---` and `--- end-recap ---` delimiters. It travels with the commit through rebases, squashes, and cherry-picks. A separate file would break on all three and generate merge conflicts on parallel branches.

## Related work

The skill draws from two explicit antecedents:

- **[TCP/UP](https://tcp-up.org/)** — a declarative protocol for editorial transparency with five labels (HUC, HCA, HCE, ACE, AIC) distinguishing human-centric from AI-centric content. `git-ai-trace` keeps the good-faith philosophy and the commitment to justifiable sincerity, but drops the labels as too coarse for code.
- **[AI_ATTRIBUTION.md](https://github.com/ismet55555/ai-attribution)** (Ismet Handzic) — a chronological log of creative control with six involvement levels. `git-ai-trace` keeps the idea of recording moments over time, but drops both the levels (still a categorization) and the separate file (broken by git operations).

The skill's own structure (presences, observable, in-commit) emerged from the design trade-offs these two approaches surfaced. See `docs/design-rationale.md` for the longer story.

## Components

The repo ships three things:

```
git-ai-trace/
├── SKILL.md                          # the skill itself (Claude Code / Claude.ai)
├── hooks/
│   ├── claude-code/
│   │   └── pre-commit-recap.sh       # Claude Code PreToolUse hook
│   ├── git/
│   │   ├── prepare-commit-msg        # native git hook, editor flow
│   │   └── commit-msg                # native git hook, final validation
│   └── README.md                     # installation instructions
└── scripts/
    └── recap-log.sh                  # regenerate a panoramic view from git log
```

The **skill** (`SKILL.md`) is what Claude reads. It can be installed as a Claude Code skill (auto-invoked on "let's commit" and similar phrases) or a slash command (`/git-ai-trace`).

The **hooks** are optional. They enforce the discipline automatically, across all three paths to `git commit` (Claude `-m`, developer `-m`, developer editor flow). Without hooks, the skill still works — it just relies on Claude or the developer remembering to invoke it.

The **extractor** (`recap-log.sh`) regenerates a chronological `AI_CONTRIB.md`-style view from the recap blocks in `git log` on demand. It's a derived view — never committed, regenerated whenever someone wants the panoramic perspective.

## Installation

### As a Claude Code skill

```bash
# Per-project (committable, shared with the team)
mkdir -p .claude/skills/git-ai-trace
cp -r SKILL.md hooks/ scripts/ .claude/skills/git-ai-trace/
chmod +x .claude/skills/git-ai-trace/hooks/claude-code/pre-commit-recap.sh
chmod +x .claude/skills/git-ai-trace/hooks/git/*
chmod +x .claude/skills/git-ai-trace/scripts/recap-log.sh
```

Or globally under `~/.claude/skills/git-ai-trace/` for all your projects.

Claude auto-invokes the skill when the conversation matches its description ("let's commit", "recap this session", etc.). You can also invoke it explicitly with `/git-ai-trace`.

### With the hooks

See `hooks/README.md` for the three hooks. Short version:

- **Claude Code hook**: add a `PreToolUse` entry in `.claude/settings.json` that runs `hooks/claude-code/pre-commit-recap.sh` on `git commit*`.
- **Native git hooks**: copy `hooks/git/prepare-commit-msg` and `hooks/git/commit-msg` into `.git/hooks/` (or use `core.hooksPath` for team sharing).

All hooks share the same validation contract:

- The commit message contains a recap block delimited by `--- session-recap ---` / `--- end-recap ---`.
- `What changed:` is present and non-empty.
- `Moments:` is followed by at least one `- <actor>: <action>` line (actor ∈ {human, claude, both}).
- `ADR:` is optional, only present if an architectural decision was formalized.

Escape hatches (the hooks let commits through without a recap when):

- The commit subject contains `[no-recap]`.
- The commit is a merge, revert, or `--amend --no-edit`.
- All staged files match trivial patterns (`.gitignore`, `README.md`, `CHANGELOG.md`, `.claude/**`, `LICENSE`).

### As a slash command only (lightest test drive)

If you just want to try the skill before committing to the full install:

```bash
mkdir -p .claude/commands
cp SKILL.md .claude/commands/git-ai-trace.md
```

Then `/git-ai-trace` in Claude Code. No auto-invocation, no hooks, no enforcement — just the skill content expanded on demand. Good for a first test on a real session before deciding whether to adopt the full setup.

## Generating a panoramic view

```bash
./scripts/recap-log.sh > AI_CONTRIB.md
./scripts/recap-log.sh v1.0..HEAD > release-notes.md
./scripts/recap-log.sh --author=alice --since=2026-01-01
```

The output is a derived view; never commit it. Regenerate whenever a reader wants the chronological overview.

## What the skill is not

- **Not a gatekeeper on AI involvement.** A recap with moments only from one side is perfectly valid. The hooks enforce *presence* of a recap, not its content.
- **Not a score.** No percentage, no label, no ranking.
- **Not a proof.** It's a good-faith trace. Credibility comes from each moment being pointable-to in the chat — a reviewer can verify.
- **Not a complete record.** Silent reading, offline thinking, teammate discussions — none of that is captured. The recap claims only to record what the chat recorded.
- **Not for every commit.** Trivial commits (typo, version bump) can opt out with `[no-recap]`.

## Status

Experimental. Tested in real use on a few projects; works well enough to adopt, not yet battle-tested across many teams and workflows. Feedback welcome, especially on cases where the recap degrades (Claude smooths over moments, merges unrelated actions into one line, invents plausible-but-unverifiable phrasing).

See `CONTRIBUTING.md` for how to report issues with concrete examples.

## License

[to fill]

## Acknowledgements

The design conversation that produced this skill happened with Claude Opus 4.7 over several iterations. The full recap of that design session lives in the first commits of this repo — a kind of self-application of the tool.
