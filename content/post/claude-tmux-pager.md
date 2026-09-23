+++
title       = "An on-call pager for Claude Code sessions in tmux"
date        = "2026-07-24T12:00:00+02:00"
lastmod     = "2026-09-23T12:00:00+02:00"
description = "Running several Claude Code sessions in tmux means either babysitting them or leaving one stuck on a prompt nobody saw. I wired Claude Code hooks, a small macOS notification agent, and two tmux hooks into a paging loop that only fires when I'm not looking."
tags        = ["claude-code", "tmux", "macos", "notifications"]
categories  = ["macos"]
ai_assisted = true
+++

I usually have a few Claude Code sessions running at once, one per tmux window. Without notifications I either keep cycling through the windows to check on them, or I forget about one and it sits at a permission prompt for twenty minutes while I work two windows over.

macOS notifications are the obvious answer, but the easy ways of sending them stop working well once more than one session is involved.

A terminal bell was my first attempt. tmux forwards bells to attached clients out of the box and Ghostty bounces the Dock, but a bell carries no text, so I still had to hunt for the window that rang. A detached session can ring all it wants.

`osascript display notification` was the second. Notifications sent that way are attributed to Script Editor, so clicking one opens Script Editor instead of my terminal. There is also no way to withdraw a notification after it has been delivered, which means Notification Center slowly fills up with prompts I answered ten minutes ago.

The text of the notification turned out to matter too, because five copies of "Claude is waiting for your input" give me no idea which session to visit first.

What I ended up building works like an on-call pager. It pages me only about sessions I cannot already see, each page says which window is asking and what for, and the page clears itself when I show up. Three pieces are involved. Claude Code hooks decide when something is worth a page, a small macOS agent called [Pager](https://github.com/pszypowicz/pager) delivers it, and two tmux hooks clear it again.

## The Claude Code hooks

Claude Code fires `Notification` hook events at the moments a session blocks on me. In `settings.json`, three matchers route them to one script:

```json
"Notification": [
  { "matcher": "permission_prompt|elicitation_dialog",
    "hooks": [{ "type": "command", "command": "~/.config/claude/hooks/bell.sh --event notification" }] },
  { "matcher": "agent_needs_input",
    "hooks": [{ "type": "command", "command": "~/.config/claude/hooks/bell.sh --event notification" }] },
  { "matcher": "idle_prompt",
    "hooks": [{ "type": "command", "command": "~/.config/claude/hooks/bell.sh --event idle" }] }
]
```

## Deciding when to page

[`bell.sh`](https://github.com/pszypowicz/dotfiles/blob/main/dot-config/claude/hooks/bell.sh) reads the hook payload and asks tmux where it is running:

```bash
INFO="$(tmux display-message -p -t "$TMUX_PANE" \
  '#{window_active} #{session_attached} #{window_index} #{window_id} #{session_id} #{session_name}')"
```

A shell hook cannot see macOS focus, so the script treats "the window is active in an attached session" as the best available approximation of "I am looking at it" and skips the page in that case, because a notification about the window already on screen would tell me nothing new. Pages only go out for background windows and detached sessions. Whether it pages or not, the hook also returns a BEL through the `terminalSequence` field, which makes Ghostty bounce the Dock while it is unfocused. tmux forwards bells to attached clients by default, so this part needs no configuration at all.

The notification text is what makes several sessions manageable. For permission prompts the payload's message already says what is being asked. For idle events the stock message is just "waiting for your input", so the script tails the session transcript and uses Claude's last reply instead. A reply that fits the roughly 150-character notification budget passes through untouched, and longer ones get summarized on-device by `fm`, the command-line tool for the Apple Foundation Model that ships with macOS 27. When several sessions are running, the notification itself tells me which one finished with passing tests and which one wants to `rm -rf` something.

## Holding the page while background work runs

The idle event also fires when Claude is only waiting on its own background work. A session that starts subagents or a background shell command goes idle right away, and Claude Code wakes it again each time one of them finishes. A page at that moment sends me to a window where there is nothing for me to do yet, and the page after the last wake-up carries the real result anyway.

Three more hooks keep a count of that work per session, all wired to one script, [`agents-in-flight.sh`](https://github.com/pszypowicz/dotfiles/blob/main/dot-config/claude/hooks/agents-in-flight.sh):

```json
"Stop": [{ "hooks": [{ "type": "command", "command": "~/.config/claude/hooks/agents-in-flight.sh --event stop", "timeout": 5 }] }],
"UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/.config/claude/hooks/agents-in-flight.sh --event prompt", "timeout": 5 }] }],
"SessionEnd": [{ "hooks": [{ "type": "command", "command": "~/.config/claude/hooks/agents-in-flight.sh --event end", "timeout": 5 }] }]
```

The `Stop` payload includes `background_tasks`, which is the task registry's own list of work still in flight. The script counts the entries of type `subagent` or `shell` and writes the number to a small file named after the session id. When `bell.sh` handles an idle event, it reads that file and stays silent while the number is above zero. It skips the BEL as well, because a Dock bounce would be the same false alarm.

Counting `SubagentStart` and `SubagentStop` events would look simpler, but `SubagentStop` does not fire for an agent stopped with `TaskStop` or by exiting the session ([anthropics/claude-code#92716](https://github.com/anthropics/claude-code/issues/92716)), so that count would drift upward. The registry drops those agents by itself.

The other two hooks cover the cases where no `Stop` fires. An interrupted turn ends without one, so `UserPromptSubmit` clears the count when I send the next prompt and a stale hold cannot outlive the turn. `SessionEnd` removes the file, and the `stop` branch also deletes files older than two days that sessions left behind when they died without a `SessionEnd`. Every path in the script exits 0 and prints nothing, because a failing `Stop` hook can keep Claude from ending its turn.

Counting background shell commands has one cost. A long-running command such as a dev server started in the background holds the idle page for as long as it runs.

## Pager

Pager is a single Swift binary that runs as a login-item agent and doubles as its own CLI. I wrote it because of the `osascript` problems above. It posts notifications under its own identity, it handles clicks, and it can withdraw a notification that was already delivered:

```sh
pager post --key @7 --title "Claude needs you" --subtitle "work / window 3" \
  --body "waiting for input" --sound Funk --session-id '$2' --window-id @7
```

Clicking the notification switches the most recently used tmux client to that window and brings Ghostty forward, so getting from the notification to the blocked prompt takes a single click.

## Clearing the page

The other half of the loop is two hooks in `tmux.conf` that withdraw a page when I return to the window that raised it:

```tmux
set-hook -g pane-focus-in       'run-shell -b "pager remove --key #{window_id}"'
set-hook -g after-select-window 'run-shell -b "pager remove --key #{window_id}"'
```

It does not matter how I get there. Clicking the notification, jumping through the session picker, and plain `prefix + n` all land in one of these hooks, and the page is removed. Because `focus-events` is on, `pane-focus-in` also fires when Ghostty itself regains focus, so a page clears even when I come back to a window that was current the whole time. `run-shell -b` keeps both hooks from blocking the tmux UI, and when there is nothing to remove the call does nothing.

The end result is that a notification exists only while a window actually needs me and I am not looking at it, and I never have to clean up Notification Center by hand.

## Why the key is the window id

All three pieces agree on tmux's `#{window_id}` as the notification key. Pager uses it to deduplicate, so a repeated prompt from the same window replaces its earlier notification instead of stacking a new one. The click handler uses it to find the window to focus. And the tmux hooks pass the same id to `pager remove` at dismiss time.

Window indices would not survive this round trip, because `renumber-windows on` reshuffles them whenever a window closes, and a page posted as window 3 might need to be dismissed as window 2. `#{window_id}` is unique for the lifetime of the tmux server and never reused, so the id on a page always matches the window that raised it. The readable session name and window index still appear, but only in the subtitle.

## Fallbacks

Each stage falls back to something simpler instead of failing. If `fm` is missing, times out, or refuses, the reply is clipped to 150 characters. The one exception is a machine where nobody has agreed to Apple's terms for the model yet. There the page says to run `sudo fm license` instead, because every long reply fails the same way until someone runs that command once. If the transcript cannot be read, the stock hook message is used. If there is no count file for the session, the idle page goes out as usual. If `pager` does not resolve on the tmux server's PATH, the remove hook quietly does nothing, and the fix is an absolute path in the hook, because a launchd-started tmux server does not inherit an interactive PATH. Outside tmux there is no page at all, only the BEL and the Dock bounce.

## Summary

- Claude Code `Notification` hooks fire on permission prompts, input requests, and idle.
- A hook script pages only about windows I cannot see, with the agent's last reply as the message.
- The idle page waits while the session still has background subagents or shell commands running.
- Pager posts a clickable macOS notification, and clicking it jumps to the exact tmux window.
- tmux focus hooks withdraw the page the moment I return, whether I clicked it or not.

Pager is `brew install pszypowicz/tap/pager` (macOS 15+, and pre-1.0, so flags may still shift). The hook script and tmux config live in my [dotfiles](https://github.com/pszypowicz/dotfiles).

**Update, September 2026:** Two things changed since the first version of this post. The idle page now waits for background work, as described in [Holding the page while background work runs](#holding-the-page-while-background-work-runs). Summaries now come from `/usr/bin/fm` in macOS 27 instead of [afm-summarize](https://github.com/pszypowicz/afm-summarize), a small Swift wrapper I wrote around the Foundation Models framework. It is the same on-device model with the same instructions, and there is one less package to install.
