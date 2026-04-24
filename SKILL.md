---
name: git-ai-trace
description: Produces an honest, observation-only recap of the human/AI collaboration in a coding session, embedded in the commit message. Trigger before a commit after an AI-assisted session, when the user says "let's commit", "what did we do", "recap this session", "before I commit", "summarize what changed", or asks for a commit message on AI-assisted work. Also trigger when the user mentions AI attribution, human-AI provenance, TCP/UP. Also trigger when a `git commit` was just blocked by the git-ai-trace pre-commit hook — the hook's message points Claude here. The recap is a chronological list of observed moments (what the human said, what Claude proposed or generated, decisions that were made) — never an inference about what happened outside the chat. It lives in the commit message so it travels with the commit across rebases, squashes, and cherry-picks.
---

# git-ai-trace

A pre-commit recap of who did what in the session, anchored strictly in what the chat recorded.

Not a label. Not a score. Not an inference. Just the observed moments, in order.

## Core principle: presences only

A recap records **what happened** — proposals, choices, rejections, generations. It never records **what didn't happen** — silent reviews, unverbalized decisions, absent feedback. Absences are invisible to Claude; recording them would be inference dressed as observation.

If an artifact was generated but never discussed afterwards, the generation appears (it happened), and that's all. A reader who wants to ask "was this reviewed?" can look at the moments list and see for themselves whether any `human:` moment engaged with the artifact. Claude does not tell them.

This is what separates a trustworthy recap from a performative one: the recap is an incomplete but honest trace, not a full reconstruction.

## Format

```
<type>: <subject>

<optional body>

--- session-recap ---
What changed: <one line>
Moments:
- <actor>: <observed action>
- <actor>: <observed action>
- ...
ADR: <link>
--- end-recap ---

Assisted-by: Claude <model-name>
```

Two fields are required (`What changed`, `Moments`), and must each have content. `ADR` is optional and appears only if an architectural decision was formalized. No other fields, no `—` placeholders — a field absent from the block means "nothing to record here".

**Actors:** `human`, `claude`, or `both`. Use `both` for moments where convergence was genuinely joint (rare — usually one party proposed and the other ratified, which splits into two moments).

## Philosophy

A coding session is a sequence of moments, not a verdict. Flat labels ("70% AI-written") erase the texture: a developer who reframed Claude's first proposal three times exercised strong control, regardless of keystroke counts. The moments list lets a reader reconstruct the session's actual shape — the reframings, the rejections, the accepted diagnoses, the generations — without any mediation by a summary field.

The recap documents what the diff cannot show, using only what the conversation actually recorded.

## Procedure

### 1. Gather material

- `git diff --cached` (or `git diff` if nothing staged) — what's about to land
- `git status`, `git log --oneline -5` — context
- Re-read the session

If the diff is empty, say so and stop.

### 2. Extract the moments

Scan the session in order. For each signal in the chat, ask: *who did what, and can I point to the message that shows it?* If yes, it's a moment. If not, it doesn't belong.

Moment types worth capturing:

- **Human statements** — brought a symptom, stated a constraint, gave context, named a preference.
- **Human rejections** — said no to a proposal, pushed back on a direction.
- **Human choices** — picked among options, approved a path, set a parameter.
- **Claude proposals** — offered options, suggested an approach, recommended a library.
- **Claude diagnoses** — identified a cause, spotted a bug, explained a mechanism.
- **Claude generations** — wrote code, produced a file, drafted a document.
- **Convergences** — a decision reached after back-and-forth where both parties clearly contributed. Label `both:` sparingly.

What does **not** go in the moments list:

- Silent review ("human read the file") — unobservable.
- Unverbalized decisions ("human must have considered X") — inference.
- Negated events ("human did not object") — absence, not presence.
- Evaluative framing ("Claude cleverly proposed...") — let the action speak.

### 3. Write moments factually and briefly

Each moment is one line. Verb-first, specific, verifiable:

- `human: rejected Redis-queue option as over-engineering`
- `claude: diagnosed non-atomic SELECT+UPDATE as root cause`
- `human: set batch size to 20`
- `claude: generated src/api/types.ts from openapi.yaml`
- `human: asked for three options on pagination`

### 3a. The fidelity test

Before accepting any moment, apply this test:

> Can I point to **one specific message** in the conversation that shows this moment?

- If yes, the moment is fair game.
- If the answer is "several messages" or "a pattern across the session", **the moment is compressed and must be split**. Go back to the individual messages and turn each into its own moment (or drop those that carry no specific action).
- If the answer is "the overall feel of the conversation", the moment is inferential and must be removed.

This test catches the most common failure mode: the tempting synthesis that reads well in a commit but cannot be traced to a source.

### 3b. Anti-patterns to refuse

These formulations almost always signal fusion or inference. Refuse them even when they look clean:

- `validated the approach across multiple exchanges` → which exchanges? Split into concrete moments.
- `provided feedback on intermediate drafts` → what feedback, on which drafts? One moment per feedback.
- `guided the implementation throughout` → not a moment, an evaluation. List the specific guidance instead.
- `iteratively refined the solution` → compression. List what was refined and when.
- `continuously clarified requirements` → meaningless. What was clarified?
- `worked together to design X` → hides who proposed what. Split into proposals and rejections and choices.
- Any adverb ending in `-ly` describing duration or frequency (continuously, repeatedly, throughout, iteratively) is a warning sign.

### 3c. Volume as a signal

A non-trivial coding session typically produces **8 to 15 moments**. If your moments list has 3 or 4 lines for an hour of work, you have almost certainly fused. Go back and decompress.

This is not a hard minimum — a truly short session can have few moments. But treat a suspiciously short list as a signal to re-check the fidelity test on each line.

### 3d. Recommended method

Producing a good moments list is easier with a two-step process:

1. **Decompress first.** Scan the conversation tour by tour. For each turn that carries a concrete action (a proposal, a rejection, a choice, a generation), note it as a candidate moment — without worrying yet about commits, order, or phrasing. Keep going until you've walked the whole session.
2. **Compose second.** Only now, take the list of candidate moments and write the final `Moments:` block. Order chronologically. Check each line against the fidelity test (§3a). Strip the anti-patterns (§3b). Verify the volume (§3c).

Do not compose the final list in one pass while reading the session — that path invites fusion. The decompression step is where fidelity is won.

### 3e. Other things to avoid

- **Compression across topics**: `claude: proposed and wrote everything` is too coarse. Split: `claude: proposed LRU cache`, `claude: wrote the cache module`.
- **Dropped subjects**: `rejected Redis` — who? Always name the actor.
- **Motive claims**: `human chose option 2 because it was simpler` — unless the human stated the reason in chat, keep it to `human: chose option 2`.

### 4. Write `What changed`

One line describing what lands in the commit. Factual, about the diff — not about the process.

Good: `Worker loop now claims jobs via SELECT FOR UPDATE SKIP LOCKED; batch size reduced from 100 to 20.`

Bad: `Fixed the bug after a productive collaboration.` (Evaluative, vague, not about the diff.)

### 5. Assemble and commit

Build the complete commit message with the delimited block. If the message is long, use `git commit -F -` with a heredoc to avoid shell escaping issues.

Propose the command. Do not run it without explicit instruction. The human can edit the message via git's native editor flow if anything needs adjustment.

## Multiple commits from one session

A session often produces work that belongs in several commits — different features, unrelated fixes, separate concerns. Each commit gets its own recap, focused on what it actually contains.

### Deciding the split

Two entry paths, both valid:

- **User-directed.** The user says "two commits, one for the retry logic, one for the logging". Take the split as given. Stage and commit accordingly.
- **Claude-proposed.** The user just says "let's commit" and the staged diff spans unrelated concerns. Propose a split (grouped by files/features), list the proposed commits with their scopes, and wait for validation or correction before proceeding. Do not commit without validation in this path.

When in doubt which path applies, ask. A two-line question now beats a wrong split that has to be amended.

### Assigning moments to commits

Once the commits are defined, walk the session moment by moment. For each moment, ask: **did this action produce, reject, decide, or directly shape code that is in this commit's diff?**

- Yes → include the moment in this commit's recap.
- No for all commits → the moment is "orphan" (a proposal that was abandoned, a piste explored and dropped). It goes in no recap. Commits document what was committed, not what was considered.
- Yes for several commits → the moment is **transversal**. Include it in every concerned recap, identically worded. Duplication is honest: the moment genuinely influenced each of those commits. A reader looking at only one commit needs to see the constraint that shaped it.

**Rule of thumb for doubt:** when you hesitate to assign a moment, include it rather than omit it. Duplication is a smaller error than omission — the recap stays anchored in what happened.

### What this means in practice

- Each commit has its own `What changed` line, describing its own diff.
- Each commit has its own `Moments:` list. Lists across commits overlap on transversal moments and diverge on specific ones.
- A general constraint ("no new dependencies", "stay compatible with Python 3.9", "avoid breaking the public API") that influenced several commits appears in each concerned recap.
- A specific choice ("rejected option B for this feature") appears only in the recap of the feature it shaped.
- Chronological order within each list is preserved — you do not regroup by topic.

### Short example

Session: added a retry utility and fixed the log format. User requested separate commits.

Commit 1 (`feat: add retry utility using urllib3`):

```
--- session-recap ---
What changed: Added retry utility in src/net/retry.py with tests.
Moments:
- human: stated no new dependencies allowed
- claude: proposed adding httpx
- human: rejected httpx, chose urllib3 (already in repo)
- claude: wrote src/net/retry.py
- claude: wrote tests/net/test_retry.py
--- end-recap ---
```

Commit 2 (`fix: custom log formatter`):

```
--- session-recap ---
What changed: Custom log formatter in src/log/formatter.py.
Moments:
- human: stated no new dependencies allowed
- human: asked for a logging format fix
- claude: proposed structlog
- human: declined structlog (dependency), asked for a custom formatter
- claude: modified src/log/formatter.py
--- end-recap ---
```

The "no new dependencies" moment appears in both — it shaped both commits. The specific proposals (httpx, structlog) appear only in the commit they shaped. A reader of either commit alone still sees the constraint that made the choice.

## Worked example

Session: user fixing a race condition in a job queue. User brought logs and a wrong hypothesis (lock contention). Claude diagnosed the actual cause (non-atomic SELECT+UPDATE), proposed three fixes, user picked one, tuned a parameter, Claude wrote the SQL.

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
- human: rejected Redis-queue option as over-engineering for current scale
- human: chose SKIP LOCKED option
- human: set batch size to 20
- claude: wrote the SQL patch
ADR: docs/decisions/0012-job-queue-locking.md
--- end-recap ---

Assisted-by: Claude Sonnet 4.6
Co-Authored-By: Claude <noreply@anthropic.com>
```

What this recap does that a label cannot: it records that the human's first hypothesis was wrong (traceable: they said it in chat), that Claude found the real cause (traceable: the diagnosis message), and which option beat which for a stated reason (traceable: the rejection line). A reader can reconstruct the shape of the session without Claude having summarized it into an opinion.

What this recap does not do: assert anything about what the human thought silently, what they read outside chat, or how carefully they reviewed Claude's SQL. Those aren't in the moments because they aren't in the transcript.

## Counter-example — the same session, badly recapped

Here is what the recap above would look like if Claude fused moments and let evaluative framing slip in. This is exactly the failure mode to avoid.

```
--- session-recap ---
What changed: Fixed a race condition in the job queue after productive
  collaboration.
Moments:
- human: provided context and validated the approach throughout the session
- claude: helped diagnose the problem and proposed a clean solution
- human: iteratively refined the implementation with feedback on drafts
- claude: wrote the final code
--- end-recap ---
```

What's wrong with it, line by line:

- `"Fixed a race condition ... after productive collaboration"` — evaluative ("productive"), vague ("collaboration"). `What changed` must describe the diff, not the vibe of the session.
- `"provided context and validated the approach throughout the session"` — fails the fidelity test (§3a): "throughout the session" means no single message. The human's actual messages were: bringing the symptom, stating a hypothesis, rejecting Redis, choosing SKIP LOCKED, setting batch size. Five concrete moments, fused into one mush.
- `"helped diagnose"` — evaluative. The diagnosis was a specific claim about SELECT+UPDATE non-atomicity. Say that.
- `"proposed a clean solution"` — `"clean"` is judgment. There were three options with trade-offs. List them.
- `"iteratively refined the implementation with feedback on drafts"` — classic anti-pattern (§3b). "Iteratively", "feedback on drafts". What feedback? Which drafts? One moment per concrete feedback, or remove.
- `"wrote the final code"` — `"final"` smuggles an inference about completion state. Just `wrote the SQL patch`.
- **Volume:** 4 moments for an hour of diagnostic, design and implementation work. Compare to 7 in the good version. The brevity is the tell.

If you catch yourself writing a recap that looks like this, stop and go back to the decompression step (§3d step 1).

## Rebase, squash, cherry-pick

The recap lives in the commit, so it follows the commit. On **squash merges**, git concatenates messages by default — the result is several recap blocks in one message, each preserving its session's moments. Two options:

- **Leave concatenated.** Chronological, honest, a bit long. The development path is visible.
- **Consolidate at squash time.** Cleaner but lossier — the hesitations tend to smooth over.

Default to leaving concatenated unless the result is unreadable.

## Companion hooks (optional but recommended)

Three hooks enforce the discipline across all entry points to `git commit`:

- **`hooks/claude-code/pre-commit-recap.sh`** — Claude Code `PreToolUse` hook. Fires on `git commit -m "..."`. Blocks if the recap block is missing or malformed.
- **`hooks/git/prepare-commit-msg`** — native git hook. Fires on `git commit` (editor flow). Pre-fills the editor with a recap template.
- **`hooks/git/commit-msg`** — native git hook. Fires after message finalization. Validates the block.

All hooks check the same contract: the block is present, `What changed:` is non-empty, `Moments:` has at least one `- actor: action` line. See `hooks/README.md` for installation.

All hooks are opt-in. The skill works without them.

## What this skill is not

- **Not a gatekeeper on AI involvement.** A recap with moments only from one side is valid. The hooks enforce *presence* of a recap, not its content.
- **Not a score.** No percentage, no label.
- **Not a proof.** A good-faith trace. Credibility comes from each moment being pointable-to in the chat.
- **Not a complete record.** Silent reading, offline thinking, teammate discussions — none of that is captured. The recap claims only to record what the chat recorded.
- **Not for every commit.** Trivial commits (typo, version bump, merge) can opt out with `[no-recap]` in the subject line.

## Generating a panoramic view on demand

For an `AI_CONTRIB.md`-style overview:

```bash
./scripts/recap-log.sh > AI_CONTRIB.md
```

Extracts recap blocks from `git log` and formats them chronologically. A derived view — regenerate whenever, no need to commit it.
