import SwiftUI

struct SavedPreview: Decodable, Identifiable { let id: String; let url: String; let port: Int; let machineName: String }
struct SavedPreviews: Decodable { let previews: [SavedPreview] }
struct PrivatePreviewsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var previews: [SavedPreview] = []
    @State private var error: String?
    @State private var removing: SavedPreview?
    @State private var browser: BrowserDestination?
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(Theme.attention) }
                if previews.isEmpty { Text("Tap a localhost link in a session to open a private preview here.").foregroundStyle(Theme.secondary) }
                ForEach(previews) { preview in
                    Button {
                        if let url = TerminalText.safeURL(preview.url) { browser = BrowserDestination(url: url) }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(preview.machineName) · Port \(preview.port)").font(.headline)
                            Text(preview.url).font(.footnote).foregroundStyle(Theme.mint)
                        }
                    }.swipeActions { Button("Stop sharing", role: .destructive) { removing = preview } }
                }
            }.navigationTitle("Private previews").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }.herdrScreen()
                .task { await refresh() }.refreshable { await refresh() }
                .sheet(item: $browser) { SessionBrowser(url: $0.url).ignoresSafeArea() }
                .confirmationDialog("Stop sharing this preview?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                    Button("Stop sharing", role: .destructive) { if let preview = removing { Task { await remove(preview) } } }
                } message: { Text("The development server keeps running. Its private preview link will stop working.") }
        }
    }
    private func refresh() async {
        guard let client = model.client, !model.isDemo else { return }
        do { let result: SavedPreviews = try await client.request("/api/previews"); previews = result.previews; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func remove(_ preview: SavedPreview) async {
        guard let client = model.client else { return }
        do { let _: EmptyResponse = try await client.request("/api/previews/\(preview.id)", method: "DELETE"); await refresh() }
        catch { self.error = error.localizedDescription }
    }
}
