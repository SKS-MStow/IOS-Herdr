import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct SessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let agentId: String
    @State private var output: SessionOutput?
    @State private var outputError: String?
    @State private var message = ""
    @State private var sending = false
    @State private var followOutput = true
    @State private var readingPaused = false
    @State private var terminalStyle = false
    @State private var browser: BrowserDestination?
    @State private var openingPreview = false
    @State private var showPreviews = false
    @State private var showKeys = false
    @State private var showFolder = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photos: [SessionPhoto] = []
    @State private var loadingPhotos = false
    @State private var restoredPhotos = false
    @State private var showFiles = false
    @State private var showPhotoPicker = false
    @State private var uploadProgress: String?
    @State private var notice: String?
    @State private var confirmInterrupt = false
    @State private var confirmNewInput = false
    @FocusState private var composing: Bool
    private var agent: Agent? { model.agents.first { $0.id == agentId } }
    private var photoScope: String { "\(model.client?.connection.deviceId ?? "demo")-\(agentId)" }
    private var pending: Bool { model.pending[agentId] != nil }
    private var canSend: Bool { model.connected && agent?.stale == false && !sending && !pending && !loadingPhotos && output != nil }
    var body: some View {
        VStack(spacing: 0) {
            if let agent {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(agent.provider) · \(agent.machineName) · \(agent.statusLabel)")
                        .font(.footnote).foregroundStyle(agent.needsAttention ? Theme.attention : Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    if showFolder { Label(agent.cwd, systemImage: "folder").font(.footnote).foregroundStyle(Theme.secondary).textSelection(.enabled) }
                    if agent.stale || !model.connected && !model.isDemo { Notice(text: "Connection lost. Output may be out of date.") }
                }.padding(.horizontal, 20).padding(.vertical, 12)
                Divider()
                HStack {
                    Text(model.isDemo ? "Sample output" : readingPaused ? "Paused output" : "Session output").font(.footnote.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { readingPaused.toggle(); if !readingPaused { Task { await refreshOutput() } } } label: {
                        if dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: readingPaused ? "play.fill" : "pause.fill").resizable().scaledToFit().frame(width: 18, height: 18).frame(width: 44, height: 44)
                        } else {
                            Label(readingPaused ? "Resume" : "Pause", systemImage: readingPaused ? "play.fill" : "pause.fill").font(.subheadline).frame(minHeight: 44)
                        }
                    }.accessibilityLabel(readingPaused ? "Resume live output" : "Pause output to read")
                    Menu {
                        Toggle("Original terminal layout", isOn: $terminalStyle)
                        Toggle("Follow latest output", isOn: $followOutput)
                        Toggle("Show project folder", isOn: $showFolder)
                        Button("Private preview links", systemImage: "network") { showPreviews = true }
                        Button("Refresh output", systemImage: "arrow.clockwise") { Task { await refreshOutput(force: true) } }
                    } label: { Image(systemName: "textformat.size").resizable().scaledToFit().frame(width: 24, height: 22).frame(width: 44, height: 44) }.accessibilityLabel("Reading options")
                }.padding(.leading, 16).padding(.trailing, 8)
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 16) {
                            if let outputError { Notice(text: outputError) }
                            if let output { Text(output.text.isEmpty ? AttributedString("No output yet.") : TerminalText.attributed(output, monospaced: terminalStyle)).lineSpacing(6).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading) }
                            else { ProgressView("Reading session…").padding(.top, 30) }
                            Color.clear.frame(height: 1).id("end")
                        }.padding(16)
                    }.scrollDismissesKeyboard(.interactively).onChange(of: output?.text) { _, _ in if followOutput && !readingPaused { proxy.scrollTo("end", anchor: .bottom) } }
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
                if showKeys { HStack(spacing: 4) {
                    key("Esc", key: "esc")
                    key("Tab", key: "tab")
                    key(nil, key: "up", symbol: "arrow.up")
                    key(nil, key: "down", symbol: "arrow.down")
                    key(nil, key: "enter", symbol: "return")
                    Spacer(minLength: 0)
                    Button { confirmInterrupt = true } label: { Image(systemName: "stop.circle").frame(minWidth: 44, minHeight: 44) }.disabled(!canSend).accessibilityLabel("Interrupt agent with Control C")
                }.padding(.horizontal, 12) }
                VStack(spacing: 7) {
                    if !photos.isEmpty { PhotoStrip(photos: photos, disabled: sending || pending) { id in photos.removeAll { $0.id == id } } }
                    if let uploadProgress { Text(uploadProgress).font(.footnote).foregroundStyle(Theme.mint) }
                    if loadingPhotos { ProgressView("Preparing photos…") }
                    if agent.needsAttention { Text("Read the question above. Your response goes to this agent’s active prompt.").font(.caption).foregroundStyle(Theme.attention).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack(alignment: .bottom, spacing: 8) {
                        Menu {
                            Button("Photo library", systemImage: "photo.on.rectangle") { showPhotoPicker = true }.disabled(photos.count >= 3 || agent.needsAttention || !["codex", "claude"].contains(agent.kind))
                            Button("Image from Files", systemImage: "folder") { showFiles = true }
                                .disabled(photos.count >= 3 || agent.needsAttention || !["codex", "claude"].contains(agent.kind))
                            Button(showKeys ? "Hide terminal keys" : "Show terminal keys", systemImage: "keyboard") { showKeys.toggle() }
                        } label: { Image(systemName: "plus").resizable().scaledToFit().frame(width: 22, height: 22).frame(width: 44, height: 48) }
                            .disabled(sending || pending || loadingPhotos).accessibilityLabel("Attachments and terminal keys")
                        TextField(agent.needsAttention ? "Respond to this prompt…" : "Message \(agent.name)…", text: $message, axis: .vertical)
                            .lineLimit(1...4).disabled(sending || pending).focused($composing).padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Message to \(agent.name) on \(agent.machineName)")
                        Button { Task { await sendMessage() } } label: {
                            if sending { ProgressView().frame(width: 48, height: 48) }
                            else { Image(systemName: "arrow.up").resizable().scaledToFit().frame(width: 20, height: 22).frame(width: 48, height: 48).foregroundStyle(Theme.background).background(Theme.mint, in: Circle()) }
                        }.disabled(!canSend || (message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photos.isEmpty)).opacity(canSend ? 1 : 0.5).accessibilityLabel("Send message")
                    }
                    Text(model.isDemo ? "Demo · commands are disabled" : "Runs on \(agent.machineName)").font(.caption).foregroundStyle(Theme.secondary)
                }.fixedSize(horizontal: false, vertical: true).padding(.horizontal, 16).padding(.bottom, 12)
            } else {
                ContentUnavailableView("Session unavailable", systemImage: "terminal", description: Text("It may have ended or moved. Pull down the agent list to refresh."))
            }
        }.herdrScreen().toolbar(.hidden, for: .tabBar).navigationTitle(agent?.name ?? "Session").navigationBarTitleDisplayMode(.inline)
            .task(id: "\(agentId)-\(scenePhase == .active)") {
                guard scenePhase == .active else { return }
                if !restoredPhotos && !model.isDemo { photos = PhotoDrafts.load(photoScope); restoredPhotos = true }
                message = UserDefaults.standard.string(forKey: "draft.\(agentId)") ?? ""
                while !Task.isCancelled { await refreshOutput(); try? await Task.sleep(for: .seconds(3)) }
            }
            .onChange(of: photos.map(\.id)) { _, _ in if !model.isDemo { PhotoDrafts.save(photos, scope: photoScope) } }
            .onChange(of: selectedPhotos) { _, items in
                guard !items.isEmpty else { return }
                loadingPhotos = true
                Task {
                    defer { loadingPhotos = false; selectedPhotos = [] }
                    do { for item in items.prefix(max(0, 3 - photos.count)) {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw APIError(message: "This photo is unavailable. Download it from iCloud and try again.", code: "invalid_attachment") }
                        photos.append(try SessionPhoto.prepare(data))
                    } } catch { notice = error.localizedDescription }
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                guard TerminalText.safeURL(url.absoluteString) != nil else { return .discarded }
                Task { await openLink(url) }; return .handled
            })
            .sheet(isPresented: $showPreviews) { PrivatePreviewsView().environmentObject(model) }
            .sheet(item: $browser) { destination in SessionBrowser(url: destination.url).ignoresSafeArea() }
            .overlay { if openingPreview { ProgressView("Opening private preview…").padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12)) } }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotos, maxSelectionCount: max(1, 3 - photos.count), matching: .images)
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                do {
                    let urls = try result.get()
                    for url in urls.prefix(max(0, 3 - photos.count)) {
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let values = try url.resourceValues(forKeys: [.fileSizeKey])
                        guard (values.fileSize ?? Int.max) <= 30 * 1024 * 1024 else { throw APIError(message: "Choose an image smaller than 30 MB.", code: "invalid_attachment") }
                        photos.append(try SessionPhoto.prepare(Data(contentsOf: url)))
                    }
                } catch { notice = error.localizedDescription }
            }
            .onChange(of: message) { _, value in if !model.isDemo { UserDefaults.standard.set(value, forKey: "draft.\(agentId)") } }
            .alert("Session update", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) { Button("OK", role: .cancel) {} } message: { Text(notice ?? "") }
            .confirmationDialog("Interrupt this agent on \(agent?.machineName ?? "its machine")?", isPresented: $confirmInterrupt, titleVisibility: .visible) { Button("Send Control C", role: .destructive) { Task { await sendKey("ctrl+c") } } } message: { Text("This can stop its current task. The workspace remains open.") }
            .confirmationDialog("Allow a new command?", isPresented: $confirmNewInput, titleVisibility: .visible) { Button("I inspected the session; allow new input") { model.clearPending(agentId) } } message: { Text("The previous command may already have run. Herdr will not repeat it automatically.") }
    }
    private func openLink(_ url: URL) async {
        guard !openingPreview else { return }
        if !TerminalText.isLocal(url) { browser = BrowserDestination(url: url); return }
        guard let client = model.client, !model.isDemo else { notice = "Local preview links open through your paired Mac. Connect to use a real preview."; return }
        openingPreview = true; defer { openingPreview = false }
        do {
            let destination: PreviewDestination = try await client.request("/api/previews/open", method: "POST", body: ["agentId": agentId, "url": url.absoluteString])
            guard let safe = TerminalText.safeURL(destination.url) else { throw APIError(message: "The controller returned an invalid preview link.", code: "invalid_preview") }
            browser = BrowserDestination(url: safe)
        } catch { notice = error.localizedDescription }
    }
    private func key(_ title: String?, key: String, symbol: String? = nil) -> some View {
        Button { Task { await sendKey(key) } } label: { Group { if let symbol { Image(systemName: symbol) } else { Text(title ?? key).font(.subheadline) } }.frame(minWidth: 44, minHeight: 44) }.disabled(!canSend).accessibilityLabel(title ?? key)
    }
    private func refreshOutput(force: Bool = false) async {
        guard !readingPaused || force else { return }
        guard model.isDemo || model.connected else { return }
        do { let next = try await model.output(for: agentId); guard !readingPaused || force else { return }; output = next; outputError = nil }
        catch { if !Task.isCancelled { outputError = error.localizedDescription } }
    }
    private func sendMessage() async {
        guard let agent, let output, canSend else { return }
        let sentMessage = message
        sending = true; defer { sending = false; uploadProgress = nil }
        do {
            if !photos.isEmpty {
                guard !agent.needsAttention, let client = model.client else { throw APIError(message: "Respond to the active question before sending photos.", code: "invalid_attachment") }
                for index in photos.indices where photos[index].uploadedId == nil {
                    uploadProgress = "Uploading photo \(index + 1) of \(photos.count) to \(agent.machineName)…"
                    let uploaded: UploadedPhoto = try await client.request("/api/agents/\(ControllerClient.agentPath(agentId))/attachments", method: "POST", body: ["contentType": "image/jpeg", "data": photos[index].data.base64EncodedString()])
                    photos[index].uploadedId = uploaded.id
                    PhotoDrafts.save(photos, scope: photoScope)
                }
            }
            uploadProgress = nil
            let operation = try await model.perform(path: "/api/agents/\(ControllerClient.agentPath(agentId))/actions", scope: agentId,
                body: ["type": agent.needsAttention ? "response" : "prompt", "text": sentMessage, "sequence": output.sequence, "attachments": photos.compactMap(\.uploadedId)])
            if operation.state == "accepted" { if message == sentMessage { message = ""; composing = false }; photos = []; await refreshOutput(); await model.refresh() }
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
        do { if let result = try await model.checkPending(agentId) { notice = result.message; if result.state == "accepted" { message = ""; photos = [] } }; await refreshOutput(force: true) }
        catch { notice = error.localizedDescription }
    }
}
