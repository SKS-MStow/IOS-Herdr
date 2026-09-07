# Styled output and clickable previews

Session output retains terminal foreground colours, bold/italic emphasis and
hyperlinks. Ordinary HTTP/HTTPS URLs are detected as tappable links. Reading mode
removes full-width divider lines, trailing ruler decoration and repeated blank
lines; it preserves code indentation. **aA → Original terminal layout** keeps
original line layout in monospace. This is a styled terminal-screen read, not a
reconstructed conversation history.

Tap a link to open the in-app Safari browser. Public links and existing Tailscale
links open directly. An HTTP localhost URL with a development port (for example
`http://localhost:5173/`) asks the paired Mac to prepare a private HTTPS preview.
The source machine comes from that session's saved machine identity. For Home PC,
the Mac opens an SSH loopback tunnel using the existing saved worker alias.
The development server must already be running. Herdr does not start a server or
send terminal commands just because a link was tapped.

The browser address becomes `https://<controller>.ts.net:<preview-port>/...`.
Paths, query strings and fragments are retained. A loopback relay rewrites the
backend Host and same-preview Origin headers for localhost development servers,
rewrites localhost redirects, and forwards WebSocket upgrades for live updates.
Relative assets/API requests keep their root paths. Apps that hard-code absolute
localhost asset URLs still need their own public/base URL configured; Herdr does
not rewrite arbitrary HTML or JavaScript.

**aA → Private preview links** lists prepared links. Swipe a row and choose
**Stop sharing** to remove its preview without stopping the development server.
At most eight routes are allocated on private HTTPS ports 8444–8451. Existing
Tailscale routes (including 443 and the controller's 8443) are preserved. The
feature uses [Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve),
never Funnel. Other permitted tailnet members can use a prepared preview URL.
URLs are development previews, not permanent published addresses.

Mappings are stored in `previews.json` beside the bridge database, mode 0600.
Loopback relays use ports 19044–19051; remote SSH forwards use 20044–20051.
On bridge restart, mappings restore their relay and tunnel processes. If a
worker disconnects later, tap its original localhost link again to reconnect.
A route occupied by another service or enabled for Funnel is never overwritten
by opening a preview. Local HTTPS/self-signed backends and privileged/reserved
ports are not supported by this feature; existing non-local HTTPS URLs open as
normal links.

## Verification

Bridge tests cover ANSI decoding, hyperlink safety, preview target validation,
reservation/retry behaviour and preservation of existing Tailscale routes.
Native tests cover styled text, divider removal, code indentation, tappable
links, local-link handling, in-app browser navigation and accessibility text.
Live Mac and Home PC fixtures verified HTTPS, paths/query strings, Host handling,
redirects, WebSockets, restart restoration and cleanup. Existing agent identities
and the original Tailscale Serve configuration were preserved.
