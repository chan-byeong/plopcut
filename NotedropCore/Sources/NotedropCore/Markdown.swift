import Foundation

/// Markdown export (spec section 7). Writing the file is the caller's job so cancelling writes nothing.
public enum MarkdownExport {
    public static func fileName(for drop: Drop) -> String { Naming.slug(drop.title) + ".md" }

    public static func render(_ drop: Drop) -> String {
        var out = "# \(drop.title)\n\n## Metadata\n\n"
        out += "- Type: \(drop.type.rawValue)\n- Created: \(drop.createdAt)\n- Updated: \(drop.updatedAt)\n"
        if !drop.tags.isEmpty { out += "- Tags: \(drop.tags.joined(separator: ", "))\n" }
        let lines: [(String, String?)] = [
            ("App", drop.source.appName), ("Window", drop.source.windowTitle),
            ("URL", drop.source.url), ("File", drop.source.filePath),
        ]
        for (label, value) in lines {
            if let value = value?.trimmedNonEmpty { out += "- \(label): \(value)\n" }
        }
        if let text = drop.text?.trimmedNonEmpty { out += "\n## Text\n\n\(text)\n" }
        if let note = drop.note?.trimmedNonEmpty { out += "\n## Note\n\n\(note)\n" }
        return out
    }
}
