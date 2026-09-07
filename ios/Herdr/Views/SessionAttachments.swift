import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

struct SessionPhoto: Identifiable {
    let id: UUID
    init(id: UUID = UUID(), data: Data, image: UIImage, uploadedId: String? = nil) { self.id = id; self.data = data; self.image = image; self.uploadedId = uploadedId }
    let data: Data
    let image: UIImage
    var uploadedId: String?
    static func prepare(_ data: Data) throws -> SessionPhoto {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400
              ] as CFDictionary) else { throw APIError(message: "This image could not be opened. Choose another photo.", code: "invalid_attachment") }
        let image = UIImage(cgImage: thumbnail)
        guard let encoded = image.jpegData(compressionQuality: 0.85), encoded.count <= 3 * 1024 * 1024 else {
            throw APIError(message: "This image is too large. Choose a smaller photo.", code: "invalid_attachment")
        }
        return SessionPhoto(data: encoded, image: image)
    }
}
struct UploadedPhoto: Decodable { let id: String; let machineName: String }

struct PhotoStrip: View {
    let photos: [SessionPhoto]
    let disabled: Bool
    let remove: (UUID) -> Void
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    HStack(spacing: 4) {
                        Image(uiImage: photo.image).resizable().scaledToFit().frame(width: 64, height: 64)
                            .accessibilityLabel("Attached photo \(index + 1)")
                        Button { remove(photo.id) } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                            .accessibilityLabel("Remove photo \(index + 1)").disabled(disabled)
                    }
                }
            }
        }.frame(height: 68)
    }
}

// Photo drafts stay in the app sandbox, excluded from device backups.
enum PhotoDrafts {
    private struct Saved: Codable { let id: UUID; let data: Data; let uploadedId: String? }
    private static func file(_ scope: String) throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PhotoDrafts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory.appendingPathComponent(Data(scope.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_") + ".json")
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }
    static func load(_ scope: String) -> [SessionPhoto] {
        guard let url = try? file(scope), let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([Saved].self, from: data) else { return [] }
        return saved.prefix(3).compactMap { item in UIImage(data: item.data).map { SessionPhoto(id: item.id, data: item.data, image: $0, uploadedId: item.uploadedId) } }
    }
    static func save(_ photos: [SessionPhoto], scope: String) {
        guard var url = try? file(scope) else { return }
        if photos.isEmpty { try? FileManager.default.removeItem(at: url); return }
        guard let data = try? JSONEncoder().encode(photos.map { Saved(id: $0.id, data: $0.data, uploadedId: $0.uploadedId) }) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try? url.setResourceValues(values)
    }
}
