# Herdr for iPhone

<!-- impeccable:product-schema 1 -->

## Platform
ios

## Users and purpose
Mark wants to see his running coding agents, receive notifications, read terminal
output and interact from his iPhone. He selected the first dark/mint mockup and
asked for the full app, distributed through his existing TestFlight account.

## Stack
Implementation choice: native SwiftUI, a dependency-free Node.js controller
service, and the existing private Herdr CLI. No provider API keys are needed by
the phone: agents use their existing sign-ins on each execution machine.

## Operating context
The Mac owns the shared machine list and shared session. The Windows Home PC is
a worker. STO-WKS-113 is pending Herdr setup, regardless of its Tailscale presence.
Computers must be awake; files are not synchronized. The controller and workers
remain independent of the iPhone's navigation and connection lifetime.

## Constraints
Use stable machine and terminal identities, label the execution machine on
every action, preserve existing installations, never retry uncertain commands,
never claim stale state is live, and never expose a general shell HTTP endpoint.
Apple push delivery needs a configured APNs provider credential and a registered
device. Demo content must be visibly distinguished from live content.

## Visual commitment
The selected visual is `preview/assets/option-1.png`. Preserve its dark surface,
mint actions and three principal destinations. After using the first TestFlight
build, Mark asked for a compact, easy-to-scan agent list with smaller badges.
Prefer two-line rows, small symbols and inline status; the whole row opens the
session. Keep full machine/project details available in the session view.
