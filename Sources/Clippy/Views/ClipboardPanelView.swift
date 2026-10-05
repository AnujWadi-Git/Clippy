import SwiftUI
import ClippyCore

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = .behindWindow; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

extension Notification.Name { static let clippyPanelDidShow = Notification.Name("clippyPanelDidShow") }

struct ClipboardPanelView: View {
    @Bindable var vm: PanelViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if vm.isCommandMode { commandHeader } else { FilterBar(vm: vm) }
            Divider().opacity(0.5)
            HStack(spacing: 0) {
                list.frame(width: 330)
                Divider().opacity(0.5)
                PreviewPane(vm: vm)
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 720, height: 470)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        .overlay(alignment: .topTrailing) {
            if vm.actionsOpen, let item = vm.selectedItem { ActionsMenu(vm: vm, item: item).padding(.top, 60).padding(.trailing, 16) }
        }
        .overlay(alignment: .bottom) {
            if let t = vm.toast {
                Text(t).font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule()).padding(.bottom, 40).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: vm.actionsOpen)
        .animation(.easeOut(duration: 0.12), value: vm.toast)
        .onAppear { searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .clippyPanelDidShow)) { _ in searchFocused = true }
    }

    @ViewBuilder private var panelBackground: some View {
        if Brand.exporting { PanelExportBackground() } else { VisualEffectBackground() }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: vm.isCommandMode ? "chevron.right.square" : (vm.smartActive ? "sparkle.magnifyingglass" : "magnifyingglass"))
                .font(.system(size: 16, weight: .medium)).foregroundStyle(vm.smartActive || vm.isCommandMode ? Brand.accent : .secondary)
            if Brand.exporting {
                Text(vm.query.isEmpty ? "Search, ask (“?”), or run a command (“>”)" : vm.query)
                    .font(.system(size: 18)).foregroundStyle(vm.query.isEmpty ? .secondary : .primary).lineLimit(1)
                Spacer(minLength: 0)
            } else {
                TextField("Search, ask (“?”), or run a command (“>”)", text: $vm.query)
                    .textFieldStyle(.plain).font(.system(size: 18)).focused($searchFocused)
            }
            if vm.busy != nil { ProgressView().controlSize(.small) }
            if vm.settings.monitoringPaused {
                Label("Paused", systemImage: "pause.circle.fill").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private var commandHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right").font(.system(size: 10)).foregroundStyle(.tertiary)
            Text("Run on").font(.system(size: 11)).foregroundStyle(.tertiary)
            Text(vm.commandTarget?.preview.prefix(60).description ?? "nothing copied yet")
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }.padding(.horizontal, 16).padding(.bottom, 8)
    }

    @ViewBuilder private var list: some View {
        if Brand.exporting {
            listContent.frame(height: 345, alignment: .top).clipped()   // fixed viewport: no scroll in export
        } else {
            ScrollViewReader { proxy in
                ScrollView { listContent }
                    .onChange(of: vm.selection) { _, _ in scrollToSelection(proxy) }
            }
        }
    }

    @ViewBuilder private var listContent: some View {
        if vm.isCommandMode && vm.commandResults.isEmpty {
            emptyState(icon: "chevron.right.square", title: vm.commandTarget == nil ? "Copy something first" : "No matching command",
                       subtitle: vm.aiAvailable ? nil : vm.aiUnavailableReason)
        } else if !vm.isCommandMode && vm.results.isEmpty {
            emptyState(icon: vm.query.isEmpty ? "clipboard" : "magnifyingglass",
                       title: vm.query.isEmpty ? "Nothing copied yet" : (vm.refining ? "Looking with on-device AI…" : "No matching clipboard item found."),
                       subtitle: vm.query.isEmpty ? "Items disappear after \(vm.settings.retention.label.lowercased()) unless pinned." : nil)
        } else if Brand.exporting {
            VStack(spacing: 2) {
                if let s = vm.pinSuggestion { PinSuggestionBanner(item: s, vm: vm) }
                if vm.smartActive && (!vm.results.isEmpty || vm.refining) { smartChip }
                ForEach(vm.rows) { row in rowView(row) }
            }.padding(6).frame(maxHeight: .infinity, alignment: .top)
        } else {
            LazyVStack(spacing: 2) {
                if let s = vm.pinSuggestion { PinSuggestionBanner(item: s, vm: vm) }
                if vm.smartActive && (!vm.results.isEmpty || vm.refining) { smartChip }
                ForEach(vm.rows) { row in rowView(row) }
            }.padding(6)
        }
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        if vm.isCommandMode {
            if vm.commandResults.indices.contains(vm.selection) { proxy.scrollTo("c:" + vm.commandResults[vm.selection].title) }
        } else if let id = vm.selectedItem?.id { proxy.scrollTo(id) }
    }

    @ViewBuilder private func rowView(_ row: PanelRow) -> some View {
        switch row {
        case .header(let t):
            Text(t.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
        case .item(let item, let idx, let similar, let nested):
            ItemRow(item: item, selected: idx == vm.selection, shortcutIndex: idx < 9 ? idx + 1 : nil, similar: similar, nested: nested, mark: vm.markIndex(of: item), repo: vm.repo)
                .id(item.id)
                .contentShape(Rectangle())
                .onTapGesture { vm.selection = idx; vm.onPaste?(item, false, false) }
        case .command(let action, let idx):
            CommandRow(action: action, selected: idx == vm.selection)
                .id("c:" + action.title)
                .contentShape(Rectangle())
                .onTapGesture { if let t = vm.commandTarget { vm.perform(action, on: t) } }
        }
    }

    private var smartChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles").font(.system(size: 10))
            Text("Smart results from your clipboard history").font(.system(size: 11))
            Spacer()
            if vm.refining { ProgressView().controlSize(.mini); Text("Refining on-device…").font(.system(size: 10)).foregroundStyle(.secondary) }
        }.foregroundStyle(Brand.accent).padding(.horizontal, 10).padding(.vertical, 4)
    }

    private func emptyState(icon: String, title: String, subtitle: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.tertiary).multilineTextAlignment(.center) }
        }.frame(maxWidth: .infinity).padding(.top, 90).padding(.horizontal, 20)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if let b = vm.busy {
                Text(b).font(.system(size: 11)).foregroundStyle(.secondary)
            } else if vm.isCommandMode {
                hint("↩", "Run"); hint("⎋", "Back")
            } else {
                if vm.marked.count > 1 { hint("↩", "Paste \(vm.marked.count) together"); hint("⎋", "Unmark") } else { hint("↩", "Paste"); hint("⌘K", "Actions"); hint("⌘P", "Pin"); hint("⌘E", "Mark"); hint("⇥", "Filter") }
                if vm.hasSimilar { hint("→", "Similar") }
            }
            Spacer()
            if !vm.isCommandMode { Text("\(vm.results.count) item\(vm.results.count == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 10, weight: .medium, design: .rounded)).padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

struct FilterBar: View {
    @Bindable var vm: PanelViewModel
    var body: some View {
        HStack(spacing: 4) {
            ForEach(ClipFilter.allCases) { f in
                Button { vm.filter = f } label: {
                    Text(f.rawValue).font(.system(size: 11.5, weight: vm.filter == f ? .semibold : .regular))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(vm.filter == f ? Brand.accent.opacity(0.22) : .clear, in: Capsule())
                        .foregroundStyle(vm.filter == f ? Brand.accent : .secondary)
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
    }
}

struct PinSuggestionBanner: View {
    let item: ClipboardItem
    let vm: PanelViewModel
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pin.circle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Copied \(item.copyCount) times — pin it?").font(.system(size: 12, weight: .medium))
                Text(item.preview).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Pin") { vm.acceptPinSuggestion() }.controlSize(.small).buttonStyle(.borderedProminent)
            Button { vm.dismissPinSuggestion() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.bottom, 4)
    }
}

struct CommandRow: View {
    let action: ItemAction
    let selected: Bool
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: action.symbol).frame(width: 22).foregroundStyle(action.isDestructive ? .red : (selected ? Brand.accent : .secondary))
            Text(action.title).font(.system(size: 13)).foregroundStyle(action.isDestructive ? .red : .primary)
            Spacer()
            if action.isAI { Image(systemName: "sparkles").font(.system(size: 10)).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(selected ? Brand.accent.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PanelExportBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { (scheme == .dark ? Color(white: 0.12) : Color(white: 0.975)).opacity(0.97) }
}

struct ActionsMenu: View {
    @Bindable var vm: PanelViewModel
    let item: ClipboardItem
    @Environment(\.colorScheme) private var scheme

    private func rows(_ actions: [ItemAction]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(actions.enumerated()), id: \.offset) { i, a in
                HStack(spacing: 8) {
                    Image(systemName: a.symbol).frame(width: 16).foregroundStyle(a.isDestructive ? .red : (a.isAI ? Brand.accent : .secondary))
                    Text(a.title).font(.system(size: 13)).foregroundStyle(a.isDestructive ? .red : .primary)
                    Spacer()
                    if a.isAI { Image(systemName: "sparkles").font(.system(size: 9)).foregroundStyle(.tertiary) }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(i == vm.actionSelection ? Brand.accent.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .id(i)
                .onTapGesture { vm.perform(a, on: item) }
            }
        }.padding(6)
    }

    var body: some View {
        let actions = vm.availableActions(for: item)
        Group {
            if Brand.exporting {
                rows(actions)
            } else {
                ScrollViewReader { proxy in
                    ScrollView { rows(actions) }
                        .onChange(of: vm.actionSelection) { _, n in proxy.scrollTo(n) }
                }
            }
        }
        .frame(width: 240, height: min(CGFloat(actions.count) * 28 + 12, 330))
        .background {
            if Brand.exporting { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(scheme == .dark ? Color(white: 0.17) : Color.white) }
            else { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial) }
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(scheme == .dark ? .white.opacity(0.12) : .black.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}
