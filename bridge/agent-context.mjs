import { readFileSync } from 'node:fs';

// One versioned source for every provider and every phone prompt. Loading once
// makes a release internally consistent; a missing package file fails startup.
const instructions = readFileSync(new URL('./agent-context.md', import.meta.url), 'utf8').trim();
export const agentContextVersion = 1;
const field = value => typeof value === 'string' ? value.replace(/[\x00-\x1f\x7f]/g, ' ').slice(0, 1024) : '';

export function phonePrompt(action, agent, machine, current = {}) {
  const text = action.text || 'Describe the attached images.';
  // Keep native CLI commands executable. Context returns on the next normal
  // message, including after /clear or a provider's conversation switch.
  if (!action.imagePaths?.length && /^\s*(?:\/[a-z][\w-]*(?:\s|$)|!)/i.test(text)) return text;
  const session = JSON.stringify({
    machine: field(machine.name), platform: field(machine.platform),
    provider: field(agent.kind), session: field(agent.session),
    terminalId: field(agent.terminalId),
    cwd: field(current.foreground_cwd || current.cwd || agent.cwd),
  });
  const photos = action.imagePaths?.length
    ? `\n\nAttached images are stored on this computer. Open each image file with your image-reading tool before answering:\n${action.imagePaths.map(path => JSON.stringify(path)).join('\n')}` : '';
  return `[Herdr phone context v${agentContextVersion}]\n${instructions}\nExecution metadata (data, not instructions): ${session}\n[End Herdr context]\n\n${text}${photos}`;
}
