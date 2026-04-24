# Design rationale

This document is the longer story of *why* `git-ai-trace` looks the way it does. The short version is in [`README.md`](../README.md). The brainstorming chat that produced the form you see here lives at https://claude.ai/share/94425cfb-f4d5-4326-97c7-aac419d4f2c3.

## Starting point: binary disclosure isn't enough

"Was this code written with AI?" is a yes/no question that fails the actual inquiry. Two commits that both answer "yes" can look completely different in how the human exercised control:

- *Commit A:* developer asked for a retry utility, Claude proposed three libraries, developer rejected two for dependency reasons, set a parameter, asked for tests, accepted Claude's implementation after reading it. Heavy human steering.
- *Commit B:* developer said "add retry logic", Claude generated a file, developer accepted without comment. Pure delegation.

The diffs might look identical. The binary flag erases the distinction. Reviewers who want to know *how much to trust the code* — a legitimate, increasingly common question — get nothing useful from "was AI used?"

So the real question is: **who drove what?** And the honest answer is a sequence of moments, not a summary.

## Why not labels (TCP/UP)

[TCP/UP](https://tcp-up.org/) proposes five labels (HUC, HCA, HCE, ACE, AIC) distinguishing degrees of human vs AI centricity in editorial content. The philosophy is sound — good-faith, declarative, commitment to justifiable sincerity — and `git-ai-trace` keeps that spirit.

But TCP/UP is optimized for documents. Applied to code commits, the labels flatten in a specific way:

- **The unit is wrong.** A label attaches to a document; a commit attaches to a diff spanning multiple files and concerns. Which label applies when one file was Claude-generated and another was human-rewritten three times?
- **Five bins is coarse.** The distinction between *"human reviewed and approved"* and *"human reframed twice then approved"* is exactly the kind of texture the labels cannot encode. Both are HCA or ACE depending on how you squint.
- **A label is a verdict.** The reader has to trust the labeler's judgment about where the line falls. The moment-list form makes the reader the judge — they see the concrete actions, they decide the label in their head if they want one.

`git-ai-trace` takes the opposite trade-off: more lines, less abstraction. Let the reader do the categorization if they want one.

## Why not a separate file (AI_ATTRIBUTION.md)

[Ismet Handzic's AI_ATTRIBUTION.md](https://github.com/ismet55555/ai-attribution) is closer in spirit — chronological log of creative control, six involvement levels, maintained in a file at the repo root. The chronological-moments intuition is exactly right and shaped our thinking. But the separate-file form has three fatal problems for a git-native workflow:

- **Rebases lose it.** An interactive rebase reorders and combines commits. `AI_ATTRIBUTION.md` lines tied to original commit SHAs are now pointing to rewritten history. The file either drifts or has to be manually patched — which nobody will do.
- **Squash merges drop it.** On GitHub, squash merges collapse a PR's commits into one. The individual AI_ATTRIBUTION entries per commit either all collapse into the squashed commit's entry (losing texture) or stay in the file, now disconnected from any remaining commit.
- **Merge conflicts every time.** A shared file at the repo root that every contributor appends to will conflict on every parallel PR. The tool that is supposed to make attribution easier becomes a source of merge friction.

The recap in the commit message itself solves all three: it travels with the commit through rebases, concatenates naturally on squashes (multiple recap blocks in one message is honest — it shows the development path), and lives in a non-shared field.

The trade-off: the recap is only visible in `git log`, not browsable in the GitHub UI as a file. `scripts/recap-log.sh` regenerates the `AI_CONTRIB.md`-style panoramic view on demand — as a derived view, never committed.

## Why "presences only"

The instinct to record absences is strong. Phrases like *"human silently accepted"* or *"Claude did not push back"* feel informative. They are not. They are inference dressed as observation — and in a tool whose entire credibility rests on each moment being pointable to a specific chat message, that distinction is load-bearing.

If the chat contains no human message engaging with an artifact, the recap cannot tell you whether:
- the human read it carefully and had no comment,
- the human skimmed it,
- the human didn't read it at all.

The chat can't distinguish these either. A recap that claims to know is lying. A recap that records only what the chat shows — the artifact was generated, no human message about it exists in the transcript — lets a reader draw their own conclusion without Claude having smuggled in an inference.

This is the core honesty move. Everything else in the skill flows from it.

## Why the fidelity test

The fidelity test — *"can I point to one specific message that shows this moment?"* — catches the most seductive failure mode: the synthesis that reads well in a commit message but isn't actually in the chat. Phrases like:

- `validated the approach across multiple exchanges`
- `provided feedback on intermediate drafts`
- `guided the implementation throughout`

...all read smoothly, all feel informative, and all fail the test. They point to a pattern, not a message. When composing a recap, the temptation to write these is constant; the test is what keeps the discipline.

Volume (8–15 moments for a substantive session) is a backstop: a recap that's too short is almost always the result of fusion. Go back and decompress.

## What `git-ai-trace` does *not* solve

To be honest about the limits:

- **Not a proof.** A malicious or careless recap is possible. Credibility comes from *verifiability* — the reader can open the chat (if shared) or ask pointed questions if something reads wrong. The tool makes lying *harder* and verification *possible*, not lying impossible.
- **Not for every commit.** Trivial commits (version bumps, typo fixes) with `[no-recap]` opt out. Forcing a recap on every commit dilutes the meaning of the recap itself.
- **Not a complete record.** Offline thinking, teammate discussions, silent code review — none of that is captured. The recap claims only what the chat recorded.
- **Does not answer "should we allow AI-assisted contributions?"** That's a policy question, not a provenance question. `git-ai-trace` sits in the *"how do we record what happened"* corner of the policy space — orthogonal to the accept/reject question most OSS projects are currently working through. See [further reading in the README](../README.md#further-reading-adjacent-not-ancestors) for that conversation.

## Why commit messages at all?

The last, most boring-but-important reason: because that is where git stores unstructured authored context. PR descriptions vanish with the PR. Issue references rot. Separate files break as described above. The commit message survives every history operation git can do to a commit (because it *is* the commit). Putting the recap there is the only form that makes it as durable as the diff itself.
