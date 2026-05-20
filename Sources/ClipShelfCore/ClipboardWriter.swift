import AppKit
import Foundation

public enum ClipboardWriter {
    public static func write(payloads: [ClipboardPayload], to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        for payload in payloads {
            item.setData(payload.data, forType: NSPasteboard.PasteboardType(payload.uti))
        }
        pasteboard.writeObjects([item])
    }

    public static func writePlainText(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
