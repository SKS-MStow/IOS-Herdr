# Herdr iOS design QA

## Build 3 candidate: shared workspaces

Workspaces is now the first native tab, with All agents, Unassigned and named
groups. Groups collect agents across machines using machine, session and terminal
identity. The compact two-line agent rows, graphite/mint palette and native
controls remain the design baseline. Group detail includes membership management
and a machine-specific Start an agent flow.

The finish reviewer requested updated navigation documentation and a demo label
that remains visible while scrolling. `DESIGN.md` now records the implemented
navigation. Workspaces, group detail and the membership picker prefix their
native navigation titles with “Demo ·”, keeping sample identity visible while
scrolling and at accessibility text sizes.

| Check | Candidate evidence |
| --- | --- |
| iOS regression tests | Eight unit tests and seven UI tests passed in `build/SharedWorkspaces-verified-3.xcresult`. One opt-in live-pairing test was skipped. |
| Demo-label follow-up | Three focused UI tests passed after the final native-title correction in `build/SharedWorkspaces-final-ui-3.xcresult`. |
| Desktop checks | Full `just check` passed, including 3,124 Rust tests and Windows lint/docs checks. |
| Final visual review | Independent reviewer: **ship**. Both material findings resolved; no remaining fixes. |

The verified result supersedes `build/SharedWorkspaces-final-3.xcresult`, which
included a failed accidental opt-in live-pairing run. The intermediate pinned
demo-label capture was superseded because content could cover it. The skipped live test is
not evidence of new pairing verification. Earlier build evidence below remains
historical and does not establish physical-device acceptance of build 3.

Live desktop QA created a temporary group, added/opened the Mac terminal,
removed an unavailable member and collapsed/expanded the sidebar. A separate
instance of the iPhone bridge saw the same group and its cross-machine members.
The first capture used an unavailable Home PC reference. On 7 September, a
temporary Home PC Claude agent returned a reply-only prompt. A group containing
that live Windows agent and an existing Mac agent appeared in the desktop and
bridge. Selecting the Windows member opened its matching terminal and displayed
the verified reply. The temporary group, worker execution workspace and bridge
pairing were removed. The current desktop capture records this live mixed-machine
check; existing agent terminal contents are omitted.

**Visual disposition: ship.** Build 3 publication and TestFlight availability
are verified separately in [the release record](docs/releases/0.1.0-3.json).
Physical installation of build 3 remains unconfirmed.

## Build 2: compact agent list

Mark’s physical-device feedback requested smaller agent badges and an easy list
to scan. This supersedes the original mockup’s tall agent rows while retaining
the graphite/mint palette and native navigation.

The bounded local review passed:

| Check | Result |
| --- | --- |
| Density | Eight sample agents fit on an iPhone 17 screen at default text size. |
| Row content | Name and inline status, then machine/provider/project. No large badge or separate Open session button. |
| Navigation | Whole-row targets open the intended session; Mac and Home PC filters work. |
| Stale state | Last known state stays visible, without live attention wording. |
| Long content | Names wrap; the full identity remains in the accessibility label and session. |
| Accessibility text | At the largest accessibility text size, status stacks below the name and metadata wraps. Decorative symbols are removed to prevent overlap. |

Evidence: [compact list](preview/native/agents.png), [stale rows](preview/native/stale.png),
[accessibility text](preview/native/accessibility.png). These are actual simulator
captures using labeled sample activity.

Five iOS unit tests and five UI tests passed in `build/CompactList-2.xcresult`.
After the accessibility overlap fix, three focused UI tests passed again in
`build/CompactList-final-2.xcresult`. Archive, export and signature checks passed.
No controller or input protocol changes were made. The prior live checks remain
recorded separately in [build 1 evidence](docs/releases/0.1.0-1.json).

This was a targeted refinement through Impeccable distill/polish, with two local
inspection rounds. No new independent-reviewer verdict is claimed for build 2.
A physical-device acceptance check of the new layout and a full VoiceOver/iPad
sweep remain outside this simulator verification.

## Build 1: earlier independent review

The original finish reviewer returned SHIP for its visual scope, with four
findings resolved: stale attention wording, the output-follow label, a visible
Inbox demo label, and restoring the Inbox title. The compact list above follows
Mark’s later feedback and is the current agent-screen design.

## Live operation and notifications

Mac and Home PC workspace creation, agent startup, prompt/reply and cleanup
passed. Native pairing and revocation passed. Apple distributed build 1 through
TestFlight; its tester state became INSTALLED. The iPhone paired and registered
for production APNs. Apple accepted the test alert, and Mark confirmed it
appeared on the phone.

See [release status](docs/release-status.json) for the current build’s Apple
processing, group assignment and verification timestamps. A newly available
TestFlight build is distinct from that version being installed on the phone.

## Session reading and photos (build 4)

Session output now uses body-size text with extra line spacing, optional
monospace and explicit Pause/Resume. The tab bar and normally hidden terminal
keys leave more reading room. The folder is available through Reading options.
The header and icon controls were checked at accessibility XXXL; metadata wraps
without splitting status words or overflowing its column.

The native system photo picker is presented from a stable view modifier, with
image-file selection as a second entry point. Composer previews include remove
controls, machine-specific upload progress and persistent unsent photo drafts.
Synthetic-image verification succeeded with live Mac/Codex and Windows/Claude.
Output remains a live terminal-screen read, not reconstructed chat history.
