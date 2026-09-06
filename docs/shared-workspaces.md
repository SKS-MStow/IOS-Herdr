# Shared workspaces

Desktop source: https://github.com/SKS-MStow/Herdr-Shared (private).

The Mac owns `~/.config/herdr-shared/shared-workspaces/shared.json`. The iPhone
bridge calls the private Herdr `shared-workspace list` / `apply` CLI. The new
optional `sharedWorkspaceCatalog` snapshot field preserves older app decoding;
an unavailable or stale catalog disables group editing and keeps All agents
accessible. Existing `/api/workspaces` still creates a machine-local execution
workspace.

A member is `{machineId, session, terminalId}`. The Mac uses `mac`; remote workers
use saved opaque profile IDs. Ended or offline references remain in the group
and can be removed. A reused pane cannot inherit membership.

Create, rename, delete, add and remove use `/api/shared-workspaces/change` with
`requestId` and `expectedRevision`. Rust serializes writers using an OS lock,
atomically replaces the catalog and saves receipts. The bridge can recover the
same metadata mutation after uncertain delivery. It never replays an agent
start, prompt or key input. The phone retains pending metadata requests across
restarts and cooldowns. Definitive input/conflict rejection permits correction.

Starting an agent from a shared workspace saves each completed step before
continuing. After an agent has started, recovery only attaches that terminal to
the group. Machine/path controls stay fixed, while a rejected start still allows
correction of agent name/provider. A missing started terminal asks for reconnection
and does not trigger another start.

Desktop selection validates terminal identity from the existing pane-focus
acknowledgment before exposing the surface or accepting input. After a connection
loss while using a shared row, select the live agent again. Automatic unqualified
pane restoration cannot bypass that identity check. Worker protocols are unchanged,
so the existing Home PC worker can remain running.

## Verification

The regression suite covers mixed-machine membership, revision conflicts,
persisted receipts, interrupted metadata recovery, stale reads arriving late,
terminal reuse, machine/session qualification, descendant cleanup on discovery
timeouts, and stale/unavailable desktop states. Native UI tests create a group,
add agents from both demo machines, remove a member and open a terminal. Demo
screens are explicitly labeled, including at the largest accessibility text size.

Build 3 is the workspace candidate. Its publication status belongs in
`release-status.json`; a candidate or screenshot is not a TestFlight release.
