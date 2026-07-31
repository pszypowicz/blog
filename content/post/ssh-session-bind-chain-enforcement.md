+++
title       = "ssh-agent enforces the session-bind chain only for constrained keys"
date        = "2026-07-31T12:05:00+02:00"
description = "session-bind@openssh.com binds each agent connection to the SSH session it serves, and a forwarded connection accumulates one binding per hop. The agent verifies every binding it records, then consults the chain only for keys added with destination constraints."
tags        = ["ssh", "openssh", "session-bind", "security"]
categories  = ["security"]
ai_assisted = true
+++

OpenSSH 8.9 added a way to tell the agent where a signature is going. Every ssh
client sends a `session-bind@openssh.com` message on the agent connection it opens,
naming the host it is talking to, and a forwarded connection collects one of these
per hop. It is the mechanism behind the destination constraints I recommended at the
end of
[the post on what agent forwarding exposes](/p/agent-forwarding-leaves-a-signing-oracle-on-every-host-you-land-on/),
and I built per-destination approval on top of the same chain, which meant reading
carefully what the agent does with it.

The chain is recorded for every key. It is consulted for keys that were added with
destination constraints, and for nothing else.

<svg id="fb" viewBox="0 0 520 148" width="520" height="148" role="img" aria-labelledby="fb-t fb-d" xmlns="http://www.w3.org/2000/svg">
<title id="fb-t">A binding accumulating at each forwarding hop</title>
<desc id="fb-d">As an agent request travels from the laptop through hop1 and hop2 to the target, each hop's ssh client adds one session binding, so the deepest request carries the whole ordered route.</desc>
<style>
#fb text{font-family:var(--mono-stack,ui-monospace,monospace);font-size:12px;fill:var(--ink,#222)}
#fb .b{fill:none;stroke:var(--rule,#999);stroke-width:1.5}
#fb .w{stroke:var(--rule,#999);stroke-width:1.5}
#fb .k{fill:var(--accent,#b44212)}
#fb .r{font-size:11px;opacity:0;animation:fbr 8s linear infinite backwards}
#fb .r2{animation-delay:2.4s}
#fb .r3{animation-delay:4.5s}
#fb .r4{animation-delay:6.6s}
#fb .m{animation:fbm 8s linear infinite}
@keyframes fbm{0%{transform:translateX(0);opacity:0}4%,18%{transform:translateX(0);opacity:1}30%,44%{transform:translateX(144px);opacity:1}56%,70%{transform:translateX(288px);opacity:1}82%,94%{transform:translateX(344px);opacity:1}100%{transform:translateX(344px);opacity:0}}
@keyframes fbr{0%,2%{opacity:0}7%,100%{opacity:1}}
@media (prefers-reduced-motion:reduce){#fb .m{animation:none}#fb .r{animation:none;opacity:1}}
</style>
<rect class="b" x="0" y="16" width="88" height="30" rx="3"/>
<rect class="b" x="144" y="16" width="88" height="30" rx="3"/>
<rect class="b" x="288" y="16" width="88" height="30" rx="3"/>
<rect class="b" x="432" y="16" width="88" height="30" rx="3"/>
<text x="44" y="62" text-anchor="middle">laptop</text>
<text x="188" y="62" text-anchor="middle">hop1</text>
<text x="332" y="62" text-anchor="middle">hop2</text>
<text x="476" y="62" text-anchor="middle">target</text>
<line class="w" x1="88" y1="31" x2="144" y2="31"/>
<line class="w" x1="232" y1="31" x2="288" y2="31"/>
<line class="w" x1="376" y1="31" x2="432" y2="31"/>
<g class="m"><circle class="k" cx="100" cy="31" r="3.5"/></g>
<text class="r r2" x="0" y="92">1  hop1    is_forwarding = true</text>
<text class="r r3" x="0" y="110">2  hop2    is_forwarding = true</text>
<text class="r r4" x="0" y="128">3  target  is_forwarding = false</text>
</svg>

## What the client sends on every agent connection

The message is documented in `PROTOCOL.agent`:

```text
byte    SSH_AGENTC_EXTENSION (0x1b)
string  session-bind@openssh.com
string  hostkey
string  session identifier
string  signature
bool    is_forwarding
```

The signature is the server's own, taken over the exchange hash in the final message
of key exchange and replayed to the agent afterwards. That is how an ssh client
manages to produce a binding for a host whose private key it obviously does not
have.

Both places that send it do so unconditionally. `sshconnect2.c` binds with
`is_forwarding` false before asking the agent for identities, and `clientloop.c`
binds with it true when the server opens a forwarded agent channel. Neither asks
the agent whether it supports the extension first, and neither treats a failure
reply as fatal, so an agent that has never heard of session-bind still works for
ordinary keys.

## The chain accumulates one binding per hop

I ran this against four Alpine containers, hopping `hop1` through `hop4` with `-A`
at every step. All four were reached, and the deepest signature request carried the
full route in order:

```text
chain SHA256:J06Lk+z... > SHA256:rlJZ+Lx... > SHA256:z9mRrd... > SHA256:XlJsTi...
```

The ordering holds because of when the binding is sent, which OpenSSH describes in
its [agent restriction notes](https://www.openssh.com/agent-restrict.html):

> each SSH client will issue a binding request as soon as it has received
> confirmation of a successfully opened channel, and before it passes the channel on
> to the next hop.

One lab detail cost me an afternoon. My first image generated the host key at build
time, so all four containers shared one identity and the chain came back as the
same fingerprint repeated four times. Generate host keys in the entrypoint, not the
`Dockerfile`, or you are testing nothing.

## The agent verifies every binding it records

`process_ext_session_bind()` in `ssh-agent.c` checks the signature against the host
key before storing anything:

```c
/* check signature with hostkey on session ID */
if ((r = sshkey_verify(key, sshbuf_ptr(sig), sshbuf_len(sig),
    sshbuf_ptr(sid), sshbuf_len(sid), NULL, 0, NULL)) != 0) {
        error_fr(r, "sshkey_verify for %s %s", sshkey_type(key), fp);
        goto out;
}
```

A failure drops the binding and returns `SSH_AGENT_EXTENSION_FAILURE` without
killing the connection, and it leaves a mark. The agent sets a flag the moment a
bind is attempted, and any later request for a destination-constrained key on that
same socket is refused outright with `previous session bind failed on socket`. One
bad binding poisons the connection for constrained keys. It also rejects a session
ID already recorded against a different host key, and any binding that arrives after
the connection has been bound for authentication. The exact same binding sent twice
is accepted as a no-op.

## What the chain is consulted for

Here is the part that surprised me. `identity_permitted()` returns success
immediately when the key carries no destination constraints, so the recorded chain
is never examined:

| key added with        | chain recorded | chain checked before signing |
| --------------------- | -------------- | ---------------------------- |
| `ssh-add key`         | yes            | no                           |
| `ssh-add -h host key` | yes            | yes                          |

For a plain key, session-bind is bookkeeping that nothing acts on. Everything
written about per-hop policy only becomes true once the key is constrained, or once
some other agent decides to act on the chain itself.

## What ssh-add -h needs before it works

`ssh-add(1)` is direct about the model:

> When attempting authentication with a key that has destination constraints, the
> whole connection path, including ssh-agent(1) forwarding, is tested against those
> constraints and each hop must be permitted for the attempt to succeed.

```bash
# each hop, then the final destination reached through it
ssh-add -h bastion.example.com \
        -h "bastion.example.com>git.internal" \
        ~/.ssh/id_ed25519
```

The requirements are spread across the manual and easy to trip over:

- OpenSSH 8.9 or newer for the agent and for the client that adds the key.
- Every host named must already be in `known_hosts` when `ssh-add` runs, because
  hosts are identified by their host keys and looked up at that moment. Wildcards
  and CA-signed host certificates work.
- Each hop needs a cooperating client to extend the chain, and the destination needs
  an sshd new enough for host-bound authentication. The manual says support in both
  the remote client and server is required over a forwarded channel.

And the limit, stated in the same page: constraints do not stop an attacker with
access to a remote `SSH_AUTH_SOCK` from forwarding it onward and using it, as long
as they use it toward a destination you permitted.

## The replay caveat OpenSSH documents

Bindings carry no freshness. A hostile hop can replay ones it has seen, which
OpenSSH covers explicitly:

> This attack allows a malicious hop to make the forwarding path appear longer than
> it actually is. In all cases however, the final destination cannot be forged
> because of the binding between the signature and the server hostkey.

That guarantee is worth exactly as much as the agent's willingness to check the
signature, which is the subject of the next post.

## Summary

- Every ssh client binds its agent connection to the host it is talking to, and a
  forwarded chain accumulates one binding per hop, in order.
- The agent verifies the host signature in each binding, and a single failed bind
  disables constrained keys on that connection for good.
- The chain is recorded for all keys and checked only for keys added with
  `ssh-add -h`. Without constraints it changes nothing about what gets signed.
- Destination constraints need 8.9 or newer at the agent, a cooperating client at
  each hop, a recent sshd at the destination, and every named host in `known_hosts`
  when you add the key.
