# Shared context for phone chats

Every normal prompt sent through the iPhone bridge includes the instructions in
[`bridge/agent-context.md`](../bridge/agent-context.md), followed by the selected
machine, provider, terminal and current working directory. The user's text and
execution-machine photo paths follow unchanged. Edit that single file and
release the bridge to update the behavior for every phone chat.

This works with both Codex and Claude, for new agents and already-running
sessions. It is supplied on each normal message, so resuming, switching or
clearing a conversation does not depend on the previous conversation remembering
Herdr. Existing request receipts still prevent duplicate delivery. No iPhone
build or worker update is required.

The context covers concise phone output, clickable URLs, private Tailscale
preview behavior, execution-machine photo paths, mixed-machine workspaces and
Mark's default PR-first release workflow. Machine metadata is refreshed and
encoded separately from the maintained instructions; no credentials or other
agents' conversations are included.

## Boundaries

This is application-supplied context in the user-message channel, not a provider
system-prompt override or a guarantee that a model follows every instruction.
Project instructions and provider/tool permissions remain in effect. The bridge
uses the terminal prompt interface, which has no separate system-message field.

Native slash commands such as `/clear` and `/resume`, and bang shell commands,
are passed through unchanged when sent without photos. The next normal prompt
includes context again. Approval responses and key presses remain exact input.
Messages typed directly into desktop terminals bypass this bridge; they do not
receive this context automatically. Other ChatGPT/Claude apps are also outside
this scope.

Codex supports persistent [AGENTS.md instructions](https://learn.chatgpt.com/docs/agent-configuration/agents-md),
and Claude supports [CLAUDE.md and appended system instructions](https://code.claude.com/docs/en/memory).
Those mechanisms can cover direct desktop use separately. We do not rewrite
personal or project instruction files merely to connect a phone session.
