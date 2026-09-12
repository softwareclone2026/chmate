import SwiftUI

/// スレ分析とAI要約（Geschar の ThreadAnalysis / Summarize 相当）。
struct ThreadToolsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var summary = ""
    @State private var busy = false
    @State private var error = ""

    private var stats: ThreadStatistics { ThreadAnalyzer.analyze(posts: model.posts, visible: model.visiblePosts) }

    var body: some View {
        NavigationStack {
            Form {
                Section("スレ分析") {
                    LabeledContent("総レス数", value: "\(stats.total)")
                    LabeledContent("表示中", value: "\(stats.visible)")
                    LabeledContent("ID数", value: "\(stats.uniqueIDs)")
                    LabeledContent("IDなし", value: "\(stats.idless)")
                    LabeledContent("アンカー", value: "\(stats.anchors)")
                    LabeledContent("画像", value: "\(stats.images)")
                    if stats.postsPerHour > 0 {
                        LabeledContent("勢い", value: String(format: "%.1f レス/時", stats.postsPerHour))
                    }
                    if let hour = stats.busiestHour {
                        LabeledContent("書き込みが多い時間帯", value: "\(hour)時台（\(stats.busiestHourCount)件）")
                    }
                }
                if !stats.topPosters.isEmpty {
                    Section("書き込みの多いID") {
                        ForEach(stats.topPosters) { item in
                            LabeledContent("ID:\(item.id)", value: "\(item.count)件")
                        }
                    }
                }
                Section("AI要約") {
                    Button(busy ? "要約中…" : "スレを要約") { Task { await run() } }
                        .disabled(busy || model.posts.isEmpty)
                    if busy { ProgressView("スレを読んで要約しています…") }
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                    if !summary.isEmpty {
                        Text(summary)
                        Button("書き込み下書きへ") {
                            NotificationCenter.default.post(name: .useAIDraft, object: summary)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("スレ分析・要約")
            .toolbar { Button("閉じる") { dismiss() } }
        }
    }

    @MainActor private func run() async {
        guard !busy else { return }
        busy = true; error = ""; summary = ""
        defer { busy = false }
        do {
            summary = try await AIService.summarize(title: model.selectedThread?.title ?? "", posts: model.posts)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 次スレ候補の一覧（Geschar の NextThreadTitleList 相当）。
struct NextThreadSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.nextThreads.isEmpty {
                    Text("次スレ候補は見つかりませんでした。板のスレ一覧を取得できているか確認してください。")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.nextThreads) { thread in
                    Button {
                        Task {
                            await model.select(thread.board)
                            await model.select(thread)
                        }
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(thread.title).lineLimit(2)
                            Text("\(thread.postCount)レス・勢い \(thread.speed)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("次スレ候補")
            .toolbar { Button("閉じる") { dismiss() } }
        }
    }
}
