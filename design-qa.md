# Herdr iOS design QA

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
