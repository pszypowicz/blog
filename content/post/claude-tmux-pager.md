+++
title       = "An on-call pager for Claude Code sessions in tmux"
date        = "2026-07-24T12:00:00+02:00"
description = "Several Claude Code sessions across tmux windows either get babysat or sit blocked on prompts nobody saw. The fix is notifications with on-call semantics: page only when unseen, click to jump there, clear on return."
tags        = ["claude-code", "tmux", "macos", "notifications"]
categories  = ["macos"]
ai_assisted = true
+++

I usually have a few Claude Code sessions running at once, one per tmux window. That leaves two failure modes: either I babysit - cycling through windows to check who needs what - or I don't, and an agent sits at a permission prompt for twenty minutes while I work two windows over.

Notifications are the obvious answer, and the naive versions all fail once there is more than one session:

- **A terminal bell** tells you _that_ something wants attention, not which of five windows, and only while you are looking at the terminal.
- **`osascript display notification`** is a dead end twice over. The notification is attributed to Script Editor, so clicking it lands you in Script Editor. And there is no way to withdraw one once delivered, so Notification Center fills with lies: the prompt was answered ten minutes ago, the toast still says "waiting for your input".
- **Identical toasts don't triage.** Five copies of "Claude is waiting for your input" carry no information about which session is worth visiting first.

What I actually wanted has on-call semantics: page me only for actionable events I cannot already see, name the what and the where, let me ack by showing up, and auto-resolve. The setup is three pieces - Claude Code hooks, a small macOS agent called [Pager](https://github.com/pszypowicz/pager), and two tmux hooks that close the loop.

## Piece 1: Claude Code fires a hook

Claude Code's `Notification` hook events cover exactly the moments a session blocks on me. In `settings.json`, three matchers route to one script:

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

## Piece 2: deciding whether and what to page

[`bell.sh`](https://github.com/pszypowicz/dotfiles/blob/main/dot-config/claude/hooks/bell.sh) reads the hook payload and asks tmux where it is running:

```bash
INFO="$(tmux display-message -p -t "$TMUX_PANE" \
  '#{window_active} #{session_attached} #{window_index} #{window_id} #{session_id} #{session_name}')"
```

macOS-level focus is invisible to a shell hook, so "attached session + active window" is the closest available approximation of "I am looking at it". Only background windows and detached sessions page; the visible one would just be telling me what is already on screen. Whether it pages or not, the hook also returns a BEL through the `terminalSequence` field, which makes Ghostty bounce the Dock while unfocused - tmux forwards bells to attached clients by default, so that path needs zero configuration.

The body is where triage happens. For permission prompts, the payload's message already says what is being asked. For idle events the stock message is the useless "waiting for your input", so the script tails the session transcript and takes Claude's last reply instead. Replies that fit the ~150-character notification budget pass through untouched; longer ones get summarized on-device by [afm-summarize](https://github.com/pszypowicz/afm-summarize), a small wrapper around the Apple Intelligence foundation model. With several sessions running, the notification itself tells me which one finished with "all tests pass" and which one wants to `rm -rf` something.

## Piece 3: Pager posts it

Pager is a single Swift binary that is both a login-item agent and a CLI, built because of the `osascript` dead end above. It posts notifications under its own identity, carries a real click handler, and - the part nothing else offers - exposes a `remove` command:

```sh
pager post --key @7 --title "Claude needs you" --subtitle "work / window 3" \
  --body "waiting for input" --sound Funk --session-id '$2' --window-id @7
```

Clicking the notification switches the most recently used tmux client to that window and brings Ghostty forward. From the toast to the blocked prompt is one click.

## Closing the loop: tmux clears the page

The half that keeps Notification Center honest is two hooks in `tmux.conf`:

```tmux
set-hook -g pane-focus-in       'run-shell -b "pager remove --key #{window_id}"'
set-hook -g after-select-window 'run-shell -b "pager remove --key #{window_id}"'
```

Whenever I land on a window - by clicking the page, by `prefix + f` through the sessionizer, by any route at all - any page that window raised is withdrawn. With `focus-events on`, `pane-focus-in` also fires when Ghostty itself regains focus, so a page clears even when I return to an already-current window. `run-shell -b` keeps both hooks off the UI thread, and when there is nothing to remove the call is a no-op.

The invariant that falls out: a notification exists exactly while a window needs me and I am not looking at it. Nothing stale, nothing to swipe away.

## One key, three jobs

The load-bearing choice is keying everything on tmux's `#{window_id}`. That single identifier is:

- the **dedup key** - a repeated prompt from the same window replaces its page instead of stacking a new one,
- the **routing target** - the click handler knows which window to focus,
- the **removal handle** - the focus hooks pass the same id to withdraw it.

Window _indices_ would break this: with `renumber-windows on` they reshuffle whenever a window closes, and the dismiss would miss. `#{window_id}` is server-unique and never reused, so a page still matches its window at dismiss time. The human-readable session name and index ride along in the subtitle only.

## Every failure is a downgrade, not a loss

Each stage degrades to the one below it rather than erroring:

- summarizer missing, timing out, or refusing → clip the reply to 150 characters,
- transcript unreadable → fall back to the payload's stock message,
- `pager` not on the tmux server's PATH → the remove hook is a harmless no-op (use an absolute path if posting fails too - a launchd-started agent does not inherit your interactive PATH),
- not inside tmux at all → no page, just the BEL and a Dock bounce.

The page always fires in some form; only its quality varies.

## Summary

- Claude Code `Notification` hooks fire on permission prompts, input requests, and idle.
- A hook script pages only for windows I cannot see, with the agent's last reply as the body.
- Pager posts a clickable macOS notification; the click jumps to the exact tmux window.
- tmux focus hooks withdraw the page the moment I return, clicked or not.

Pager is `brew install pszypowicz/tap/pager` (macOS 15+, pre-1.0 so flags may still shift). The hook script and tmux config live in my [dotfiles](https://github.com/pszypowicz/dotfiles).
