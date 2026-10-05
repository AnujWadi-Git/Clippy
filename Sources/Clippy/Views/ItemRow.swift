import SwiftUI
import ClippyCore

enum ClipStyle {
    static func symbol(_ i: ClipboardItem) -> String {
        switch i.category {
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .command: return "terminal"
        case .email: return "envelope"
        case .phone: return "phone"
        case .json: return "curlybraces"
        case .address: return "mappin.and.ellipse"
        case .path, .file: return "doc"
        case .image: return "photo"
        case .message: return "text.alignleft"
        case .other: return i.preview.hasPrefix("🔒") ? "lock" : "doc.text"
        }
    }
    static func relative(_ d: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(d))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }
    static func expiry(_ i: ClipboardItem, now: Date = Date()) -> String {
        if i.pinned { return "Pinned — never expires" }
        guard let e = i.expiresAt else { return "Never expires" }
        let s = Int(e.timeIntervalSince(now))
        if s <= 0 { return "Expiring now" }
        if s < 3600 { return "Deletes in \(max(1, s / 60))m" }
        if s < 86400 { return "Deletes in \(s / 3600)h \((s % 3600) / 60)m" }
        return "Deletes in \(s / 86400)d \((s % 86400) / 3600)h"
    }
}

struct ItemRow: View {
    let item: ClipboardItem
    let selected: Bool
    let shortcutIndex: Int?
    var similar: Int = 0
    var nested: Bool = false
    let repo: ClipboardRepository

    var body: some View {
        HStack(spacing: 9) {
            if nested { Image(systemName: "arrow.turn.down.right").font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 14) }
            leading.frame(width: 22, height: 22)
            Text(item.preview.isEmpty ? "(empty)" : item.preview)
                .font(item.category == .code || item.category == .command || item.category == .json
                      ? .system(size: 12.5, design: .monospaced) : .system(size: 13))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if similar > 0 {
                Text("+\(similar)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1).background(.quaternary, in: Capsule())
                    .help("Similar items — press → to expand")
            }
            if item.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.orange) }
            if let n = shortcutIndex, selected { Text("⌘\(n)").font(.system(size: 10, design: .rounded)).foregroundStyle(.tertiary) }
            else { Text(ClipStyle.relative(item.lastUsedAt)).font(.system(size: 11)).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder private var leading: some View {
        if item.kind == .image, let t = item.thumbPath, let data = repo.blobs.read(t), let img = NSImage(data: data) {
            Image(nsImage: img).resizable().scaledToFill().frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: ClipStyle.symbol(item)).font(.system(size: 13)).foregroundStyle(selected ? Color.accentColor : .secondary)
        }
    }
}

struct PreviewPane: View {
    let vm: PanelViewModel

    var body: some View {
        let item = vm.selectedItem
        VStack(alignment: .leading, spacing: 0) {
            if let item {
                Group {
                    if item.kind == .image, let n = item.blobPath, let d = vm.repo.blobs.read(n), let img = NSImage(data: d) {
                        Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            Text(String((item.text ?? item.preview).prefix(6000)))
                                .font(item.category == .code || item.category == .command || item.category == .json || item.category == .path
                                      ? .system(size: 12, design: .monospaced) : .system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .topLeading).padding(14)
                        }
                    }
                }.frame(maxHeight: .infinity)
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 3) {
                    if let why = vm.selectedReason, !why.isEmpty {
                        HStack(spacing: 4) { Image(systemName: "sparkles").font(.system(size: 9)); Text("Matched: \(why)") }
                            .font(.system(size: 11)).foregroundStyle(Color.accentColor).padding(.bottom, 2)
                    }
                    meta("Type", item.category.rawValue.capitalized)
                    if let s = item.sourceName { meta("From", s) }
                    meta("Copied", ClipStyle.relative(item.lastUsedAt) + (item.copyCount > 1 ? " · \(item.copyCount)×" : ""))
                    meta("Size", ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file))
                    Text(ClipStyle.expiry(item)).font(.system(size: 11)).foregroundStyle(item.pinned ? Color.orange : Color.secondary).padding(.top, 2)
                }.padding(12)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func meta(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.tertiary).frame(width: 50, alignment: .leading); Text(v).foregroundStyle(.secondary); Spacer() }
            .font(.system(size: 11))
    }
}
