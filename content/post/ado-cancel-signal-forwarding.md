+++
title       = "In Azure DevOps, only `Bash@3` forwards SIGINT to your script"
date        = "2026-04-20T12:00:00+02:00"
description = "Cancel an Azure DevOps pipeline mid-terraform-apply and your state lock survives. Most built-in tasks hard-kill their child shell instead of forwarding SIGINT. Bash@3 is the exception."
tags        = ["azure-devops", "terraform", "signals"]
categories  = ["devops"]
ai_assisted = true
aliases     = ["/p/terraform-under-azurecli@2-never-sees-your-cancel/"]
+++

If you cancel an Azure DevOps pipeline mid-`terraform apply`, or let it hit `timeoutInMinutes`, you probably expect terraform to catch SIGINT, release its state lock, and exit cleanly. Under `AzureCLI@2` that does not happen. Terraform is killed without ever seeing a signal, and the lock stays behind.

The cause is not terraform, not the agent's signal-timeout knobs, and not anything documented in the cancel-related env vars. It is that `AzureCLI@2` does not forward signals to the bash child it spawns. `Bash@3` does.

## What I measured

The Azure Pipelines agent applies a signal ladder on cancel: SIGINT, wait `PROCESS_SIGINT_TIMEOUT` ms (default 7500), SIGTERM, wait `PROCESS_SIGTERM_TIMEOUT` ms (default 2500), SIGKILL. Straightforward on paper.

For each task, I ran a probe on `ubuntu-latest`: a small bash script that traps SIGINT/SIGTERM/SIGHUP and writes ms-precise ticks. Knobs set to `PROCESS_SIGINT_TIMEOUT=30000`, `PROCESS_SIGTERM_TIMEOUT=5000` so any forwarding would be obvious. Cancel mid-flight, watch the log.

| Task                              | trap fires? | observed                                                            |
| --------------------------------- | ----------- | ------------------------------------------------------------------- |
| `Bash@3`                          | yes         | SIGINT trap, SIGTERM trap at `PROCESS_SIGINT_TIMEOUT`, then SIGKILL |
| `AzureCLI@2` (`scriptType: bash`) | no          | process killed before any trap could fire                           |

`Bash@3` honoured both configured timeouts precisely. Under `AzureCLI@2` no trap ever fired - the bash child was killed before the SIGINT window even started counting down.

Same outcome with a real `terraform apply`: under `Bash@3`, terraform's `Interrupt received. / Gracefully shutting down...` log line shows up within milliseconds of the cancel. Under `AzureCLI@2` that line never appears - terraform is killed mid-apply with the lock still held.

## Why

The built-in tasks all run under a Node-based task host on the agent. Whether the inner script sees a signal on cancel depends on whether the task explicitly forwards SIGINT to the child it spawned. `Bash@3` does. `AzureCLI@2` does not. The cancel ladder lands on the task host, the host exits, and the inner shell is torn down by the kernel cascade with no trap-visible signal.

So `PROCESS_SIGINT_TIMEOUT` and `PROCESS_SIGTERM_TIMEOUT` do exactly what they advertise: they tune the ladder applied to the task host. Anything running under a non-forwarding task lives one process further down and never learns anything is wrong until it is already gone.

## Fix

Run terraform under `Bash@3`.

```yaml
jobs:
  - job: terraform_apply
    timeoutInMinutes: 60
    # 5 min = 300 s, must cover the 60 s PROCESS_SIGINT_TIMEOUT below.
    # If you bump SIGINT, bump this too, or the cap truncates the SIGINT window.
    cancelTimeoutInMinutes: 5
    variables:
      # Job-scope: the agent reads these once at task start.
      # Step-level env: is injected too late and gets ignored.
      # Bump SIGINT so terraform can release its state lock
      # before the agent escalates to SIGTERM/SIGKILL.
      PROCESS_SIGINT_TIMEOUT: 60000
      PROCESS_SIGTERM_TIMEOUT: 5000
    steps:
      - task: Bash@3
        displayName: terraform apply
        inputs:
          targetType: inline
          script: |
            set -euo pipefail
            # exec replaces bash with terraform so SIGINT
            # lands directly on terraform, no intermediate shell.
            exec terraform apply -auto-approve
```

After the swap, terraform sees SIGINT within milliseconds of the cancel, prints its shutdown banner, releases the lock, and exits.

For terraform specifically, only `PROCESS_SIGINT_TIMEOUT` actually controls the cleanup window. terraform handles SIGTERM identically to SIGINT (both trigger the same graceful-shutdown path), so it either finishes inside the SIGINT window or dies fast once SIGTERM lands. `PROCESS_SIGTERM_TIMEOUT` is effectively a no-op here - tune SIGINT to cover your worst-case lock release.

Whatever you set `PROCESS_SIGINT_TIMEOUT` to, make sure `cancelTimeoutInMinutes` covers it. Otherwise the per-job cap fires first, SIGKILLs the task host, and your SIGINT window is silently truncated.

## Things that sound like they should help, but don't

- **`USE_GRACEFUL_PROCESS_SHUTDOWN=true`**: only skips the SIGTERM stage of the agent's ladder. Under a non-forwarding task it still never reaches the inner script. Under `Bash@3` it just collapses the ladder to SIGINT-then-SIGKILL at `PROCESS_SIGINT_TIMEOUT`, no middle step.
- **`exec` to collapse the process tree**: useful under `Bash@3` (one fewer hop for SIGINT to traverse). Does not rescue a non-forwarding task; the gap is above bash, not below.
- **Step-level `env:` for the knobs**: ignored. The agent reads them once at task start from variable scope, not from the per-step env that gets injected afterwards. Use job- or pipeline-scope `variables:`.

## Summary

- `AzureCLI@2` does not forward SIGINT to its bash child; `Bash@3` does. Use `Bash@3` for anything that needs to trap the cancel: terraform, long-running scripts, anything with cleanup.
- Use job- or pipeline-scope `variables:` for `PROCESS_SIGINT_TIMEOUT` and `PROCESS_SIGTERM_TIMEOUT`. Step-`env:` will not take.
