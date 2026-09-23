+++
title       = "Claude Code reads AGENTS.md only when telemetry is on"
date        = "2026-09-23T12:00:00+02:00"
description = "Claude Code 2.1.277 added AGENTS.md support, but the loader sits behind a remote feature flag. With telemetry or nonessential traffic turned off, a local AGENTS.md is skipped without a warning. This is what I measured and the one-line CLAUDE.md I use instead."
tags        = ["claude-code", "agents-md", "telemetry", "privacy"]
categories  = ["macos"]
ai_assisted = true
+++

Claude Code 2.1.277 announced support for `AGENTS.md`. In a project with no `CLAUDE.md`, it is supposed to read `AGENTS.md` instead. I keep telemetry off in my shell, and in my repos the file never loaded. [Issue #95690](https://github.com/anthropics/claude-code/issues/95690) explains why, and I added [my own measurements](https://github.com/anthropics/claude-code/issues/95690#issuecomment-5791716755) to it. This post collects them in one place.

## Where the gate is

The loader ships as a built-in plugin called `agents-md`. Its registration in the 2.1.280 bundle looks like this:

```js
var W = !1;
var B = () => Oa("tengu_agents_md_mod", W);
var H =
  "AGENTS.md as project instructions: by default loaded where the project has no CLAUDE.md; ...";
```

`W` is the plugin's `isOnByDefault` value and it is `false`. `B` is `isAvailable`, and it asks a remote feature flag called `tengu_agents_md_mod`, with `false` as the fallback. When Claude Code cannot fetch the flag, the plugin is unavailable, and the local file is never read. Reading a markdown file from the working directory needs no network at all, but here it waits on a server-side switch.

## How I tested it

I made an empty directory that holds only an `AGENTS.md` with a canary word in it, and asked `claude -p` for the word. Each setup ran in two sessions, because the first session in a new configuration only fetches the flag and the second one uses it.

```sh
echo 'The canary word is PERIWINKLE.' > AGENTS.md
claude -p 'What is the canary word from the project instructions? Answer NONE if you have none. Do not read files.'
```

## What I measured

- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` blocks the feature, as the issue says.
- `DISABLE_TELEMETRY=1` blocks it too. With either variable set, `AGENTS.md` never loaded, so I had to clear both.
- Setting either variable to `0` does not help. The block stays in place. The environment variable docs say that any value counts, but that is easy to miss when you try to turn a feature on.
- An `env` block in the project's `.claude/settings.json` that clears both variables has no effect. There is no way to turn the feature on for a single repo.
- A session-level override does work from the second session on:

```sh
claude --settings '{"env":{"DISABLE_TELEMETRY":"","CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC":""}}'
```

None of these cases print a warning. The session starts, the model answers without the project instructions, and nothing tells you that a file was skipped. The issue also points out that third-party gateways, Bedrock and Vertex have the same problem, because the flag cannot resolve to true there either.

## The workaround

`CLAUDE.md` supports `@path` imports, and those do not depend on the flag. A one-line `CLAUDE.md` next to the `AGENTS.md` loads it with telemetry off:

```sh
echo '@AGENTS.md' > CLAUDE.md
```

With that file in place, the same canary test returns the word with `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` still set. The cost is one extra file per repo, which is what the `AGENTS.md` support was supposed to remove.

## What I would like to see

- Reading a local file should not depend on telemetry. If the gate has to stay for a gradual rollout, a startup warning when an `AGENTS.md` is present and skipped would save people the time I spent on a canary test.
- A global `AGENTS.md`. The plugin looks for `AGENTS.md` and `.claude/AGENTS.md` in project directories only, and there is no user-level file next to the user `CLAUDE.md`. Codex reads a global `~/.codex/AGENTS.md`, and the `/import` command in Claude Code can copy it into the user `CLAUDE.md`, but the copy does not follow later edits. If you keep one set of personal instructions for several agents, you still need an `@` import in the user `CLAUDE.md` that points at the shared file.
- Native support for shared agent skills. Codex reads skills from `.agents/skills` in the project and from `~/.agents/skills` in the home directory. Claude Code 2.1.280 knows those paths only in `/import`, which copies the skills into `.claude/skills`. I put a canary skill in `.agents/skills` and Claude Code did not list it, but it listed the same skill from `.claude/skills` in the same repo. A copy drifts from the source, so I link `.claude/skills` to `../.agents/skills` instead, and Claude Code follows that symlink.

Until then, I use the one-line `CLAUDE.md` for instructions and a symlink for skills.
