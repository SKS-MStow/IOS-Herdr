# Session instructions for phone agents

When the phone starts a Codex or Claude agent, the bridge supplies
[`bridge/agent-context.md`](../bridge/agent-context.md) once through the provider's
native startup settings, together with its execution-machine identity:

- Codex: `-c developer_instructions=...` (additional developer instructions).
- Claude: `--append-system-prompt ...` (appended system instructions).

Normal phone messages contain exactly the user's text. Photo messages append
only the image paths required for that particular request. There are no repeated
context blocks, short reminders, or per-message machine metadata. Native slash
commands, approval responses and key input remain literal. Request receipts
still prevent duplicate delivery.

The provider retains the instructions as session context, rather than Herdr
adding another copy on every turn. They still occupy a fixed amount of context
and may count toward input usage; system prompts are not free tokens. Provider
caching and compaction determine actual usage.

## Lifecycle and scope

The launch settings cover agents started using the phone's Start Agent action.
They do not retrofit existing processes or agents launched directly in a desktop
terminal. Already-running agents stop receiving repeated blocks immediately;
they retain whatever is in their existing conversation until it is cleared or
compacted. Relaunch with the startup settings to adopt persistent instructions.
Active agents are never restarted automatically.

A native new-chat/reset within the configured process uses its startup settings.
Resuming in a new process must supply the settings again; an external desktop
resume command does not pass through the phone's start path. Other providers
keep their usual launch and receive no automatic shared instructions.

The Codex command-line setting takes precedence over a `developer_instructions`
value in its configuration for that invocation. Project AGENTS.md guidance and
other configuration remain loaded. If maintaining custom developer instructions,
include them in the shared launch instructions before using this launch path.
Claude appends to its default system prompt, preserving CLAUDE.md guidance.
No credentials, global instruction files, permissions or personal profiles change.

Edit the single shared Markdown file and release/restart the bridge. Updated
instructions apply to subsequent agent launches; existing processes keep the
version they started with. No iPhone rebuild or worker update is required.

References: [Codex configuration](https://learn.chatgpt.com/docs/config-file/config-reference)
and [Claude system-prompt flags](https://code.claude.com/docs/en/cli-reference#system-prompt-flags).
