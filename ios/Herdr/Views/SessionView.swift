import SwiftUI

struct SessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    let agentId: String
    @State private var output: SessionOutput?
    @State private var outputError: String?
    @State private var message = ""
    @State private var sending = false
    @State private var followOutput = true
    @State private var notice: String?
    @State private var confirmInterrupt = false
    @State private var confirmNewInput = false
    @FocusState private var composing: Bool
    private var agent: Agent? { model.agents.first { $0.id == agentId } }
    private var pending: Bool { model.pending[agentId] != nil }
    private var canSend: Bool { model.connected && agent?.stale == false && !sending && !pending && output != nil }
    var body: some View {
        VStack(spacing: 0) {
            if let agent {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("\(agent.provider) · \(agent.machineName)").font(.headline); Spacer(); StatusLabel(agent: agent) }
                    Label(agent.cwd, systemImage: "folder").font(.caption).foregroundStyle(Theme.secondary).lineLimit(2).textSelection(.enabled)
                    if agent.stale || !model.connected && !model.isDemo { Notice(text: "Connection lost. Output may be out of date.") }
                }.padding(.horizontal, 20).padding(.vertical, 12)
                Divider()
                HStack {
                    Text(model.isDemo ? "Sample output" : "Session output").font(.subheadline.weight(.medium))
                    Spacer()
                    Toggle(isOn: $followOutput) { Text("Follow output").font(.caption) }.fixedSize().accessibilityLabel("Follow new output")
                    Button { Task { await refreshOutput() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("Refresh output")
                }.padding(.leading, 20).padding(.trailing, 8)
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 16) {
                            if let outputError { Notice(text: outputError) }
                            if let output { Text(output.text.isEmpty ? "No output yet." : output.text).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading) }
                            else { ProgressView("Reading session…").padding(.top, 30) }
                            Color.clear.frame(height: 1).id("end")
                        }.padding(20)
                    }.onChange(of: output?.text) { _, _ in if followOutput { proxy.scrollTo("end", anchor: .bottom) } }
                }
                if pending {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Delivery needs checking").font(.headline).foregroundStyle(Theme.attention)
                        Text("Read the output before sending another command.").font(.caption).foregroundStyle(Theme.secondary)
                        HStack {
                            Button("Check delivery") { Task { await checkDelivery() } }.buttonStyle(.bordered)
                            Button("I checked the session") { confirmNewInput = true }.buttonStyle(.bordered)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(Theme.surface)
                }
                Divider()
                HStack(spacing: 4) {
                    key("Esc", key: "esc")
                    key("Tab", key: "tab")
                    key(nil, key: "up", symbol: "arrow.up")
                    key(nil, key: "down", symbol: "arrow.down")
                    key(nil, key: "enter", symbol: "return")
                    Spacer(minLength: 0)
                    Button { confirmInterrupt = true } label: { Image(systemName: "stop.circle").frame(minWidth: 44, minHeight: 44) }.disabled(!canSend).accessibilityLabel("Interrupt agent with Control C")
                }.padding(.horizontal, 12)
                VStack(spacing: 7) {
                    if agent.needsAttention { Text("Read the question above. Your response goes to this agent’s active prompt.").font(.caption).foregroundStyle(Theme.attention).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack(alignment: .bottom, spacing: 12) {
                        TextField(agent.needsAttention ? "Respond to this prompt…" : "Message \(agent.name)…", text: $message, axis: .vertical)
                            .lineLimit(1...6).focused($composing).padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Message to \(agent.name) on \(agent.machineName)")
                        Button { Task { await sendMessage() } } label: {
                            if sending { ProgressView().frame(width: 48, height: 48) }
                            else { Image(systemName: "arrow.up").font(.title3.bold()).frame(width: 48, height: 48).foregroundStyle(Theme.background).background(Theme.mint, in: Circle()) }
                        }.disabled(!canSend || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).opacity(canSend ? 1 : 0.5).accessibilityLabel("Send message")
                    }
                    Text(model.isDemo ? "Demo · commands are disabled" : "Runs on \(agent.machineName)").font(.caption).foregroundStyle(Theme.secondary)
                }.padding(.horizontal, 16).padding(.bottom, 12)
            } else {
                ContentUnavailableView("Session unavailable", systemImage: "terminal", description: Text("It may have ended or moved. Pull down the agent list to refresh."))
            }
        }.herdrScreen().navigationTitle(agent?.name ?? "Session").navigationBarTitleDisplayMode(.inline)
            .task(id: "\(agentId)-\(scenePhase == .active)") {
                guard scenePhase == .active else { return }
                message = UserDefaults.standard.string(forKey: "draft.\(agentId)") ?? ""
                while !Task.isCancelled { await refreshOutput(); try? await Task.sleep(for: .seconds(3)) }
            }
            .onChange(of: message) { _, value in if !model.isDemo { UserDefaults.standard.set(value, forKey: "draft.\(agentId)") } }
            .alert("Session update", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) { Button("OK", role: .cancel) {} } message: { Text(notice ?? "") }
            .confirmationDialog("Interrupt this agent on \(agent?.machineName ?? "its machine")?", isPresented: $confirmInterrupt, titleVisibility: .visible) { Button("Send Control C", role: .destructive) { Task { await sendKey("ctrl+c") } } } message: { Text("This can stop its current task. The workspace remains open.") }
            .confirmationDialog("Allow a new command?", isPresented: $confirmNewInput, titleVisibility: .visible) { Button("I inspected the session; allow new input") { model.clearPending(agentId) } } message: { Text("The previous command may already have run. Herdr will not repeat it automatically.") }
    }
    private func key(_ title: String?, key: String, symbol: String? = nil) -> some View {
        Button { Task { await sendKey(key) } } label: { Group { if let symbol { Image(systemName: symbol) } else { Text(title ?? key).font(.subheadline) } }.frame(minWidth: 44, minHeight: 44) }.disabled(!canSend).accessibilityLabel(title ?? key)
    }
    private func refreshOutput() async {
        guard model.isDemo || model.connected else { return }
        do { output = try await model.output(for: agentId); outputError = nil }
        catch { if !Task.isCancelled { outputError = error.localizedDescription } }
    }
    private func sendMessage() async {
        guard let agent, let output, canSend else { return }
        let sentMessage = message
        sending = true; defer { sending = false }
        do {
            let operation = try await model.perform(path: "/api/agents/\(ControllerClient.agentPath(agentId))/actions", scope: agentId,
                body: ["type": agent.needsAttention ? "response" : "prompt", "text": sentMessage, "sequence": output.sequence])
            if operation.state == "accepted" { if message == sentMessage { message = ""; composing = false }; await refreshOutput(); await model.refresh() }
            else { notice = operation.message }
        } catch { notice = error.localizedDescription }
    }
    private func sendKey(_ key: String) async {
        guard let output, canSend else { return }
        sending = true; defer { sending = false }
        do {
            let operation = try await model.perform(path: "/api/agents/\(ControllerClient.agentPath(agentId))/actions", scope: agentId, body: ["type": "key", "key": key, "sequence": output.sequence])
            if operation.state != "accepted" { notice = operation.message }
            await refreshOutput()
        } catch { notice = error.localizedDescription }
    }
    private func checkDelivery() async {
        do { if let result = try await model.checkPending(agentId) { notice = result.message }; await refreshOutput() }
        catch { notice = error.localizedDescription }
    }
}
