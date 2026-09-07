import SwiftUI
import UIKit
import SafariServices

struct TerminalRun: Codable { let text: String; var color: String?; var bold: Bool?; var dim: Bool?; var italic: Bool?; var underline: Bool?; var link: String? }

/// Terminal colours and emphasis survive transport. Reading mode removes
/// terminal-width rules/padding without interpreting output as executable HTML.
enum TerminalText {
    static func attributed(_ output: SessionOutput, monospaced: Bool) -> AttributedString {
        var result = AttributedString()
        for run in output.runs ?? [TerminalRun(text: output.text)] {
            var part = AttributedString(run.text)
            var font: Font = monospaced ? .system(.body, design: .monospaced) : .body
            if run.bold == true { font = font.bold() }
            if run.italic == true { font = font.italic() }
            part.font = font
            part.foregroundColor = color(run.color) ?? (run.dim == true ? Theme.secondary : .primary)
            if run.underline == true { part.underlineStyle = .single }
            if let link = run.link, let url = safeURL(link) { part.link = url; part.foregroundColor = Theme.mint; part.underlineStyle = .single }
            result += part
        }
        if !monospaced { result = compact(result) }
        // NSDataDetector preserves URL paths/query strings and ignores sentence punctuation.
        let plain = String(result.characters)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
                guard let destination = match.url, safeURL(destination.absoluteString) != nil,
                      let range = Range(match.range, in: plain),
                      let lower = AttributedString.Index(range.lowerBound, within: result),
                      let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
                if result[lower..<upper].runs.contains(where: { $0.link != nil }) { continue }
                result[lower..<upper].link = destination
                result[lower..<upper].foregroundColor = Theme.mint
                result[lower..<upper].underlineStyle = .single
            }
        }
        return result
    }
    static func safeURL(_ value: String) -> URL? {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func isLocal(_ url: URL) -> Bool {
        ["localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]"].contains(url.host?.lowercased() ?? "")
    }
    static func color(_ hex: String?) -> Color? {
        guard let hex, hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        // Keep dark terminal palette values legible on the app's graphite background.
        let components = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { $0 / 255 }
        func luminance(_ rgb: [Double]) -> Double {
            let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let background = luminance([17.0 / 255, 20.0 / 255, 19.0 / 255])
        var adjusted = components
        if (luminance(adjusted) + 0.05) / (background + 0.05) < 4.5 {
            var lower = 0.0, upper = 1.0
            for _ in 0..<12 {
                let blend = (lower + upper) / 2
                let candidate = components.map { $0 + (1 - $0) * blend }
                if (luminance(candidate) + 0.05) / (background + 0.05) < 4.5 { lower = blend } else { upper = blend }
            }
            adjusted = components.map { $0 + (1 - $0) * upper }
        }
        return Color(red: adjusted[0], green: adjusted[1], blue: adjusted[2])
    }
    static func compact(_ input: AttributedString) -> AttributedString {
        let plain = String(input.characters)
        var result = AttributedString(); var previousBlank = true
        for range in plain.lineRanges {
            let line = String(plain[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rule = line.count >= 4 && line.allSatisfy { "─━═_-—= │┄┈".contains($0) }
            if rule || line.isEmpty {
                if !previousBlank { result += AttributedString("\n\n"); previousBlank = true }
                continue
            }
            // Trim padding at the right only; code indentation remains intact.
            let source = plain[range].replacingOccurrences(of: "[ \\t\\r\\n]+$", with: "", options: .regularExpression)
            let trimmed = source.replacingOccurrences(of: "[─━═]{4,}$", with: "", options: .regularExpression).replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression)
            let end = plain.index(range.lowerBound, offsetBy: trimmed.count)
            guard let lower = AttributedString.Index(range.lowerBound, within: input), let upper = AttributedString.Index(end, within: input) else { continue }
            if !previousBlank { result += AttributedString("\n") }
            result += AttributedString(input[lower..<upper]); previousBlank = false
        }
        return result
    }
}
private extension String {
    var lineRanges: [Range<String.Index>] {
        var result: [Range<String.Index>] = []; var start = startIndex
        while start < endIndex { let end = self[start...].firstIndex(of: "\n").map { index(after: $0) } ?? endIndex; result.append(start..<end); start = end }
        return result
    }
}
struct SessionBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
struct BrowserDestination: Identifiable { let id = UUID(); let url: URL }
struct PreviewDestination: Decodable { let url: String }
