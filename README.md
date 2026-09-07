# Herdr for iPhone

Native SwiftUI companion for Mark’s shared Herdr. See agents on the Mac and Home
PC, read their terminal screens, send messages, photos and key responses, create
workspaces, start agents, and receive activity notifications.

The selected design is A / option 1: graphite surfaces with mint controls.

## Open from the PC or iPhone

- [Native app screenshots](http://100.103.121.43:8765/)
- [Pair the iPhone](https://marks-macbook-air.tail79ccb5.ts.net:8443/connect)
- [Configure Apple notifications](https://marks-macbook-air.tail79ccb5.ts.net:8443/setup)

Keep Tailscale connected and the Mac awake. The review page is static; the iOS
app provides the real controls. The controller runs privately through Tailscale
HTTPS, without Funnel or public internet exposure.

## Using the app

1. Install or update to **Herdr Shared 0.1.0 (5)** in TestFlight. If already paired,
   your connection and notification settings carry over.
2. On the iPhone, open the pairing page and create a one-use code. Tap **Open
   Herdr and connect**, then **Connect to Mac**. Codes expire after ten minutes.
3. In **Workspaces**, create a group, add existing Mac or Home PC agents,
   and open any agent to read its terminal or send input. **All agents** remains
   available. Starting a new agent requires an existing folder on its execution
   machine; creating a shared group does not.
4. In a session, **Pause** holds the output while you read. The **aA** menu offers
   the original terminal layout and reading options. Output preserves colours and
   emphasis; tap a link to open it inside the app. Localhost development links
   open through private Tailscale HTTPS on the agent’s machine.
   [Private preview details](docs/rich-output-and-previews.md). Tap **+** to attach up to three photos
   from Photos or Files to a Codex or Claude prompt. [Photo details](docs/session-photos.md).
5. In **Settings**, enable notifications, choose alert types and send a test
   notification. This requires an APNs key on the controller. Apple accepting
   a notification is separate from the alert appearing on the phone.

Sample mode is available before pairing and disables real commands. The Inbox
records state changes even when push is not configured. The Work laptop remains
marked **Setup pending** until its worker installation is completed separately.

The app shows running agents and their providers. It does not enumerate billing
accounts or move agent sign-ins, project folders or files between machines.
Terminal output is the visible screen, not a complete conversation transcript.
An uncertain command is never resent automatically: read the session and check
delivery before allowing new input.

## Build and verify

Requires macOS, Xcode, XcodeGen, Node.js 22.13 or newer, Tailscale and the private
shared Herdr CLI. This project has no third-party application dependencies.

```sh
npm test
xcodegen generate --spec ios/project.yml
xcodebuild -project ios/Herdr.xcodeproj -scheme Herdr -destination 'platform=iOS Simulator,name=iPhone 17' -skip-testing:HerdrUITests/HerdrUITests/testPreparedLivePairing test
bash scripts/archive-testflight.sh
```

The opt-in live smoke script `node scripts/smoke-live.mjs` creates and closes
only its own temporary Scratch workspaces on each connected machine. It starts
the installed agent and sends a reply-only prompt, which may use the provider’s
normal account allowance. Do not run it as part of routine unit tests.

See [development and release](docs/development.md), [controller operations](docs/controller.md),
[product scope](PRODUCT.md) and [visual design](DESIGN.md).

## Current release state

Version 0.1.0 (5) is available in the Mark internal TestFlight group. Apple
reports `VALID` and `IN_BETA_TESTING`, with only the account holder enrolled.
The production bridge is deployed. Existing phone pairing and agents were
preserved. Private HTTPS previews were verified from the Home PC, including
Mac and Windows backends, redirects, WebSockets and restart restoration.
Physical installation of build 5 remains unconfirmed. See
[the verification record](docs/release-status.json).

## Context across phone chats

Codex and Claude agents started from the iPhone load the shared Herdr instructions
once through native startup settings. Normal messages contain only your text;
photos add their execution-machine paths. Existing running agents need a fresh
launch to adopt the startup settings. See [scope and editing](docs/agent-context.md).

## Shared workspaces

Build 3 adds the same named, mixed-machine groups to desktop Herdr and the
phone. Desktop source is in [Herdr-Shared](https://github.com/SKS-MStow/Herdr-Shared),
a separate private fork. See [the workspace contract](docs/shared-workspaces.md).
Reopen `herdr-multi` to use the new desktop sidebar. Existing official Herdr
installs and the Home PC worker are preserved.
