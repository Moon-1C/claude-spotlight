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

    private var task: Task<Void, Never>?

    func reset() {
        query = ""
        results = []
        selection = 0
        answer = nil
        isAsking = false
    }

    func onQueryChange() {
        task?.cancel()
        answer = nil          // stale once the query changes
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

    /// Stage 2: ask the local Claude Code to re-rank the current candidates and synthesize an answer.
    func askClaude() {
        let q = query
        guard !results.isEmpty, !isAsking, !q.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isAsking = true
        answer = nil
        let snapshot = Array(results.prefix(40))
        let parsed = ParsedQuery.parse(q)
        let reasoner = Prefs.reasoner()   // honor current model setting
        Task { [weak self] in
            let r = await reasoner.rank(query: parsed, candidates: snapshot)
            await MainActor.run {
                guard let self, self.query == q else { return }   // ignore if the query moved on
                if let r {
                    self.results = SearchEngine.reorder(self.results, by: r.orderedIDs)
                    self.selection = 0
                    self.answer = r.answer ?? "Ranked by Claude."
                } else {
                    self.answer = "Claude ranking unavailable — showing local results."
                }
                self.isAsking = false
            }
        }
    }

    func openSelected() {
        guard results.indices.contains(selection) else { return }
        let c = results[selection]
        if let p = c.path {
            NSWorkspace.shared.open(URL(fileURLWithPath: p))
        } else if let u = c.uri, let url = URL(string: u) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct CommandView: View {
    @ObservedObject var vm: SearchViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
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

            // Stage-2 status / synthesized answer
            if vm.isAsking || vm.answer != nil {
                Divider().opacity(0.5)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                    if vm.isAsking {
                        Text("Asking Claude…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else if let answer = vm.answer {
                        Text(answer)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
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
                    Text("\(vm.elapsedMs) ms · ↑↓ navigate · ↩ open · ⌘↩ ask Claude · esc close")
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
        case .calendar: return "calendar"
        case .contact: return "person.crop.circle"
        default: return "sparkle"
        }
    }
}
