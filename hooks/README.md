# git-ai-trace hooks

Three hooks enforce the recap discipline across all three paths to `git commit`. All hooks share the same validation contract, and all are opt-in — the skill works without them.

## The contract

A commit message is valid if **any** of these is true:

- It contains a recap block delimited by `--- session-recap ---` / `--- end-recap ---`, with a non-empty `What changed:` line and at least one `- <actor>: <action>` line under `Moments:` (actor ∈ `human`, `claude`, `both`).
- The subject line contains `[no-recap]` (explicit opt-out for trivial commits).
- The commit is a merge, a revert, or `--amend --no-edit`.
- All staged files match the trivial patterns: `.gitignore`, `README.md`, `CHANGELOG.md`, `.claude/**`, `LICENSE`.

## The three hooks

### `claude-code/pre-commit-recap.sh` — Claude Code `PreToolUse`

Fires when Claude Code tries to run `git commit -m "..."` (inline message path). Blocks before the commit happens if the message lacks a valid recap.

**Install.** Add a `PreToolUse` entry to your `.claude/settings.json` (per-project) or `~/.claude/settings.json` (user-global):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/absolute/path/to/hooks/claude-code/pre-commit-recap.sh"
          }
        ]
      }
    ]
  }
}
```

The hook reads the tool-call JSON from stdin, inspects the `tool_input.command`, and only acts if the command contains `git commit`. It's cheap on non-commit calls.

**Dependencies.** `jq`, `python3`, `bash`. Standard on Linux/macOS dev environments.

**Limitation.** Cannot see messages typed in `$EDITOR` (no `-m`) or passed via `-F -` (heredoc) — those cases are handled by the native git hooks below.

### `git/prepare-commit-msg` — native git, editor flow

Fires when `git commit` opens the editor (no `-m`). Pre-fills the buffer with a recap skeleton so the developer starts from the right template rather than remembering the syntax.

Exits quietly on `merge`, `squash`, `commit` (amend), `message` sources — those cases already carry their own message.

### `git/commit-msg` — native git, final validator

Fires after the message is finalized (all sources: `-m`, editor, `-F`). Last line of defense: validates the recap block and rejects the commit on malformed blocks.

This is the one you want even if you never use Claude Code — it catches humans who forgot the block too.

## Installing the native git hooks

Two options.

### Option A — per-clone (`.git/hooks/`)

Copy into the target repo's hooks dir:

```bash
cp hooks/git/prepare-commit-msg /path/to/repo/.git/hooks/
cp hooks/git/commit-msg /path/to/repo/.git/hooks/
chmod +x /path/to/repo/.git/hooks/prepare-commit-msg
chmod +x /path/to/repo/.git/hooks/commit-msg
```

Each clone of the repo needs this done once. Not shared through git.

### Option B — shared via `core.hooksPath`

Commit the `hooks/git/` directory in your repo, then:

```bash
git config core.hooksPath hooks/git
```

Everyone who clones and runs the one-time `git config` gets the hooks. Trade-off: you need a policy to ensure team members actually run the config.

## Troubleshooting

**"Commit blocked: no recap block" but I ran the skill.**
The skill proposed the message — check that the final `git commit` command actually included the block. The block must be inside `-m "..."` or in the editor buffer that `commit-msg` sees.

**`jq: command not found` in the Claude Code hook.**
Install `jq` (`apt install jq`, `brew install jq`). The hook exits 0 (non-blocking) on unrelated tool calls, but needs `jq` to parse the tool-input JSON.

**`python3` in the Claude Code hook.**
The hook uses Python's `shlex` to parse the `git commit` command line robustly (handles quoted args, `-m` vs `--message=`, multi-`-m`). If Python 3 isn't available, consider using the native git `commit-msg` hook alone — it's independent of Python.

**A commit I expected to pass is blocked.**
Check the escape-hatch rules at the top of this file. In particular: staged-file patterns are matched literally, so a file outside the `.claude/**`, `LICENSE`, `README.md`, `CHANGELOG.md`, `.gitignore` set will defeat the "all trivial" check even if the other files are trivial. Add `[no-recap]` to the subject to force through a truly trivial commit.

**The hook lets a malformed commit through.**
Please report, with the commit message and the hook's `set -euo pipefail` trace if possible. Silent-skip is the worst failure mode for a validator.
