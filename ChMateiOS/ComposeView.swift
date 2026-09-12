import SwiftUI

struct ComposeView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultPostName") private var name = ""
    @AppStorage("defaultPostMail") private var mail = "sage"
    @State private var message = ""
    @State private var status = ""
    @State private var sending = false
    @State private var restored = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("名前", text: $name)
                TextField("メール", text: $mail).textInputAutocapitalization(.never)
                TextEditor(text: $message).frame(minHeight: 220)
                if !status.isEmpty { Text(status).foregroundStyle(status.contains("完了") ? .green : .red) }
            }
            .navigationTitle("書き込み")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "送信中…" : "送信") { Task { await send() } }.disabled(sending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { restoreDraft() }
        .onChange(of: message) { _, _ in saveDraft() }
        .onChange(of: name) { _, _ in saveDraft() }
        .onChange(of: mail) { _, _ in saveDraft() }
        .onReceive(NotificationCenter.default.publisher(for: .replyToPost)) { note in if let number=note.object as? Int { message += message.isEmpty ? ">>\(number)\n" : "\n>>\(number)\n" } }
        .onReceive(NotificationCenter.default.publisher(for: .useAIDraft)) { note in if let text=note.object as? String { message=text } }
    }

    /// 前回の下書きがあれば復元する。無ければ本文だけ引き継ぐ。
    private func restoreDraft() {
        guard !restored else { return }
        restored = true
        if let draft = model.currentDraft {
            message = draft.message
            if !draft.name.isEmpty { name = draft.name }
            if !draft.mail.isEmpty { mail = draft.mail }
            status = "下書きを復元しました"
        } else if message.isEmpty {
            message = model.composeDraft
        }
    }

    private func saveDraft() {
        guard restored else { return }
        model.saveDraft(message: message, name: name, mail: mail)
    }

    private func send() async {
        sending = true; defer { sending = false }; status = ""
        do {
            let number = try await model.post(message:message,name:name,mail:mail)
            model.recordPost(number: number, message: message, name: name, mail: mail)
            status = number.map { "書き込み完了（\($0)番）" } ?? "書き込み完了"
            message = ""; model.composeDraft = ""; model.clearDraft()
        } catch { status = error.localizedDescription }
    }
}
