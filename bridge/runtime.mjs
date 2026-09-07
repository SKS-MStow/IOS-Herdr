import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { now } from './store.mjs';
import { terminalDocument } from './terminal-output.mjs';

const execute = promisify(execFile);
export class RuntimeError extends Error {
  constructor(message, code = 'runtime_error', uncertain = false) { super(message); this.code = code; this.uncertain = uncertain; }
}
export function cleanEnvironment() {
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('HERDR_')));
  return { ...env, PATH: `${process.env.HOME}/.local/share/herdr-shared/bin:${process.env.HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin` };
}
export class Runtime {
  constructor(config, store, runner = execute) {
    this.config = config; this.store = store; this.runner = runner; this.machines = []; this.agents = [];
    this.catalogReadGeneration = 0; this.catalogAppliedGeneration = 0;
    this.refreshing = null; this.machineLocks = new Map();
    this.sharedWorkspaceCatalog = { available: false, stale: true, revision: 0, workspaces: [] };
  }
  async command(machine, args, { text = false, mutation = false, timeout = 20000 } = {}) {
    const argv = ['--session', 'shared'];
    if (machine.remote) argv.push('machine', 'exec', machine.id, '--');
    argv.push(...args);
    try {
      const { stdout } = await this.runner(this.config.herdrPath, argv, { env: cleanEnvironment(), timeout, maxBuffer: 4 * 1024 * 1024, killSignal: 'SIGTERM' });
      if (text) return stdout;
      const response = JSON.parse(stdout);
      if (response.error) throw new RuntimeError(response.error.message, response.error.code, mutation);
      return response.result;
    } catch (error) {
      if (error instanceof RuntimeError) throw error;
      let known;
      try { known = JSON.parse(error.stderr || error.stdout || '').error; } catch {}
      if (known) {
        const safeRejections = ['agent_blocked', 'agent_not_found', 'pane_not_found', 'invalid_params', 'agent_busy', 'workspace_conflict', 'workspace_missing', 'request_conflict', 'workspace_rejected'];
        throw new RuntimeError(known.message, known.code, mutation && !safeRejections.includes(known.code));
      }
      throw new RuntimeError(mutation ? 'Delivery could not be confirmed. Inspect the session before sending again.' : 'This machine could not be reached.', 'unreachable', mutation);
    }
  }
  async discover() {
    const { stdout } = await this.runner(this.config.herdrPath, ['--session', 'shared', 'machine', 'list'], { env: cleanEnvironment(), timeout: 8000, maxBuffer: 64000 });
    const remote = stdout.trim().split('\n').filter(Boolean).map(line => {
      const [id, name, target, session, enabled] = line.split('\t');
      return { id, name, target, session, enabled, remote: true, platform: 'windows' };
    }).filter(item => /^[a-f0-9]{32}$/.test(item.id) && item.enabled === 'enabled');
    return [{ id: 'mac', name: 'Mac', remote: false, platform: 'mac', session: 'shared' }, ...remote];
  }
  refresh() {
    if (this.refreshing) return this.refreshing;
    this.refreshing = this.refreshAll().finally(() => { this.refreshing = null; });
    return this.refreshing;
  }
  async refreshAll() {
    const catalogRead = this.refreshSharedWorkspaces();
    let machines;
    try { machines = await this.discover(); }
    catch { machines = this.machines.filter(item => item.id !== 'work-laptop'); if (!machines.length) machines = [{ id: 'mac', name: 'Mac', remote: false, platform: 'mac' }]; }
    const snapshots = await Promise.all(machines.map(async machine => {
      const previous = this.machines.find(item => item.id === machine.id);
      try {
        const response = await this.command(machine, ['api', 'snapshot']);
        const snapshot = response.snapshot;
        const current = { ...machine, state: 'online', lastSeen: now(), error: null, version: snapshot.version,
          workspaces: snapshot.workspaces.map(w => ({ id: w.workspace_id, label: w.label || 'Workspace', paneCount: w.pane_count })),
          panes: snapshot.panes.map(p => ({ id: p.pane_id, terminalId: p.terminal_id, cwd: p.cwd || '', workspaceId: p.workspace_id })) };
        const agents = snapshot.agents.map(agent => this.normalizeAgent(current, agent, snapshot));
        this.connectionEvent(current);
        for (const agent of agents) this.agentEvent(agent);
        return { machine: current, agents };
      } catch (error) {
        const current = { ...machine, state: 'offline', lastSeen: previous?.lastSeen || null, error: error.message, workspaces: previous?.workspaces || [], panes: previous?.panes || [] };
        this.connectionEvent(current);
        return { machine: current, agents: this.agents.filter(a => a.machineId === machine.id).map(a => ({ ...a, stale: true })) };
      }
    }));
    this.machines = snapshots.map(s => s.machine);
    this.machines.push({ id: 'work-laptop', name: 'Work laptop', platform: 'windows', state: 'pending', lastSeen: null, error: 'STO-WKS-113 needs its Herdr worker setup.', workspaces: [], panes: [], remote: true });
    this.agents = snapshots.flatMap(s => s.agents);
    await catalogRead;
  }
  normalizeAgent(machine, agent, snapshot) {
    const workspace = snapshot.workspaces.find(w => w.workspace_id === agent.workspace_id);
    const tab = snapshot.tabs.find(t => t.tab_id === agent.tab_id);
    return { id: `${machine.id}/${agent.terminal_id}`, machineId: machine.id, machineName: machine.name,
      terminalId: agent.terminal_id, session: machine.session || 'shared', paneId: agent.pane_id, workspaceId: agent.workspace_id,
      workspace: workspace?.label || 'Workspace', name: agent.name || tab?.label || agent.terminal_title_stripped?.replace(/^[^\p{L}\p{N}]+/u, '') || `${agent.agent || 'Agent'} · ${agent.pane_id}`,
      kind: agent.agent || 'unknown', status: agent.agent_status || 'unknown', cwd: agent.foreground_cwd || agent.cwd || '',
      sequence: agent.state_change_seq || 0, ready: Boolean(agent.interactive_ready), stale: false, updatedAt: now() };
  }
  agentEvent(agent) {
    const previous = this.store.observe(`agent:${agent.id}`, agent.status);
    if (previous === undefined || previous === agent.status) return;
    const kind = agent.status === 'blocked' ? 'attention' : ['idle', 'done'].includes(agent.status) && previous === 'working' ? 'completion' : null;
    if (kind) this.store.addEvent({ kind, agentId: agent.id, machineId: agent.machineId,
      title: kind === 'attention' ? 'An agent needs you' : 'An agent is ready', body: `${agent.name} · ${agent.machineName}` });
  }
  connectionEvent(machine) {
    const previous = this.store.observe(`machine:${machine.id}`, machine.state);
    if (previous && previous !== machine.state) this.store.addEvent({ kind: 'connection', machineId: machine.id,
      title: machine.state === 'online' ? 'Machine reconnected' : 'Machine disconnected', body: machine.name });
  }
  state() { return { generatedAt: now(), machines: this.machines.map(({ target, enabled, session, remote, ...machine }) => machine), agents: this.agents, sharedWorkspaceCatalog: this.sharedWorkspaceCatalog }; }
  async refreshSharedWorkspaces() {
    const generation = ++this.catalogReadGeneration;
    try {
      const catalog = await this.command({ remote: false }, ['shared-workspace', 'list']);
      if (!Array.isArray(catalog?.workspaces) || !Number.isSafeInteger(catalog.revision)) throw new Error('Unsupported catalog');
      if (catalog.revision < this.sharedWorkspaceCatalog.revision || generation < this.catalogAppliedGeneration) return;
      this.catalogAppliedGeneration = generation;
      this.sharedWorkspaceCatalog = { ...catalog, available: true, stale: false };
    } catch {
      if (generation < this.catalogAppliedGeneration) return;
      this.catalogAppliedGeneration = generation;
      this.sharedWorkspaceCatalog = { ...this.sharedWorkspaceCatalog, stale: true, error: 'Shared workspaces are unavailable. Check the Mac controller.' };
    }
  }
  async changeSharedWorkspace(input) {
    const result = await this.command({ remote: false }, ['shared-workspace', 'apply', JSON.stringify(input)], { mutation: true });
    await this.refreshSharedWorkspaces();
    return { ...result, message: 'Workspace updated.' };
  }
  async resolve(id) {
    await this.refresh();
    const agent = this.agents.find(a => a.id === id);
    if (!agent) throw new RuntimeError('This session has ended or moved. Refresh the agent list.', 'session_missing');
    const machine = this.machines.find(m => m.id === agent.machineId);
    if (agent.stale || machine?.state !== 'online') throw new RuntimeError('The execution machine is offline. Reconnect before sending.', 'offline');
    const current = await this.command(machine, ['agent', 'get', agent.paneId]);
    if (current.agent?.terminal_id !== agent.terminalId || current.agent?.agent !== agent.kind) throw new RuntimeError('The agent in this pane changed. Refresh before sending.', 'session_changed');
    return { agent, machine, current: current.agent };
  }
  async output(id, lines = 200) {
    const { agent, machine, current } = await this.resolve(id);
    // Alternate-screen history capture scrolls the worker and is unavailable while busy.
    // A phone refresh reads the visible terminal screen without scrolling it.
    const ansi = await this.command(machine, ['agent', 'read', agent.paneId, '--source', 'visible', '--lines', String(lines), '--format', 'ansi'], { text: true });
    return { agentId: id, ...terminalDocument(ansi), readAt: now(), source: 'visible', sequence: current.state_change_seq || 0 };
  }
  async locked(id, work) {
    const previous = this.machineLocks.get(id) || Promise.resolve();
    const next = previous.catch(() => {}).then(work);
    this.machineLocks.set(id, next);
    try { return await next; } finally { if (this.machineLocks.get(id) === next) this.machineLocks.delete(id); }
  }
  async action(id, action) {
    return this.locked(id, async () => {
      const { agent, machine, current } = await this.resolve(id);
      if (action.type === 'prompt') {
        if (current.agent_status === 'blocked') throw new RuntimeError('This agent is waiting at a question or approval. Read its output and use the response controls.', 'agent_blocked');
        if (action.imagePaths?.length && !['codex', 'claude'].includes(agent.kind)) throw new RuntimeError('This agent does not support photo messages.', 'invalid_attachment');
        const message = action.imagePaths?.length ? `${action.text || 'Describe the attached images.'}\n\nAttached images are stored on this computer. Open each image file with your image-reading tool before answering:\n${action.imagePaths.map(path => JSON.stringify(path)).join('\n')}` : action.text;
        await this.command(machine, ['agent', 'prompt', agent.paneId, message], { mutation: true, timeout: 15000 });
      } else {
        // Key input must match the status snapshot the person actually reviewed.
        if (current.state_change_seq !== action.sequence) throw new RuntimeError('The session changed since you viewed it. Refresh the output before responding.', 'stale_response');
        if (action.type === 'response') {
          await this.command(machine, ['pane', 'send-text', agent.paneId, action.text], { mutation: true });
          // Revalidate identity before pressing Enter; a partial response is uncertain, never replayed.
          try {
            const check = await this.command(machine, ['agent', 'get', agent.paneId]);
            if (check.agent?.terminal_id !== agent.terminalId) throw new RuntimeError('Session changed after text was entered. Inspect the terminal.', 'session_changed', true);
            await this.command(machine, ['agent', 'send-keys', agent.paneId, 'enter'], { mutation: true });
          } catch (error) {
            throw new RuntimeError('Text may have been entered without submitting. Inspect the session before sending again.', error.code || 'partial_response', true);
          }
        } else await this.command(machine, ['agent', 'send-keys', agent.paneId, action.key], { mutation: true });
      }
      return { message: 'Input accepted by Herdr.' };
    });
  }
  async createWorkspace(input) {
    await this.refresh();
    const machine = this.machines.find(m => m.id === input.machineId);
    if (!machine || machine.state !== 'online') throw new RuntimeError('Select a connected machine.', 'offline');
    if (machine.platform === 'mac' ? !input.cwd.startsWith('/') : !/^[A-Za-z]:[\\/]/.test(input.cwd)) throw new RuntimeError('Enter an absolute folder path on the selected machine.', 'invalid_path');
    const result = await this.command(machine, ['workspace', 'create', '--label', input.label, '--cwd', input.cwd, '--no-focus'], { mutation: true });
    return { message: 'Workspace created.', machineId: machine.id, paneId: result.root_pane.pane_id, workspaceId: result.workspace.workspace_id };
  }
  async startAgent(input) {
    await this.refresh();
    const machine = this.machines.find(m => m.id === input.machineId);
    if (!machine || machine.state !== 'online') throw new RuntimeError('The execution machine is offline.', 'offline');
    const pane = machine.panes.find(p => p.id === input.paneId);
    if (!pane) throw new RuntimeError('The workspace pane no longer exists.', 'pane_missing');
    if (this.agents.some(a => a.machineId === machine.id && a.paneId === input.paneId)) throw new RuntimeError('An agent is already running in this pane.', 'agent_exists');
    const result = await this.command(machine, ['agent', 'start', input.name, '--kind', input.kind, '--pane', input.paneId, '--timeout', '30000'], { mutation: true, timeout: 40000 });
    await this.refresh();
    return { message: 'Agent started.', agentId: `${machine.id}/${result.agent.terminal_id}` };
  }
}
