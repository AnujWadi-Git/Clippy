import SwiftUI
import ClippyCore
import Carbon.HIToolbox

struct SettingsView: View {
    let ctx: AppContext
    var body: some View {
        TabView {
            GeneralTab(ctx: ctx).tabItem { Label("General", systemImage: "gearshape") }
            ClipboardTab(ctx: ctx).tabItem { Label("Clipboard", systemImage: "clipboard") }
            PrivacyTab(ctx: ctx).tabItem { Label("Privacy", systemImage: "hand.raised") }
            AITab(ctx: ctx).tabItem { Label("AI", systemImage: "sparkles") }
            ShortcutsTab(ctx: ctx).tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AppearanceTab(ctx: ctx).tabItem { Label("Appearance", systemImage: "paintbrush") }
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 420)
    }
}

@MainActor private final class GeneralModel: ObservableObject {
    @Published var login = LoginItem.isEnabled
    @Published var axTrusted = PasteManager.hasAccessibility
}

private struct GeneralTab: View {
    @Bindable var settings: SettingsManager
    @StateObject private var m = GeneralModel()
    init(ctx: AppContext) { settings = ctx.settings }

    var body: some View {
        Form {
            Toggle("Launch Clippy at login", isOn: $m.login)
                .onChange(of: m.login) { _, v in if !LoginItem.set(v) { m.login = LoginItem.isEnabled } }
            if LoginItem.needsApproval {
                Text("Approve Clippy in System Settings → General → Login Items.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Paste automatically into the active app", isOn: $settings.pasteAutomatically)
            HStack {
                Image(systemName: m.axTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(m.axTrusted ? .green : .orange)
                Text(m.axTrusted ? "Accessibility access granted" : "Accessibility access needed to paste automatically")
                Spacer()
                if !m.axTrusted {
                    Button("Grant…") { PasteManager.requestAccessibility() }
                }
                Button("Recheck") { m.axTrusted = PasteManager.hasAccessibility }
            }
            Text("Without Accessibility, Clippy still copies the item — press ⌘V yourself. macOS offers no other way to insert text into another app.")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).padding()
    }
}

@MainActor private final class UsageModel: ObservableObject { @Published var usage = 0; @Published var message: String? }

struct ClipboardTab: View {
    @Bindable var settings: SettingsManager
    let ctx: AppContext
    @StateObject private var m = UsageModel()
    init(ctx: AppContext) { self.ctx = ctx; settings = ctx.settings }

    var body: some View {
        Form {
            Picker("Keep history for", selection: $settings.retention) {
                ForEach(RetentionPolicy.allCases) { Text($0.label).tag($0) }
            }
            Text("Pinned items never expire. Everything else is permanently deleted after this time.").font(.caption).foregroundStyle(.secondary)
            Stepper("Maximum history size: \(settings.maxItems) items", value: $settings.maxItems, in: 50...10_000, step: 50)
            Stepper("Maximum storage: \(settings.maxDiskMB) MB", value: $settings.maxDiskMB, in: 10...5_000, step: 50)
            Toggle("Ignore duplicate entries", isOn: $settings.ignoreDuplicates)
            LabeledContent("Currently using", value: ByteCountFormatter.string(fromByteCount: Int64(m.usage), countStyle: .file))
            Toggle("Read text in copied images (OCR, on-device)", isOn: $settings.ocrImages)
            Section("Backup") {
                HStack {
                    Button("Export Pinned…") { export(pinnedOnly: true) }
                    Button("Export All…") { export(pinnedOnly: false) }
                    Button("Import…") { importFile(m) }
                }
                if let msg = m.message { Text(msg).font(.caption).foregroundStyle(.secondary) }
                Text("Exports are plain, unencrypted JSON (text, links and files; not images). Keep them somewhere safe.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Clear History…", role: .destructive) { try? ctx.repository.clear() }
        }.formStyle(.grouped).padding()
        .onAppear { m.usage = ctx.repository.diskUsageBytes }
    }
}

extension ClipboardTab {
    @MainActor fileprivate func export(pinnedOnly: Bool) {
        let alert = NSAlert()
        alert.messageText = "Export clipboard history?"
        alert.informativeText = "The file will contain your clips as readable text, including pinned items that Clippy normally keeps encrypted. Store it somewhere safe."
        alert.addButton(withTitle: "Export…"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = pinnedOnly ? "Clippy Pinned.json" : "Clippy History.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try HistoryArchive.export(ctx.repository.snapshot(), pinnedOnly: pinnedOnly)
            try data.write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { NSAlert(error: error).runModal() }
    }

    @MainActor fileprivate func importFile(_ m: UsageModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let r = try HistoryArchive.importArchive(try Data(contentsOf: url), pipeline: ctx.pipeline, repository: ctx.repository)
            m.message = "Imported \(r.imported) (\(r.pinned) pinned), \(r.duplicates) already present, \(r.skipped) skipped by privacy filters."
        } catch { m.message = error.localizedDescription }
    }
}

private struct PrivacyTab: View {
    @Bindable var settings: SettingsManager
    init(ctx: AppContext) { settings = ctx.settings }

    var body: some View {
        Form {
            Toggle("Protect sensitive clipboard data", isOn: $settings.protectSensitive)
            Text("Passwords, API keys, tokens, private keys, card numbers, one-time codes and seed phrases are detected before saving and are never stored. This lowers risk but can't be perfect.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("When something sensitive is copied", selection: $settings.sensitiveMode) {
                Text("Ignore it completely").tag(SensitiveMode.drop)
                Text("Keep in memory for 60 seconds").tag(SensitiveMode.memoryOnly)
            }.disabled(!settings.protectSensitive)
            Toggle("Ignore password managers", isOn: $settings.ignorePasswordManagers)
            Section("Ignored apps") {
                if settings.ignoredApps.isEmpty { Text("None").foregroundStyle(.secondary) }
                ForEach(settings.ignoredApps, id: \.self) { b in
                    HStack { Text(b).font(.system(size: 12, design: .monospaced)); Spacer()
                        Button { settings.ignoredApps.removeAll { $0 == b } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless) }
                }
                Button("Add App…") { addApp() }
            }
        }.formStyle(.grouped).padding()
    }

    private func addApp() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]; p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let url = p.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !settings.ignoredApps.contains(id) { settings.ignoredApps.append(id) }
    }
}

@MainActor private final class AIModel: ObservableObject {
    @Published var keyDraft = ""
    @Published var hasKey = false
    @Published var indexed = 0
}

private struct AITab: View {
    @Bindable var settings: SettingsManager
    let ctx: AppContext
    @StateObject private var m = AIModel()
    init(ctx: AppContext) { self.ctx = ctx; settings = ctx.settings }

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI features", isOn: $settings.aiEnabled)
                    .onChange(of: settings.aiEnabled) { _, _ in ctx.semanticSearchChanged() }
                Toggle("Prefer on-device AI", isOn: $settings.preferLocalAI).disabled(!settings.aiEnabled)
                LabeledContent("On-device model") {
                    if let why = LocalAIService().unavailableReason() {
                        Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                    } else { Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            } footer: {
                Text("AI only runs when you ask: rewrite, summarize, explain, convert. Sensitive items are never sent to any model.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Semantic search") {
                Toggle("Search by meaning (on-device)", isOn: $settings.semanticSearch).disabled(!settings.aiEnabled)
                    .onChange(of: settings.semanticSearch) { _, _ in ctx.semanticSearchChanged() }
                LabeledContent("Indexed items", value: "\(m.indexed)")
                Toggle("Suggest pinning things I copy often", isOn: $settings.pinSuggestions)
                Toggle("Clean up junk early (stray punctuation, tracking redirects)", isOn: $settings.cleanJunk)
            }
            Section {
                Toggle("Allow cloud processing", isOn: $settings.allowCloudProcessing).disabled(!settings.aiEnabled)
                if settings.allowCloudProcessing {
                    TextField("Model", text: $settings.cloudModel).font(.system(size: 12, design: .monospaced))
                    HStack {
                        SecureField(m.hasKey ? "API key saved in Keychain" : "Anthropic API key", text: $m.keyDraft)
                        Button("Save") { ctx.keychain.set(m.keyDraft, for: settings.cloudProvider); m.keyDraft = ""; m.hasKey = true }
                            .disabled(m.keyDraft.isEmpty)
                        if m.hasKey { Button("Remove") { ctx.keychain.delete(settings.cloudProvider); m.hasKey = false } }
                    }
                    Text("When used, ONLY the single item you chose is sent to Anthropic, and only if on-device AI is unavailable or you turned off “Prefer on-device”. Search never sends anything.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Cloud (off by default)") }
        }
        .formStyle(.grouped).padding()
        .onAppear { m.hasKey = ctx.keychain.get(settings.cloudProvider) != nil; m.indexed = ctx.semanticIndex.count }
    }
}

@MainActor private final class RecorderModel: ObservableObject {
    @Published var recording = false
    @Published var failed = false
    var monitor: Any?
}

private struct ShortcutsTab: View {
    let ctx: AppContext
    @Bindable var settings: SettingsManager
    @StateObject private var m = RecorderModel()
    init(ctx: AppContext) { self.ctx = ctx; settings = ctx.settings }

    var body: some View {
        Form {
            LabeledContent("Open Clippy") {
                Button(m.recording ? "Press shortcut…" : GlobalHotkeyManager.display(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)) {
                    m.recording ? stop() : start()
                }.frame(minWidth: 120)
            }
            if m.failed { Text("That shortcut couldn't be registered (already in use?).").font(.caption).foregroundStyle(.red) }
            Button("Reset to ⌥V") {
                settings.hotkeyKeyCode = SettingsManager.defaultHotkey.keyCode; settings.hotkeyModifiers = SettingsManager.defaultHotkey.modifiers
                m.failed = !ctx.registerHotkey()
            }
            LabeledContent("Skip my next copy", value: "⌥⇧V")
            Section("In the panel") {
                ForEach([("↑ ↓", "Navigate"), ("↩", "Paste"), ("⌥↩", "Paste as plain text"), ("⌘↩", "Copy only"), ("⌘K", "Actions"),
                         ("⌘P", "Pin / unpin"), ("⌘⌫", "Delete"), ("⌘1–9", "Quick paste"), ("⇥", "Next filter"), ("⎋", "Clear search / close")], id: \.0) { k in
                    LabeledContent(k.0, value: k.1)
                }
            }
        }.formStyle(.grouped).padding()
        .onDisappear { stop() }
    }

    private func start() {
        m.recording = true; m.failed = false
        m.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }
            let mods = GlobalHotkeyManager.carbonModifiers(from: e.modifierFlags.intersection(.deviceIndependentFlagsMask))
            guard mods != 0 else { return nil }   // require a modifier so typing isn't hijacked
            let (oldK, oldM) = (settings.hotkeyKeyCode, settings.hotkeyModifiers)
            settings.hotkeyKeyCode = Int(e.keyCode); settings.hotkeyModifiers = mods
            if !ctx.registerHotkey() {
                settings.hotkeyKeyCode = oldK; settings.hotkeyModifiers = oldM; ctx.registerHotkey(); m.failed = true
            }
            stop(); return nil
        }
    }
    private func stop() {
        m.recording = false
        if let mon = m.monitor { NSEvent.removeMonitor(mon); m.monitor = nil }
    }
}

private struct AppearanceTab: View {
    @Bindable var settings: SettingsManager
    let ctx: AppContext
    init(ctx: AppContext) { self.ctx = ctx; settings = ctx.settings }
    var body: some View {
        Form {
            Picker("Appearance", selection: $settings.appearance) {
                Text("System").tag(AppearanceMode.system); Text("Light").tag(AppearanceMode.light); Text("Dark").tag(AppearanceMode.dark)
            }.pickerStyle(.segmented)
            .onChange(of: settings.appearance) { _, _ in ctx.applyAppearance() }
        }.formStyle(.grouped).padding()
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.clipboard").font(.system(size: 44)).foregroundStyle(Color.accentColor)
            Text("Clippy").font(.title.bold())
            Text("Copy once. Find it again.").foregroundStyle(.secondary)
            Text("Version 0.1.0").font(.caption).foregroundStyle(.tertiary)
            Text("Your clipboard remembers enough to be useful, but forgets quickly enough to stay private.")
                .multilineTextAlignment(.center).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 40).padding(.top, 8)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
