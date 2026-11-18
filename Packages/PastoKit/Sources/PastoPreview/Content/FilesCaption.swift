import Foundation

/// The line under a files preview.
nonisolated enum FilesCaption {
    /// The path of a single file, or `multipleFilesTitle` for any other number of them, followed
    /// by the size when it is known and not zero.
    static func text(paths: [String], totalByteCount: Int64?, multipleFilesTitle: String) -> String {
        var parts = [paths.count == 1 ? paths[0] : multipleFilesTitle]
        if let totalByteCount, totalByteCount >= 1 {
            parts.append(totalByteCount.formatted(.byteCount(style: .file)))
        }
        return parts.joined(separator: PreviewMetrics.footerSeparator)
    }
}
