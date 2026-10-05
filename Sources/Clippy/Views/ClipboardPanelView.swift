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

struct ClipboardPanelView: View {
    @Bindable var vm: PanelViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            FilterBar(vm: vm)
            Divider().opacity(0.5)
            HStack(spacing: 0) {
                list.frame(width: 330)
                Divider().opacity(0.5)
                PreviewPane(item: vm.selectedItem, repo: vm.repo)
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 720, height: 470)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        .overlay(alignment: .topTrailing) { if vm.actionsOpen, let item = vm.selectedItem { ActionsMenu(vm: vm, item: item).padding(.top, 96).padding(.trailing, 16) } }
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

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(.secondary)
            TextField("Search clipboard", text: $vm.query)
                .textFieldStyle(.plain).font(.system(size: 18)).focused($searchFocused)
            if vm.settings.monitoringPaused {
                Label("Paused", systemImage: "pause.circle.fill").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if vm.results.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 2, pinnedViews: []) {
                        ForEach(vm.rows) { row in
                            switch row {
                            case .header(let t):
                                Text(t.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
                            case .item(let item, let idx):
                                ItemRow(item: item, selected: idx == vm.selection, shortcutIndex: idx < 9 ? idx + 1 : nil, repo: vm.repo)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { vm.selection = idx; vm.onPaste?(item, false, false) }
                            }
                        }
                    }
                    .padding(6)
                }
            }
            .onChange(of: vm.selection) { _, _ in
                if let id = vm.selectedItem?.id { proxy.scrollTo(id) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: vm.query.isEmpty ? "clipboard" : "magnifyingglass").font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(vm.query.isEmpty ? "Nothing copied yet" : "No matching clipboard item found.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            if vm.query.isEmpty {
                Text("Items disappear after \(vm.settings.retention.label.lowercased()) unless pinned.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }.frame(maxWidth: .infinity).padding(.top, 90)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↩", "Paste"); hint("⌘K", "Actions"); hint("⌘P", "Pin"); hint("⌘⌫", "Delete"); hint("⇥", "Filter")
            Spacer()
            Text("\(vm.results.count) item\(vm.results.count == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(.tertiary)
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

extension Notification.Name { static let clippyPanelDidShow = Notification.Name("clippyPanelDidShow") }

struct FilterBar: View {
    @Bindable var vm: PanelViewModel
    var body: some View {
        HStack(spacing: 4) {
            ForEach(ClipFilter.allCases) { f in
                Button { vm.filter = f } label: {
                    Text(f.rawValue).font(.system(size: 11.5, weight: vm.filter == f ? .semibold : .regular))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(vm.filter == f ? Color.accentColor.opacity(0.22) : .clear, in: Capsule())
                        .foregroundStyle(vm.filter == f ? Color.accentColor : .secondary)
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
    }
}

struct ActionsMenu: View {
    @Bindable var vm: PanelViewModel
    let item: ClipboardItem
    var body: some View {
        let actions = vm.availableActions(for: item)
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { i, a in
                HStack(spacing: 8) {
                    Image(systemName: a.symbol).frame(width: 16).foregroundStyle(a == .delete ? .red : .secondary)
                    Text(a.rawValue).font(.system(size: 13)).foregroundStyle(a == .delete ? .red : .primary)
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(i == vm.actionSelection ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture { vm.perform(a, on: item) }
            }
        }
        .padding(6).frame(width: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}
