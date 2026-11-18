import SwiftUI
import UniformTypeIdentifiers

/// Arquivo CSV compartilhável via ShareLink.
struct CSVExport: Transferable {
    let fileName: String
    let content: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.fileName)
            try file.content.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
