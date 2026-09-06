import SwiftUI

struct PairView: View {
    @EnvironmentObject private var model: AppModel
    @State private var connecting = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("herdr").font(.largeTitle.bold()).foregroundStyle(Theme.mint).padding(.top, 28)
                Image(systemName: "iphone.and.arrow.forward").font(.system(size: 60, weight: .light)).foregroundStyle(Theme.mint).padding(.vertical, 16).accessibilityHidden(true)
                Text("Your agents.\nWithin reach.").font(.largeTitle.bold())
                Text("Connect to your Mac to see what’s running, reply to agents and receive updates wherever you are.").font(.body).foregroundStyle(Theme.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Mac controller").font(.headline)
                    TextField("https://your-mac.ts.net:8443", text: $model.pairingServer).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("controllerURL")
                    Text("Pairing code").font(.headline).padding(.top, 8)
                    TextField("10-character code", text: $model.pairingCode).keyboardType(.asciiCapable).textInputAutocapitalization(.characters).autocorrectionDisabled().padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("pairingCode")
                    if let error { Notice(text: error, symbol: "exclamationmark.circle") }
                    Button { Task { connecting = true; defer { connecting = false }; do { try await model.pair() } catch { self.error = error.localizedDescription } } } label: {
                        HStack { if connecting { ProgressView().tint(Theme.background) }; Text(connecting ? "Connecting…" : model.connection == nil ? "Connect to Mac" : "Pair with this controller"); Spacer(); Image(systemName: "arrow.right") }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(connecting || model.pairingCode.isEmpty)
                }
                if let url = try? ControllerClient.validatedURL(model.pairingServer) {
                    Link("Get a pairing code", destination: url.appendingPathComponent("connect")).font(.headline).padding(.vertical, 6)
                }
                Text("Keep Tailscale connected on both devices. Create a code on the pairing page, then return here. Your agent accounts stay signed in on their computers.").font(.footnote).foregroundStyle(Theme.secondary)
                if model.connection == nil { Button("Explore the design with sample data") { model.enableDemo() }.font(.subheadline).padding(.vertical, 8) }
            }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.herdrScreen()
    }
}
