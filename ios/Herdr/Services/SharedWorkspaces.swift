import Foundation

extension AppModel {
    func clearSharedWorkspaceRecovery() {
        pendingSharedChange = nil
        UserDefaults.standard.removeObject(forKey: "pendingSharedChange")
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("workspaceAgentDraft-") { UserDefaults.standard.removeObject(forKey: key) }
    }
    var sharedCatalog: SharedWorkspaceCatalog? { state?.sharedWorkspaceCatalog }
    var sharedWorkspaces: [SharedWorkspace] { sharedCatalog?.workspaces ?? [] }
    var canEditSharedWorkspaces: Bool { (connected || isDemo) && sharedCatalog?.available == true && sharedCatalog?.stale == false && !sharedBusy && pendingSharedChange == nil }
    func isAssigned(_ agent: Agent) -> Bool { sharedWorkspaces.contains { $0.members.contains { $0.matches(agent) } } }
    func sharedWorkspace(_ id: String) -> SharedWorkspace? { sharedWorkspaces.first { $0.id == id } }

    @discardableResult
    func changeSharedWorkspace(_ action: String, id: String? = nil, label: String? = nil, member: SharedMember? = nil) async throws -> String? {
        guard canEditSharedWorkspaces else { throw APIError(message: "Reconnect or finish the pending workspace change first.", code: "workspace_unavailable") }
        let change = SharedChange(requestId: UUID().uuidString.lowercased(), expectedRevision: sharedCatalog?.revision ?? 0, action: action, id: id, label: label, member: member)
        if isDemo {
            guard var catalog = state?.sharedWorkspaceCatalog else { return nil }
            var resultID = id
            if action == "create" { resultID = change.requestId; catalog.workspaces.append(SharedWorkspace(id: change.requestId, label: label ?? "Workspace", members: [])) }
            else if action == "delete" { catalog.workspaces.removeAll { $0.id == id } }
            else if let index = catalog.workspaces.firstIndex(where: { $0.id == id }) {
                if action == "rename", let label { catalog.workspaces[index].label = label }
                if action == "add", let member, !catalog.workspaces[index].members.contains(member) { catalog.workspaces[index].members.append(member) }
                if action == "remove", let member { catalog.workspaces[index].members.removeAll { $0 == member } }
            }
            catalog.revision += 1; state?.sharedWorkspaceCatalog = catalog
            return resultID
        }
        pendingSharedChange = change
        UserDefaults.standard.set(try JSONEncoder().encode(change), forKey: "pendingSharedChange")
        return try await resumeSharedWorkspaceChange()
    }

    func clearDefinitivelyRejectedSharedChange(_ error: Error) {
        guard let error = error as? APIError,
              ["invalid_request", "request_conflict"].contains(error.code) else { return }
        pendingSharedChange = nil
        UserDefaults.standard.removeObject(forKey: "pendingSharedChange")
    }

    @discardableResult
    func resumeSharedWorkspaceChange() async throws -> String? {
        guard let change = pendingSharedChange, let client, connected, !sharedBusy else { throw APIError(message: "Reconnect to your Mac to check this workspace change.", code: "offline") }
        sharedBusy = true; defer { sharedBusy = false }
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(change)) as! [String: Any]
        let operation: Operation
        do { operation = try await client.request("/api/shared-workspaces/change", method: "POST", body: body) }
        catch {
            clearDefinitivelyRejectedSharedChange(error)
            throw error
        }
        if ["accepted", "rejected"].contains(operation.state) {
            pendingSharedChange = nil
            UserDefaults.standard.removeObject(forKey: "pendingSharedChange")
        }
        await refresh()
        guard operation.state == "accepted" else { throw APIError(message: operation.message, code: operation.result?.code ?? "workspace_pending") }
        return operation.result?.sharedWorkspaceId
    }
}
