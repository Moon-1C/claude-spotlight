import SwiftUI
import AppKit
import CSpotKit

final class SearchViewModel: ObservableObject {
    @Published var query = "" { didSet { onQueryChange() } }   // drives search from the model itself
    @Published var results: [Candidate] = []
    @Published var selection = 0
    @Published var escalate = false
    @Published var elapsedMs = 0
    @Published var isAsking = false
    @Published var answer: String?
    @Published var toast: String?
    @Published var pendingAction: Action?   // a proposed mutating action awaiting ⏎ confirm
    private var pendingActionQuery: String? // the query the proposal was made for (staleness guard)
    @Published var context: AppContext?   // the running app the user was in when they opened the launcher
    @Published var axTrusted: Bool = AXReader.isTrusted
    private var contextPID: pid_t?

    private var current: Candidate? { results.indices.contains(selection) ? results[selection] : nil }

    /// Capture the context of the app that was frontmost before the launcher took focus.
    func captureContext(appName: String?, pid: pid_t?) {
        contextPID = pid
        Task { [weak self] in
            let ctx = await ContextCapture.capture(appName: appName)
            await MainActor.run { self?.context = ctx }
        }
    }

    func refreshAXState() { axTrusted = AXReader.isTrusted }

    func grantAccessibility() {
        AXReader.promptForTrust()
        AXReader.openAccessibilitySettings()
    }

    private var task: Task<Void, Never>?

    func reset() {
        query = ""
        results = []
        selection = 0
        answer = nil
        isAsking = false
        context = nil
        pendingAction = nil
    }

    func onQueryChange() {
        task?.cancel()
        answer = nil          // stale once the query changes
        pendingAction = nil   // a proposed action must never outlive the query it was made for
        let q = query
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []; selection = 0; return
        }
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 130_000_000)   // debounce
            if Task.isCancelled { return }
            guard let self else { return }
            let started = Date()
            let parsed = ParsedQuery.parse(q)
            let collector = CandidateCollector(sources: Prefs.liveSources())   // honor current settings
            let result = await collector.collect(parsed)
            if Task.isCancelled { return }
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            await MainActor.run {
                self.results = result.candidates
                self.selection = 0
                self.escalate = result.shouldEscalate
                self.elapsedMs = ms
            }
        }
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = max(0, min(results.count - 1, selection + delta))
    }

    /// Stage 2: ask the local Claude Code to re-rank candidates / answer / or propose an action.
    func askClaude() {
        let q = query
        guard !isAsking, !q.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isAsking = true
        answer = nil
        pendingAction = nil
        let snapshot = Array(results.prefix(40))
        let parsed = ParsedQuery.parse(q)
        let lightCtx = context
        let reasoner = Prefs.reasoner()   // honor current model setting
        Task { [weak self] in
            // Deep-read the captured app's content/selection now, targeting the app the user was in.
            var ctx = await ContextCapture.capture(appName: lightCtx?.app, deep: true) ?? lightCtx
            // Merge Accessibility-read selection/value when trusted (works across arbitrary apps).
            // weak self → self?.contextPID is pid_t??; flatten with `?? nil` before unwrapping.
            if AXReader.isTrusted, let pid = (await MainActor.run { self?.contextPID }) ?? nil,
               let ax = AXReader.snapshot(pid: pid) {
                if let sel = ax.selectedText, !sel.isEmpty { ctx?.selectionText = sel }
                if (ctx?.bodyText?.isEmpty ?? true), let val = ax.focusedValue { ctx?.bodyText = val }
            }
            let r = await reasoner.rank(query: parsed, candidates: snapshot, context: ctx)

            // Command → action
            if let action = r?.action {
                if action.requiresConfirm {
                    await MainActor.run {
                        guard let self, self.query == q else { return }
                        self.pendingAction = action          // show confirm band
                        self.pendingActionQuery = q
                        self.isAsking = false
                    }
                } else {
                    let outcome = await ActionExecutor().perform(action, confirmed: false)  // open/draft/copy
                    await MainActor.run {
                        guard let self, self.query == q else { return }
                        self.showToast(outcome.message)
                        self.isAsking = false
                    }
                }
                return
            }

            // Search → rerank + answer
            await MainActor.run {
                guard let self, self.query == q else { return }
                if let r {
                    self.results = SearchEngine.reorder(self.results, by: r.orderedIDs)
                    self.selection = 0
                    self.answer = r.answer ?? "Ranked by Claude."
                } else {
                    self.answer = "Claude unavailable — showing local results."
                }
                self.isAsking = false
            }
        }
    }

    /// The ONLY place a mutating action runs (confirmed:true). Wired to ⏎ on the confirm band.
    func confirmAction() {
        // Never confirm a proposal made for a query the user has since edited.
        guard let a = pendingAction, query == pendingActionQuery else { pendingAction = nil; return }
        pendingAction = nil
        isAsking = true
        Task { [weak self] in
            let outcome = await ActionExecutor().perform(a, confirmed: true)
            await MainActor.run { self?.isAsking = false; self?.showToast(outcome.message) }
        }
    }

    func cancelAction() {
        guard pendingAction != nil else { return }
        pendingAction = nil
        showToast("Cancelled")
    }

    func openSelected() {
        guard let c = current else { return }
        if let p = c.path {
            NSWorkspace.shared.open(URL(fileURLWithPath: p))
        } else if let u = c.uri, let url = URL(string: u) {
            NSWorkspace.shared.open(url)
        }
    }

    /// ⌘R — reveal the selected file/app in Finder.
    func revealSelected() {
        guard let c = current, let p = c.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
    }

    /// ⌘C — copy the selected item's path (or uri/title) to the clipboard.
    func copySelected() {
        guard let c = current else { return }
        let value = c.path ?? c.uri ?? c.title
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        showToast("Copied \(c.path != nil ? "path" : "value")")
    }

    private func showToast(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            if self?.toast == message { self?.toast = nil }
        }
    }
}

struct CommandView: View {
    @ObservedObject var vm: SearchViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Accessibility grant nudge (lets us read selected text / field value in any app)
            if !vm.axTrusted {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield").font(.system(size: 11)).foregroundStyle(.orange)
                    Text("Grant Accessibility to read selected text in any app")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Grant…") { vm.grantAccessibility() }
                        .controlSize(.small).buttonStyle(.borderless)
                }
                .padding(.horizontal, 18).padding(.top, 8)
            }

            // current running-app context chip
            if let ctx = vm.context {
                HStack(spacing: 6) {
                    Image(systemName: ctx.url != nil ? "globe" : "macwindow")
                        .font(.system(size: 11)).foregroundStyle(Color.accentColor)
                    Text(ctx.urlTitle ?? ctx.windowTitle ?? ctx.app)
                        .lineLimit(1).foregroundStyle(.primary)
                    Text("· \(ctx.app)").foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 2)
            }

            // search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search files…", text: $vm.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .focused($focused)
                if vm.isAsking {
                    ProgressView().controlSize(.small)
                } else if vm.escalate {
                    Text("⌘↩ ask Claude")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            // Action confirm band (mutating action proposed by Stage 2)
            if let action = vm.pendingAction {
                Divider().opacity(0.5)
                HStack(spacing: 10) {
                    Image(systemName: actionIcon(action.kind))
                        .font(.system(size: 16))
                        .foregroundStyle(action.destructive ? .red : Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(action.preview).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        Text("⏎ confirm · esc cancel")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background((action.destructive ? Color.red : Color.accentColor).opacity(0.08))
            }

            // Toast (copy feedback) / Stage-2 status / synthesized answer
            if vm.pendingAction == nil, vm.toast != nil || vm.isAsking || vm.answer != nil {
                Divider().opacity(0.5)
                HStack(alignment: .top, spacing: 8) {
                    if let toast = vm.toast {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12)).foregroundStyle(.green)
                        Text(toast).font(.system(size: 12)).foregroundStyle(.primary)
                    } else if vm.isAsking {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12)).foregroundStyle(Color.accentColor)
                        Text("Asking Claude…").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else if let answer = vm.answer {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12)).foregroundStyle(Color.accentColor)
                        Text(answer).font(.system(size: 12)).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
            }

            if !vm.results.isEmpty {
                Divider().opacity(0.5)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(vm.results.enumerated()), id: \.element.id) { idx, candidate in
                                ResultRow(candidate: candidate, selected: idx == vm.selection)
                                    .id(idx)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        vm.selection = idx
                                        vm.openSelected()
                                    }
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: min(CGFloat(vm.results.count) * 46 + 16, 380))
                    .onChange(of: vm.selection) { proxy.scrollTo(vm.selection, anchor: .center) }
                }

                Divider().opacity(0.5)
                HStack {
                    Text("\(vm.results.count) results")
                    Spacer()
                    Text("\(vm.elapsedMs) ms · ↑↓ · ↩ open · ⌘R reveal · ⌘C copy · ⌘↩ ask · esc")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .frame(width: 720)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear { focused = true }
    }
}

func actionIcon(_ kind: ActionKind) -> String {
    switch kind {
    case .createNote, .appendNote: return "note.text"
    case .addCalendarEvent: return "calendar.badge.plus"
    case .addReminder: return "checklist"
    case .composeMail, .replyMail: return "envelope"
    case .sendMessage: return "message"
    case .openURL: return "safari"
    case .revealFile: return "folder"
    case .copyText: return "doc.on.doc"
    case .runShortcut: return "bolt"
    }
}

struct ResultRow: View {
    let candidate: Candidate
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(width: 26)
                .foregroundStyle(selected ? .white : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                if let subtitle = candidate.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(candidate.source.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? .white.opacity(0.9) : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .foregroundStyle(selected ? .white : .primary)
    }

    private var icon: String {
        switch candidate.source {
        case .file: return "doc"
        case .app: return "app"
        case .calendar: return "calendar"
        case .contact: return "person.crop.circle"
        default: return "sparkle"
        }
    }
}
