+++
title       = "Terraform under AzureCLI@2 never sees your cancel"
date        = "2026-04-20T12:00:00+02:00"
description = "Cancelling an Azure DevOps pipeline mid-terraform-apply leaves terraform no time to shut down or release its state lock. The fix is the task handler, not the signal knobs."
tags        = ["azure-devops", "terraform", "signals"]
categories  = ["devops"]
ai_assisted = true
+++

If you cancel an Azure DevOps pipeline mid-`terraform apply`, or let it hit its `timeoutInMinutes`, you probably expect terraform to catch SIGINT, release its state lock, and exit cleanly. Under `AzureCLI@2` that does not happen. Terraform is SIGKILLed without ever seeing a signal, and the state lock stays behind.

## What I measured

The Azure Pipelines agent applies a signal ladder on cancel: SIGINT, wait `PROCESS_SIGINT_TIMEOUT` ms (default 7500), SIGTERM, wait `PROCESS_SIGTERM_TIMEOUT` ms (default 2500), SIGKILL. Straightforward on paper.

I ran a matrix of probe jobs, each a small bash script trapping SIGINT and SIGTERM and writing millisecond-precise ticks, then cancelled the build mid-flight. Results:

- **`Bash@3`**: SIGINT arrives at the script within ~10 ms of the cancel click. The knobs honour job-scope `variables:` exactly (configured 5000 ms, measured 5004 ms).
- **`AzureCLI@2`**: no signal reaches the bash child. The script dies a few hundred milliseconds after its last tick, without entering its trap.

I re-ran with a real `terraform apply` instead of a sleep loop, using terraform's own `Interrupt received. / Gracefully shutting down...` log line as the authoritative witness that SIGINT hit the process. Same result: `Bash@3` gets it, `AzureCLI@2` does not, regardless of `exec` versus wrapper, and regardless of `USE_GRACEFUL_PROCESS_SHUTDOWN`.

## Root cause

`AzureCLI@2` is a Node-based task. When the agent cancels it, the ladder is applied to the Node process - not to the bash child that Node spawns to run the inline script. Node does not forward SIGINT to its descendants. When Node goes, the bash subtree is torn down by the kernel cascade without any trap-visible signal.

So the knobs do exactly what they advertise. They just tune the Node side. Terraform lives two processes further down and never learns anything is wrong until it is already gone.

## Root fix

Run terraform under `Bash@3`. If you need the Azure credentials that `AzureCLI@2` sets up for free, do the `az login --service-principal` yourself at the top of the script, reading the service connection values from pipeline variables. That is the only thing `AzureCLI@2` really does for you under the hood; replicating it is a few lines.

After the swap, terraform sees SIGINT within milliseconds of the cancel, prints its shutdown banner, releases the lock, and exits. No state left dangling.

## Things that sound like they should help, but don't

- **`USE_GRACEFUL_PROCESS_SHUTDOWN=true`**: only skips the SIGTERM stage. Under `AzureCLI@2` it still never reaches bash. Under `Bash@3` it just means SIGINT-then-SIGKILL at `PROCESS_SIGINT_TIMEOUT` with no middle step.
- **`exec terraform apply` (collapse the process tree)**: does not save `AzureCLI@2`. The handoff happens above bash.
- **Step-level `env:` for the knobs**: ignored. The agent reads the knob once at task start from variable scope, not from the per-step env that gets injected afterwards. Use job- or pipeline-scope `variables:`.

## Bonus gotcha: `timeout(1)` inside the wrapper script

If your terraform wrapper does something like `timeout 50m terraform apply`, delete it. `timeout(1)` sends SIGTERM by default, and terraform does not gracefully shut down on SIGTERM - it hard-kills the local-exec subprocess and bails. You also lose ADO's `cancelTimeoutInMinutes` grace window.

ADO's own job timeout uses the same SIGINT ladder as user-Cancel, confirmed with the same probe: trap entry ~9 ms after the `Operation will be canceled` marker, SIGINT to SIGTERM gap matches `PROCESS_SIGINT_TIMEOUT` to the millisecond. Let ADO do the timing; keep `timeoutInMinutes` on the step and drop the internal wrapper.

## Summary

- Use job- or pipeline-scope `variables:` for `PROCESS_SIGINT_TIMEOUT` and `PROCESS_SIGTERM_TIMEOUT`. Step-`env:` will not take.
- `AzureCLI@2` does not forward SIGINT to bash. Use `Bash@3` for anything that needs to trap the cancel: terraform, long-running scripts, anything with cleanup.
- Do not wrap terraform in `timeout(1)`. ADO's native timeout is the same signal path as user-Cancel.
