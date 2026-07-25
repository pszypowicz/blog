+++
title       = "Which Azure DevOps tasks forward SIGINT when you cancel a pipeline"
date        = "2026-04-20T12:00:00+02:00"
description = "Cancelling an Azure DevOps pipeline mid-terraform-apply leaves the state lock stuck under AzureCLI@2, because the task kills its child shell without forwarding any signal. Bash@3 and CmdLine@2 forward SIGINT and let terraform shut down cleanly."
tags        = ["azure-devops", "terraform", "signals"]
categories  = ["devops"]
ai_assisted = true
aliases     = ["/p/terraform-under-azurecli@2-never-sees-your-cancel/"]
+++

If you cancel an Azure DevOps pipeline mid-`terraform apply`, or let it hit `timeoutInMinutes`, you probably expect terraform to catch SIGINT, release its state lock, and exit cleanly. Whether that happens depends on the task your script runs under. Under `Bash@3` or a plain `script:` step terraform gets the signal and shuts down cleanly. Under `AzureCLI@2` it is killed without ever seeing a signal, and the lock stays behind.

None of this is terraform's doing. The agent cancels every task the same way, but only some tasks pass the signal on to the shell they spawned.

## The ladder and the knobs

The Azure Pipelines agent applies a signal ladder on cancel: SIGINT, then SIGTERM, then SIGKILL. How long it waits between the rungs is set by two agent variables, `PROCESS_SIGINT_TIMEOUT` (default 7500 ms) and `PROCESS_SIGTERM_TIMEOUT` (default 2500 ms). The agent's own codebase calls its tunables knobs (both of these live in `AgentKnobs.cs` alongside every other agent setting), so knobs is what I will call them here. Straightforward on paper.

The knobs are newer than the ladder itself, and finding that out was half the journey. The two waits were hardcoded at those defaults until agent v3.239.1 (May 2024), when [azure-pipelines-agent#4744](https://github.com/microsoft/azure-pipelines-agent/pull/4744) made them settable through a pipeline variable or an environment variable (`USE_GRACEFUL_PROCESS_SHUTDOWN` arrived in the same change). Microsoft-hosted agents are always current, but on a self-hosted pool that lags behind, no variable changes the timings and 7.5 s of SIGINT time is all a cancelled script gets.

The defaults are tight for anything real. A cancelled `terraform apply` has to finish the resource operation it is in the middle of and then release the state lock, and 7.5 s is rarely enough for that on Azure, where a single operation can run for minutes. When the SIGTERM rung lands, terraform treats it as a second interrupt and gives up immediately, so the graceful window is the SIGINT wait and nothing more. That is what the knobs are for: raise `PROCESS_SIGINT_TIMEOUT` until it covers the longest shutdown you are willing to wait out.

## What I measured

For each task I ran a probe on `ubuntu-latest`: a small bash script that traps SIGINT/SIGTERM/SIGHUP and writes ms-precise ticks, with the knobs raised to `PROCESS_SIGINT_TIMEOUT=30000` and `PROCESS_SIGTERM_TIMEOUT=5000` so any forwarding would be obvious in the log. Then I cancelled each run mid-flight and read the trap lines.

| Task                                | trap fires? | observed                                                              |
| ----------------------------------- | ----------- | --------------------------------------------------------------------- |
| `Bash@3`                            | yes         | SIGINT, SIGTERM 30.002 s later, SIGKILL 5.01 s after that             |
| `CmdLine@2` (a bare `script:` step) | yes         | same as `Bash@3`: SIGTERM at +30.001 s, SIGKILL +5.02 s               |
| `AzureCLI@2` (`scriptType: bash`)   | no          | killed about 1.5 s after the cancel, before the SIGINT window started |

The forwarding tasks honoured both configured timeouts to the millisecond. Under `AzureCLI@2` no trap ever fired, and the build finished within seconds of the cancel instead of waiting out the 35 s of configured signal windows, so the bash child was gone before the ladder even started counting.

Same outcome with a real `terraform apply`: under `Bash@3`, terraform's `Interrupt received. / Gracefully shutting down...` log line shows up within milliseconds of the cancel. Under `AzureCLI@2` that line never appears, and terraform is killed mid-apply with the lock still held.

## Root cause

The built-in tasks all run under a Node-based task host on the agent, and the cancel ladder is applied to that host. Whether your script sees anything depends on whether the task explicitly forwards SIGINT to the child it spawned. The script-runner tasks I tested (`Bash@3`, `CmdLine@2`) forward it. `AzureCLI@2` does not, so the host exits and the inner shell is torn down by the kernel cascade without any trap-visible signal.

`PROCESS_SIGINT_TIMEOUT` and `PROCESS_SIGTERM_TIMEOUT` do exactly what they advertise, but they tune the ladder applied to the task host. A script under a non-forwarding task lives one process further down and never learns anything is wrong until it is already gone.

I probed exactly these three tasks. If your long-running work sits under a different wrapper (`AzurePowerShell@5`, a marketplace task), run the same probe against it before you rely on a graceful cancel.

## Fix

Run terraform under `Bash@3`, or under a plain `script:` step, which behaves the same.

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

If `AzureCLI@2` was there for the automatic `az login`, that still has to happen somewhere. Doing it yourself at the top of the script is a few lines of `az login --service-principal` with the service connection values read from pipeline variables, and it is the only thing the task was doing for you under the hood.

For terraform specifically, only `PROCESS_SIGINT_TIMEOUT` controls the cleanup window. terraform handles SIGTERM the same way as SIGINT (both trigger the same graceful-shutdown path), so it either finishes inside the SIGINT window or dies quickly once SIGTERM lands. Tune SIGINT to cover your worst-case lock release and leave SIGTERM alone.

Whatever you set `PROCESS_SIGINT_TIMEOUT` to, make sure `cancelTimeoutInMinutes` covers it. Otherwise the per-job cap fires first, SIGKILLs the task host, and your SIGINT window is silently truncated.

## Things that sound like they should help, but don't

- **`USE_GRACEFUL_PROCESS_SHUTDOWN=true`**: only skips the SIGTERM stage of the agent's ladder. Under a non-forwarding task it still never reaches the inner script, and under `Bash@3` it just collapses the ladder to SIGINT-then-SIGKILL at `PROCESS_SIGINT_TIMEOUT` with no middle step.
- **`exec` to collapse the process tree**: useful under a forwarding task, because SIGINT lands directly on terraform instead of on the shell. It does not rescue `AzureCLI@2`, where the forwarding already fails a level above bash.
- **Step-level `env:` for the knobs**: ignored. The agent reads them once at task start from variable scope, and the per-step env is injected too late. With the knobs set only in step `env:`, the measured trap gaps came out at the 7.5 s and 2.5 s defaults. Use job- or pipeline-scope `variables:`.

## Summary

- Whether a cancel is graceful depends on the task wrapping your script. `Bash@3` and `CmdLine@2` forward SIGINT to the child shell, and `AzureCLI@2` kills it without any signal. Run terraform, and anything else with cleanup to do, under a forwarding task.
- Use job- or pipeline-scope `variables:` for `PROCESS_SIGINT_TIMEOUT` and `PROCESS_SIGTERM_TIMEOUT`, and size `cancelTimeoutInMinutes` to cover the SIGINT window. Step-level `env:` will not take.
