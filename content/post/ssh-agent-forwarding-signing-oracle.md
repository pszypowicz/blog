+++
title       = "Agent forwarding leaves a signing oracle on every host you land on"
date        = "2026-07-31T12:00:00+02:00"
description = "ssh -A exposes your agent's socket on the remote host, and anyone who can connect to that socket can authenticate as you for as long as your session lasts. ProxyJump moves the same traffic through the same box without leaving anything there to use."
tags        = ["ssh", "security", "proxyjump", "agent-forwarding"]
categories  = ["security"]
ai_assisted = true
+++

`ssh -A` usually starts as a one-off. You add it to get a `git push` working from a
build box, it drifts into a `Host *` block, and from then on every host you touch
gets a live connection back to the agent holding your keys.

The agent never hands over key material, which is the reason people stop worrying
about it. It signs whatever it is asked to sign, and a signature is all anyone
needs to authenticate as you.

<svg id="fa" viewBox="0 0 512 190" width="512" height="190" role="img" aria-labelledby="fa-t fa-d" xmlns="http://www.w3.org/2000/svg">
<title id="fa-t">Agent forwarding compared with ProxyJump</title>
<desc id="fa-d">With ssh -A the agent socket sits on hop1, and hop1 opens its own connection to the target using it while the laptop is idle. With ssh -J the agent stays on the laptop and the encrypted session passes through hop1 without stopping there.</desc>
<style>
#fa text{font-family:var(--mono-stack,ui-monospace,monospace);font-size:12px;fill:var(--ink,#222)}
#fa .b{fill:none;stroke:var(--rule,#999);stroke-width:1.5}
#fa .w{stroke:var(--rule,#999);stroke-width:1.5}
#fa .k{fill:var(--accent,#b44212)}
#fa .s{font-size:11px;opacity:.75}
#fa .d{opacity:.35}
#fa .m1{animation:fa1 5s ease-in-out infinite}
#fa .m2{animation:fa2 5s linear infinite}
@keyframes fa1{0%,12%{transform:translateX(0)}44%,56%{transform:translateX(84px)}88%,100%{transform:translateX(0)}}
@keyframes fa2{0%{transform:translateX(0);opacity:0}6%{opacity:1}94%{opacity:1}100%{transform:translateX(280px);opacity:0}}
@media (prefers-reduced-motion:reduce){#fa .m1,#fa .m2{animation:none}}
</style>
<g transform="translate(8,14)">
<text class="s" y="8">ssh -A: your agent socket sits on hop1, and hop1 can use it</text>
<rect class="b d" x="0" y="16" width="96" height="30" rx="3"/>
<rect class="b" x="196" y="16" width="96" height="30" rx="3"/>
<rect class="b" x="392" y="16" width="96" height="30" rx="3"/>
<text class="d" x="48" y="62" text-anchor="middle">laptop</text>
<text x="244" y="62" text-anchor="middle">hop1</text>
<text x="440" y="62" text-anchor="middle">target</text>
<line class="w d" x1="96" y1="31" x2="196" y2="31"/>
<line class="w" x1="292" y1="31" x2="392" y2="31"/>
<circle class="k" cx="244" cy="31" r="5"/>
<g class="m1"><circle class="k" cx="300" cy="31" r="3.5"/></g>
</g>
<g transform="translate(8,110)">
<text class="s" y="8">ssh -J: hop1 relays an encrypted stream and holds nothing</text>
<rect class="b" x="0" y="16" width="96" height="30" rx="3"/>
<rect class="b" x="196" y="16" width="96" height="30" rx="3"/>
<rect class="b" x="392" y="16" width="96" height="30" rx="3"/>
<text x="48" y="62" text-anchor="middle">laptop</text>
<text x="244" y="62" text-anchor="middle">hop1</text>
<text x="440" y="62" text-anchor="middle">target</text>
<line class="w" x1="96" y1="31" x2="196" y2="31"/>
<line class="w" x1="196" y1="31" x2="292" y2="31" stroke-dasharray="3 4"/>
<line class="w" x1="292" y1="31" x2="392" y2="31"/>
<circle class="k" cx="48" cy="31" r="5"/>
<g class="m2"><circle class="k" cx="104" cy="31" r="3.5"/></g>
</g>
</svg>

## What forwarding puts on the remote host

When you connect with `-A`, sshd on the remote host creates a listener socket for
your session and points `SSH_AUTH_SOCK` at it. Anything written to that socket
travels back over your connection to the agent on your laptop. OpenSSH 10.1 moved
those sockets under `~/.ssh/agent`, and before that they lived in
`/tmp/ssh-XXXXXXXX/agent.<pid>`.

Connecting to a Unix socket needs write permission on the socket plus traversal of
the directory holding it, so in practice the account running your session and root
can reach it. Root does not need your shell or your attention:

```bash
# on the remote host, as root, while your -A session is open
sock=$(find /home/*/.ssh/agent /tmp/ssh-* -type s 2>/dev/null | head -1)

SSH_AUTH_SOCK=$sock ssh-add -l          # every key loaded on my laptop
SSH_AUTH_SOCK=$sock ssh -T git@github.com   # authenticates as me
```

The socket is removed when the session ends, so the exposure is bounded by how long
you stay logged in. That bound is weaker than it sounds, because a few seconds are
enough to authenticate somewhere and push a commit, and the host picks the moment
rather than you.

## What the man page already tells you

None of this is obscure. It is in `ssh(1)` under `-A`:

> Agent forwarding should be enabled with caution. Users with the ability to bypass
> file permissions on the remote host (for the agent's UNIX-domain socket) can
> access the local agent through the forwarded connection. An attacker cannot
> obtain key material from the agent, however they can perform operations on the
> keys that enable them to authenticate using the identities loaded into the agent.
> A safer alternative may be to use a jump host (see -J).

The last sentence is OpenSSH recommending the fix in the same paragraph that
documents the problem.

## Transiting a host and operating on it are different problems

Two things get called "I need to SSH through this box" and they have different
answers.

The first is transiting. You want to reach a machine that is only routable from a
bastion, and the bastion itself is scenery. Nothing you care about runs there.

The second is operating on the host. You want to run `git clone` on it, or drive
Ansible from it, using your credentials on their CPU. That means handing your key
material's usage to a machine you do not control.

Transiting is solved completely by `-J`. Operating on the host is not solvable by
any key mechanism, because you are running on their computer. They can read your
files, log your keystrokes, and interfere with anything you launch from that shell.
Every mitigation later in this post narrows what a hostile host can do with your
agent, and none of them touch that.

The habit worth building is asking which of the two you are doing before you type
`-A`. Most of the time the honest answer is the first one.

## What ProxyJump rests on

`ssh -J bastion target`, or `ProxyJump bastion` in `ssh_config`. Under the hood ssh
builds a `ProxyCommand` of the shape `ssh -W '[%h]:%p' bastion`, so both ssh
processes run on my laptop and the bastion only ever sees a TCP forward.

That gives two properties, and neither of them is new machinery:

- Key exchange and authentication with the target run end to end from my laptop, so
  the bastion relays ciphertext it cannot read or inject into.
- My laptop verifies the target's host key against my own `known_hosts` at the far
  end of the tunnel, so a bastion that tries to sit in the middle fails the check.
  The bastion's own key is verified locally too, by the first ssh process.

Nothing is placed on the bastion, so there is nothing on it to abuse. No socket, no
signing oracle, no keys.

```
Host bastion
  HostName bastion.example.com
  User me

Host app-*
  ProxyJump bastion
  ForwardAgent no
```

Chained hops work the same way with `ssh -J first,second target`, each one relaying
for the next.

## If you have to forward anyway

Sometimes the work genuinely runs on the remote host. In rough order of value:

- **Destination constraints.** `ssh-add -h bastion -h "bastion>git.internal" key`
  binds the key so the agent refuses to sign for anything but the named path. This
  is the strongest option short of not forwarding. It wants OpenSSH 8.9 or newer at
  the agent and at every hop, a recent sshd at the destination, and every host you
  name already present in `known_hosts` when you run `ssh-add`. I go through what
  the agent does and does not enforce in
  [the follow-up](/p/ssh-agent-enforces-the-session-bind-chain-only-for-constrained-keys/).
- **Touch per use.** A FIDO2 `sk-` key or a Secure Enclave key makes every
  signature need a physical tap, so silent background use fails and an unexpected
  prompt is your cue to refuse. It is defence in depth, and prompt fatigue defeats
  it.
- **Short-lived credentials.** `ssh-add -t 30`, or short-TTL certificates from a CA
  scoped to a principal and a host. A captured signature is useless outside its
  window.

Worth checking while you are in there: `ForwardAgent yes` under `Host *` is how most
people end up forwarding to machines they never thought about.

## Summary

- Agent forwarding puts a socket on the remote host that signs on demand, and root
  on that host can use it without your shell, your terminal, or your knowledge.
- The exposure lasts as long as the session, which is long enough.
- If you are only passing through a box, `-J` removes the entire problem, because
  authentication runs end to end from your laptop and the jump host relays
  ciphertext.
- If you are running work on the box, no key mechanism saves you. Constrain the key,
  require a touch, and keep the credential short-lived, but be honest that you are
  on their computer.
