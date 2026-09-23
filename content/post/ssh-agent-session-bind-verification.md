+++
title       = "The session-bind signature check I skipped in my own SSH agent"
date        = "2026-09-23T12:00:00+02:00"
description = "For one afternoon my Secure Enclave SSH agent built per-destination approval on session-bind chains without verifying the host signature in each binding. A test from a hostile first hop showed what that allows, and what an agent still cannot catch after the check is in place."
tags        = ["ssh", "secure-enclave", "macos", "security"]
categories  = ["security"]
ai_assisted = true
draft       = true
+++

I build [Sequester](https://github.com/pszypowicz/sequester), a macOS SSH agent that
keeps keys in the Secure Enclave and asks before it signs. Talking to the enclave
turned out to be the easy half. The hard half is deciding what the prompt should
say, because "something wants to sign with your key" is a question nobody can answer
usefully.

`session-bind@openssh.com` looked like the answer. Every hop's ssh client tells the
agent which host it is talking to, so a forwarded request arrives with its whole
route and the prompt can name the destination. On the first day I built approval on
top of that chain, and I did it without the one check that makes the chain mean
anything. The check landed about three hours later, before the first release. This
post is about what a hostile host could do in those three hours, and about what it
can still do now.

## Why a custom agent builds on the chain at all

OpenSSH's agent consults the recorded chain only for keys added with destination
constraints, which I went through in
[the previous post](/p/ssh-agent-enforces-the-session-bind-chain-only-for-constrained-keys/).
For an ordinary key the chain is recorded and never looked at.

That gap is the reason to write an agent. The information arrives with every
request, so an agent can prompt with the route, remember an approval for it, and
stay quiet the next time the same route comes back. Constraints have to be declared
up front with `ssh-add -h`, and a prompt can be answered by whoever is at the
keyboard when the request arrives.

## The check I left out

`PROTOCOL.agent` says the agent verifies the signature and checks the consistency of
the message contents. OpenSSH's own agent does exactly that in
`process_ext_session_bind()`, before it stores anything.

My first version parsed the binding, pulled out the host key, computed its
fingerprint, appended it to the chain, and moved on. It read the signature field and
ignored it. Every other part of the design assumed that the chain described what
really happened.

## What a hostile first hop did with that

I tested it that afternoon in a lab of Alpine containers. I authenticated from my
laptop to `hop1` with a throwaway file-based key, so that setting up the session did
not involve the agent under test, and forwarded the agent. Then I ran a script on
`hop1` that speaks the agent protocol directly to the forwarded socket and sends
whatever bindings it likes.

<svg id="fc" viewBox="0 0 520 148" width="520" height="148" role="img" aria-labelledby="fc-t fc-d" xmlns="http://www.w3.org/2000/svg">
<title id="fc-t">A first hop fabricating the rest of the route</title>
<desc id="fc-d">The binding for hop1 is genuine and comes from my own ssh client. The bindings for hop2 and the target are fabricated by hop1, which never connected to either host.</desc>
<style>
#fc text{font-family:var(--mono-stack,ui-monospace,monospace);font-size:12px;fill:var(--ink,#222)}
#fc .b{fill:none;stroke:var(--rule,#999);stroke-width:1.5}
#fc .w{stroke:var(--rule,#999);stroke-width:1.5}
#fc .d{opacity:.35}
#fc .f{fill:var(--accent,#b44212)}
#fc text.r{font-size:11px}
#fc .g1{opacity:0;animation:fcg 8s linear infinite backwards;animation-delay:1.2s}
#fc .g2,#fc .g3{opacity:0;animation:fcf 8s linear infinite backwards}
#fc .g2{animation-delay:2.6s}
#fc .g3{animation-delay:4s}
@keyframes fcg{0%,2%{opacity:0}8%,100%{opacity:1}}
@keyframes fcf{0%{opacity:0;transform:translateX(-150px)}14%,100%{opacity:1;transform:translateX(0)}}
@media (prefers-reduced-motion:reduce){#fc .g1,#fc .g2,#fc .g3{animation:none;opacity:1;transform:none}}
</style>
<rect class="b" x="0" y="16" width="88" height="30" rx="3"/>
<rect class="b" x="144" y="16" width="88" height="30" rx="3"/>
<rect class="b d" x="288" y="16" width="88" height="30" rx="3" stroke-dasharray="4 4"/>
<rect class="b d" x="432" y="16" width="88" height="30" rx="3" stroke-dasharray="4 4"/>
<text x="44" y="62" text-anchor="middle">laptop</text>
<text x="188" y="62" text-anchor="middle">hop1</text>
<text class="d" x="332" y="62" text-anchor="middle">hop2</text>
<text class="d" x="476" y="62" text-anchor="middle">target</text>
<line class="w" x1="88" y1="31" x2="144" y2="31"/>
<line class="w d" x1="232" y1="31" x2="288" y2="31" stroke-dasharray="4 4"/>
<line class="w d" x1="376" y1="31" x2="432" y2="31" stroke-dasharray="4 4"/>
<g class="g1"><text class="r" x="0" y="92">1  hop1    forwarding = true    genuine, from my ssh</text></g>
<g class="g2"><text class="r f" x="0" y="110">2  hop2    forwarding = true    forged on hop1</text></g>
<g class="g3"><text class="r f" x="0" y="128">3  target  forwarding = false   forged on hop1</text></g>
</svg>

The script bound two hosts I never connected to in that run, and the agent accepted
both. This is the agent log from my notes, trimmed, with the hop names added:

```text
Session bound to SHA256:J06Lk+z... (hop1)    forwarding true    <- genuine
Session bound to SHA256:rlJZ+Lx... (hop2)    forwarding true    <- forged
Session bound to SHA256:z9mRrd... (hop3)     forwarding false   <- forged
Sign request: chain hop1 > hop2 > hop3, decision ask
```

Three things came out of it, and only the first one was my bug.

The forgery works because a host public key is public. It goes past in cleartext
during every handshake and it sits in the intermediate host's `known_hosts`, so a
fabricated binding carries the real fingerprint of the host it claims to be. A
fingerprint has no per-session randomness, so comparing fingerprints can never
detect this, and that comparison was all my agent did. The signature over the
session identifier is the only field a host cannot produce for someone else, and it
was the field I threw away.

The genuine first binding cannot be removed. OpenSSH's client on my laptop sends it
before it hands the channel to the remote side, so every request that comes out of a
forwarded socket is stamped as forwarded through that host, whatever the attacker
appends afterwards. I confirmed this by having the script present a single
non-forwarding hop, and `hop1, forwarding=true` still arrived first. A request from
a forwarded agent cannot be made to look local.

It was not a silent bypass in that configuration. The forged chain matched no
remembered approval, so the policy came out as `ask` and a human had to allow the
dialog. The signature happened because someone said yes to a prompt that named a
route that did not exist.

## What the agent checks now

The fix verifies the signature in each binding against the host key it carries, and
rejects the binding if the check fails. A binding that carries the real host key of
`hop2` with a signature from some other key now gets `SSH_AGENT_FAILURE` back, and
this line in the log:

```text
Rejected session-bind with an invalid signature for SHA256:J6DItnJex4LiGr7f5FU4hEoo+gkc/f13GhvCr0OwS04, requester "python3.13" (unverified)
```

Two smaller checks landed before the first release. The chain is capped at 32
bindings, because the policy scans it on every signature and a client could
otherwise append host keys it controls without limit. And a silent signature needs
the session identifier inside the data being signed to match the last binding in
the chain. OpenSSH applies the same rule to constrained keys. Without it, a verified binding for one session could
approve a signature meant for a different session. When the identifiers do not
match, the agent asks instead of signing silently.

## Approval models and why they must not compose

Once you prompt and remember answers, you have to decide what a remembered answer
covers. There are three models, in increasing order of how well they survive a
hostile first hop.

Approving a destination means "github is fine, whatever the path". A hostile
intermediate then reaches github from its own session with no prompt at all. This is
the worst of the three and also the most tempting, because it matches how people
describe what they want.

Approving edges means "`vm1 to vm2` is fine, and `vm2 to github` is fine". A hostile
`vm1` can then fabricate the chain `[vm1, vm2, github]`, both edges are approved,
the policy composes them, and the agent signs silently in `vm1`'s own session. A
human approved every edge, but never the route as a whole.

Approving the exact full chain is what I settled on. `[vm1, vm2, github]` is a
different record from `[vm1, vm2]` and from `[vm2, github]`, so approvals do not
compose and only a route you actually approved replays without a prompt.

Sequester also lets you set a standing on a hop, which then covers every chain
through that hop. It is most useful for blocking. Approving a hop is a deliberate
decision to trust that host with the key for anything it asks, which is the
destination model again, limited to one branch. Keys that need Touch ID can
remember a tap for a short window, but the agent never opens a window for a request
that arrived through a forwarding hop. There the tap is the last human check.

## What full-chain matching still cannot stop

Exact matching stops composition, but it does not stop replay. Bindings carry no
freshness, so a hop can resend genuine bindings it saw earlier and make the path
look longer than it is. The destination is the one part it cannot fake, because the
last binding has to match the session that is really being authenticated. So a
hostile `vm1` can reproduce any approved chain that starts with `vm1` and ends at a
host it can really reach.

Then there is the case no agent can catch. A host with your socket does not have to
lie. It opens a real connection to a real second host and a real destination, with
real host keys, real session identifiers and real signatures at every step. The
chain is completely honest. It describes a route that exists, that you never asked
for, in a session you know nothing about, and there is nothing forged for the agent
to detect.

That is the limit of what an agent can do. An enclave-backed agent cannot make agent
forwarding safe. It can verify what it is told, refuse to compose approvals, put the
real route in front of a human, and make the
[ProxyJump path](/p/agent-forwarding-leaves-a-signing-oracle-on-every-host-you-land-on/)
the obvious one to take.

## Summary

- Comparing host fingerprints in a session-bind chain proves nothing, because host
  public keys are public and a forged binding carries the genuine fingerprint.
- The signature over the session identifier is the only unforgeable field, so an
  agent that skips verifying it will believe any route a hostile hop invents.
- The first binding in a forwarded chain is written by your own client and cannot be
  stripped, so a forwarded request can never disguise itself as a local one.
- Approvals must match the whole chain. Approving destinations or individual edges
  lets a hostile first hop assemble a route nobody approved.
- Even with verification and exact matching, a host that holds your socket can make
  genuine connections you never asked for, so no prompt design makes forwarding into
  an untrusted host safe.
