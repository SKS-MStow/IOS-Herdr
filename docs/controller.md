# Controller operations

## Installed services

The native app calls the Node.js bridge. The bridge calls Mark’s existing private
Herdr executable, using session `shared`; Home PC commands are forwarded using
the existing Herdr machine entry and SSH configuration.

| Item | Location |
| --- | --- |
| Private Herdr | `~/.local/share/herdr-shared/bin/herdr` |
| Bridge config | `~/.config/herdr-iphone/config.json` |
| Database | `~/.local/share/herdr-iphone/controller.sqlite` |
| APNs keys | `~/.config/herdr-iphone/keys/` |
| LaunchAgent | `~/Library/LaunchAgents/com.mark.herdr-iphone.plist` |
| Logs | `~/Library/Logs/HerdrIPhone/` |
| Loopback listener | `127.0.0.1:8790` |
| Private HTTPS | `https://marks-macbook-air.tail79ccb5.ts.net:8443` |

Install or refresh the launch service using `node scripts/install-controller.mjs`.
This preserves the existing local configuration. After source changes, restart:

```sh
launchctl kickstart -k "gui/$(id -u)/com.mark.herdr-iphone"
curl --fail https://marks-macbook-air.tail79ccb5.ts.net:8443/health
```

The existing service on Tailscale HTTPS port 443 is independent. The original
Herdr installation and upstream updater are not modified. The bridge’s source
path is in its LaunchAgent: keep this checkout in place while that agent is used.

## Access and notifications

Pairing and APNs upload use the owner’s Tailscale identity supplied by Tailscale
Serve. A local admin bearer can also access operator endpoints. It is stored in
the private config; never paste it into a chat, log, URL or source file.

Pairing returns a random device bearer once; the bridge stores only its hash.
The app keeps the bearer in Keychain. **Unpair this iPhone** revokes it on the
controller. Operator endpoints can list and revoke devices if a phone is lost.
Pairing codes expire after ten minutes and can be consumed once.

APNs uploads must be Apple P-256 `.p8` keys, separate from App Store Connect API
credentials. Private directories are mode 0700; config, database and keys are
mode 0600. TestFlight uses production APNs; debug builds register for sandbox.
Notification content never includes terminal output; agent/machine names are
hidden in the alert body unless that iPhone opts in.

The bridge observes state transitions every five seconds. Initial discovery
does not send alerts. Events are persisted in Inbox. The push outbox retries
transient Apple/network errors, expires events after one hour and clears invalid
device tokens. Turned-off preferences are rechecked before delivery.

## Command safety and limitations

Each input request has a persisted UUID. Repeating the same request retrieves
its recorded result. A restart changes interrupted operations to **uncertain**;
the bridge never dispatches them again. Partial text entry also remains uncertain.
Different input cannot reuse an old request UUID.

The bridge checks the machine, terminal identity and provider before input,
and checks the viewed state sequence for key/response actions. Actions for one
agent are serialized. The existing Herdr CLI has no atomic conditional-send
primitive: another desktop viewer can change a pane between a check and a send.
Read the current question before responding and avoid simultaneous input from
multiple viewers.

HTTP exposes specific workspace and agent actions, not an arbitrary shell
endpoint. Arguments are passed using `execFile`, without shell interpolation.
Agent prompts can still perform whatever work that signed-in agent is allowed
to do on its execution machine.

If a worker goes offline, its last agents are retained in memory and marked
stale. Output already read in an open session remains visible; it is not a
persistent transcript. The current terminal screen is read without scrolling
or selecting a desktop pane. Restarting the bridge does not stop Herdr agents;
restarting their execution computer may stop them.

## Static review service

`com.mark.herdr-mockups` serves only `preview/` at `100.103.121.43:8765`, bound to
the Mac’s Tailscale IP. Logs are under `~/Library/Logs/HerdrMockups/`. No keys,
IPAs, live terminal content or config files belong in this directory.
