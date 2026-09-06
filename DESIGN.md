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
Agents uses an inline navigation title to leave room for the list. Other top-level
destinations and pairing headlines use the native large-title hierarchy. Agent
names and grouped list names use `headline`; compact row metadata uses `footnote`
and inline status uses `caption`. Supporting screens use `subheadline`, with
`caption` and `footnote` for timestamps, path details and concise guidance.

Session output uses the monospaced `subheadline` style and permits text
selection. Paths and identifiers must remain accurate; monospace is appropriate
for terminal content, not general interface copy. Use SF Symbols for controls,
machine types, folders and status. Visible labels explain unfamiliar controls,
including “Follow output”.

## Layout

Agents uses a native plain List, small unfilled terminal symbols, full-width
row targets and native separators. Row insets are 16pt horizontally and 12pt
vertically, with a 20pt symbol column and a 12pt content gap. Names and status
share the first line; machine, provider and project share the second. The entire
row opens the session. Names may wrap to two lines. At accessibility text sizes,
status moves below the name and metadata wraps. Decorative symbols and the
agent count are omitted at accessibility sizes to give the text more room.

The machine filter and a compact connection/count line stay above the scrolling
list. The deferred Work laptop remains in Machines, where setup status belongs.

Session detail keeps machine and folder context above a scrolling output area.
The key strip and multiline composer sit below the output. The output inset
uses `content`; the composer uses `medium`. The text field grows from one to
six lines. Explicit terminal controls have at least 44pt targets; the send
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

- **Navigation:** Agents, Inbox and Machines are native tabs, each with a
  navigation stack. Inbox carries the unread badge. Settings and Start an agent
  open from the Agents toolbar as sheets. Keep destination titles visible.
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
- **Demo states:** Agents and Inbox show “DEMO” in their toolbars. Session shows
  “Sample output” and “Demo · commands are disabled”. Machines labels sample
  connections. These labels must remain visible without hiding screen titles.
- **Empty and pending states:** use native `ContentUnavailableView` for empty
  agents, Inbox and unavailable sessions. Pending machines say “Setup pending”.
  Copy must reflect real connection and command state.

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
