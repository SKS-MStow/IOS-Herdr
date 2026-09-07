---
name: Herdr for iPhone
description: A graphite and mint interface for agents running on your computers.
colors:
  background: "#111413"
  surface: "#1C211E"
  mint: "#B5E4C9"
  secondary: "#AAB5AE"
  attention: "#F5C15B"
typography:
  display:
    fontFamily: "SF Pro"
    fontWeight: 700
  agent-title:
    fontFamily: "SF Pro"
    fontWeight: 600
  body:
    fontFamily: "SF Pro"
  output:
    fontFamily: "SF Mono"
rounded:
  action: "10pt"
  field: "12pt"
spacing:
  compact: "8pt"
  small: "12pt"
  medium: "16pt"
  content: "20pt"
  section: "24pt"
components:
  button-primary:
    backgroundColor: "{colors.mint}"
    textColor: "{colors.background}"
    rounded: "{rounded.field}"
    height: "48pt"
  input:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.field}"
    padding: "14pt"
  notice:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.attention}"
    rounded: "{rounded.field}"
    padding: "{spacing.medium}"
---

# Design System: Herdr for iPhone

## Overview

**Creative North Star: "Graphite and mint"**

The visual authority is Mark's selected [option A](preview/assets/option-1.png),
adapted to native SwiftUI. Preserve its dark surface, restrained mint actions,
clear agent rows and three principal destinations. The app is calm and direct:
agent names, execution machines and current status carry the hierarchy.

This records the implemented system in `ios/Herdr/Views` and `HerdrApp.swift`.
Tokens above describe app-owned styling; points are native layout units. SF
Symbols, system text styles, safe areas, navigation chrome, keyboard, sheets and
confirmation dialogs remain native. Their exact appearance can vary by iOS.

## Colors

Warm graphite neutrals keep output readable and let actions and state stand out.

- **Primary — mint:** app tint, primary actions, selected machine filter,
  active navigation, working/completed state and unread indicators.
- **Attention — amber:** current requests for a response and actionable notices.
- **Neutral — background:** the screen canvas and plain Inbox rows.
- **Neutral — surface:** fields, notices, grouped forms.
- **Neutral — secondary:** machine/provider details, paths, timestamps, pending
  setup and stale status. Agent-row rules use this color at 20% opacity.

Primary text uses SwiftUI `.primary` and native label colors. The earlier fixed
primary-text hex is not an implemented token. The app requests dark appearance.
System destructive actions and notification badges retain native colors.

**The state rule.** Pair status color with text and a symbol. Stale agents use
secondary color and “Last known state”. Attention is an inline amber label;
status never gets a separate large banner or action area in an agent row.

## Typography

Use SF system text styles with Dynamic Type, rather than fixed font sizes.
Workspaces, its group and agent lists, and the membership picker use inline
navigation titles to leave room for content. Inbox, Machines and pairing
headlines use the native large-title hierarchy. Agent
names and grouped list names use `headline`; compact row metadata uses `footnote`
and inline status uses `caption`. Supporting screens use `subheadline`, with
`caption` and `footnote` for timestamps, path details and concise guidance.

Session output defaults to the system `body` style with 6pt line spacing and
permits text selection. Reading options offer the original terminal layout in monospaced body text.
Terminal foreground colours and emphasis are preserved; dim text stays legible.
HTTP/HTTPS links are mint and underlined. Reading mode removes terminal-width
rulers and excess blank lines, preserving indentation. Links open native Safari
inside the app. A localhost link shows progress while its private Tailscale
preview is prepared; failures keep the session visible with an actionable error.
Private preview links are managed in a native list under Reading options.
Pause freezes the current screen; Resume reads fresh output. Paths and identifiers must remain accurate; monospace is appropriate
for terminal content, not general interface copy. Use SF Symbols for controls,
machine types, folders and status. Visible labels explain unfamiliar controls,
including “Follow output”.

## Layout

Workspaces starts with All agents and Unassigned, followed by named groups in a
native plain List. Group rows show a headline name and a footnote summary of
agent and machine counts. Group detail reuses the compact agent list; adding
membership uses a searchable native list. At accessibility text sizes, the
browse links omit decorative symbols so their labels can wrap.

Agent lists use small unfilled terminal symbols, full-width
row targets and native separators. Row insets are 16pt horizontally and 12pt
vertically, with a 20pt symbol column and a 12pt content gap. Names and status
share the first line; machine, provider and project share the second. The entire
row opens the session. Names may wrap to two lines. At accessibility text sizes,
status moves below the name and metadata wraps. Decorative symbols and the
agent count are omitted at accessibility sizes to give the text more room.

In All agents and Unassigned, the machine filter and a compact connection/count
line stay above the scrolling list. The deferred Work laptop remains in
Machines, where setup status belongs.

In demo mode, shared-workspace navigation titles begin with “Demo ·”. The native
navigation bar keeps the qualifier visible while lists scroll, including at
accessibility text sizes. Place this marker before the title so long names
cannot hide the sample-data distinction.

Session detail keeps machine and state above a scrolling output area; the folder
is available in Reading options. The session hides the tab bar to leave more
reading space. The plus menu offers Photo library, Image from Files and terminal
keys. Keys expand above the composer only when requested. Photo previews include
44pt remove controls. Upload progress names the execution machine. The output inset
uses `content`; the composer uses `medium`. The text field grows from one to
four lines. Explicit terminal controls have at least 44pt targets; the send
control is 48pt. The primary button token's height is a minimum.

Inbox uses a native plain list. Machines, Settings and Start an agent use native
grouped lists or forms. Pairing is a scrollable column with `section` padding,
centered at a maximum width of 560pt. Preserve native safe areas and scrolling.
No custom iPad composition or breakpoint system has been established.

## Elevation & Depth

App-owned content uses tonal layering and dividers, without custom shadows.
Surface-colored fields and notices separate content from the darker canvas. Native navigation, sheets and alerts provide their own system depth;
do not reproduce their current rendering with custom decorative containers.

## Shapes

Fields, notices and primary pairing actions share the gently rounded `field`
shape. Agent-row symbols have no enclosing badge; the send control is circular.
Segmented controls, grouped
lists, toolbar items and tab navigation keep their native shapes.

## Components

- **Navigation:** Workspaces, Inbox and Machines are native tabs, each with a
  navigation stack. Workspaces opens All agents, Unassigned and named groups;
  group and agent rows open their details. Inbox carries the unread badge.
  Workspaces offers Create workspace and Settings in its toolbar. Settings and
  Start an agent remain available from the agent-list toolbar as native sheets.
  Keep destination titles visible.
- **Shared workspace:** a named group uses compact rows and count summaries.
  Group details retain the execution machine, provider and folder in each
  available agent row. Unavailable saved members retain machine context and
  explicitly say “Machine unavailable” or “Session ended”. Native menus, alerts
  and swipe actions handle group management; deletion copy explains that agents
  keep running on their machines.
- **Membership picker:** search by agent or machine, then use the whole row to
  add or remove membership. Mint plus/check symbols and Add/Remove accessibility
  wording expose the current action. Preserve the compact agent-row identity.
- **Start an agent:** a native form names the selected shared group when
  entered from group detail, then asks where to run the agent. Keep “Run on”,
  machine-specific folder guidance and provider selection explicit. Progress,
  errors and recovery text distinguish creating an execution workspace,
  starting an agent and finishing group membership.
- **Machine filter:** a native segmented picker; selected segments use mint
  with dark text. Pending machines are not offered as active filters.
- **Agent row:** name and inline status, then execution machine, provider and
  folder. Current attention uses amber text; all rows use native disclosure
  chevrons. No separate “Open session” button or decorative icon well. The
  accessibility label includes the full name, state, machine, provider and folder.
- **Primary action:** headline label, full available width and dark-on-mint
  contrast. The custom style reduces mint opacity to 70% while pressed and
  overall opacity to 45% when disabled. Other buttons use native styles.
- **Fields and composer:** surface fill and padded text; URL and code fields
  choose appropriate native keyboards. Send and terminal keys are unavailable
  when disconnected, stale, awaiting delivery checks or in demo mode.
- **Notices and confirmations:** a symbol and concise text explain errors or
  stale output. Uncertain delivery exposes “Check delivery” before further
  commands. Interruption and access changes use native confirmation dialogs.
- **Demo states:** Workspaces, group detail and the membership picker prefix
  their navigation titles with “Demo ·”. Agent lists and Inbox show “DEMO”
  in their toolbars.
  Session shows “Sample output” and “Demo · commands are disabled”. Machines
  labels sample connections. These labels must remain visible without hiding
  screen titles.
- **Empty and pending states:** use native `ContentUnavailableView` for empty
  agents, Inbox and unavailable sessions. Pending machines say “Setup pending”.
  Copy must reflect real connection and command state.

**The demo continuity rule.** Scrolling through sample groups or membership
choices must never remove the visible demo label. Keep offline, stale and saved
member states explicit; sample activity is not evidence of a live connection.

## Do's and Don'ts

- **Do** keep the execution machine visible in session context and action labels.
- **Do** preserve the chosen graphite/mint hierarchy and native iOS affordances.
- **Do** retain text and symbol cues alongside status color, including stale and
  sample data states.
- **Do** use semantic text styles and meaningful accessibility labels; runtime
  accessibility coverage is recorded separately in [design QA](design-qa.md).
- **Don't** label cached state as live or make uncertain commands look safe to
  repeat.
- **Don't** replace native tab navigation with custom decorative chrome.
- **Don't** treat a sample-data screenshot or push-service configuration as proof
  of live command execution or an alert received on an iPhone.
