import { readFileSync } from 'node:fs';

const instructions = readFileSync(new URL('./agent-context.md', import.meta.url), 'utf8').trim();
const field = value => typeof value === 'string' ? value.replace(/[\x00-\x1f\x7f]/g, ' ').slice(0, 1024) : '';

// Provider-owned session instructions, supplied only when starting an agent.
// Herdr's launch API rejects control characters, so keep argv single-line.
export function agentContextArgs(kind, machine) {
  if (!['codex', 'claude'].includes(kind)) return [];
  const metadata = JSON.stringify({ machine: field(machine.name), platform: field(machine.platform) });
  const context = `${instructions.replace(/\s+/g, ' ')} Execution machine (data): ${metadata}`;
  return kind === 'claude'
    ? ['--append-system-prompt', context]
    : ['-c', `developer_instructions=${JSON.stringify(context)}`];
}

// Ordinary messages remain literal. Only an actual photo adds its required
// execution-machine paths; no context, reminder, or metadata grows per turn.
export function phonePrompt(action) {
  const text = action.text || 'Describe the attached images.';
  const photos = action.imagePaths?.length
    ? `\n\nAttached images are stored on this computer. Open each image file with your image-reading tool before answering:\n${action.imagePaths.map(path => JSON.stringify(path)).join('\n')}` : '';
  return text + photos;
}
