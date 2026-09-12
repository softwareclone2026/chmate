import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AppSettingsView:View{
    @ObservedObject var model:AppModel
    @Environment(\.dismiss)private var dismiss
    @AppStorage("appearanceMode")private var appearance="system"
    @AppStorage("responseFontSize")private var fontSize=16.0
    @AppStorage("showThumbnails")private var thumbnails=true
    @AppStorage("gesturesEnabled")private var gestures=true
    @AppStorage(SpeakManager.rateKey)private var speechRate=SpeakManager.defaultRate
    @AppStorage("defaultPostName")private var postName=""
    @AppStorage("defaultPostMail")private var postMail="sage"
    @State private var word="";@State private var url=""
    @State private var deepseekKey="";@State private var deepseekStatus="";@State private var deepseekBusy=false;@State private var deepseekStored=false;@State private var confirmDelete=false
    @AppStorage(NetSlangSettings.storageKey)private var slangEnabled=true
    @State private var slangCount=0;@State private var slangRisky=0;@State private var slangSource="";@State private var slangProblem="";@State private var slangQuery="";@State private var slangHits:[String]=[]
    @State private var slangStatus=""
    var body:some View{NavigationStack{Form{
        Section("DeepSeek（クラウドAI）"){
            SecureField("APIキー",text:$deepseekKey)
            HStack{
                Button("保存"){saveDeepSeekKey()}.disabled(deepseekKey.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                Button(deepseekBusy ? "確認中…":"接続テスト"){Task{await testDeepSeek()}}.disabled(deepseekBusy || (deepseekKey.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !deepseekStored))
            }
            if deepseekStored{
                LabeledContent("登録済み",value:APIKeyStore.maskedKey ?? "••••")
                LabeledContent("保存先",value:APIKeyStore.storageDescription)
                Button("APIキーを削除",role:.destructive){confirmDelete=true}
            }
            LabeledContent("モデル",value:AIModelChoice.deepseek.rawValue)
            if !deepseekStatus.isEmpty{Text(deepseekStatus).font(.caption).foregroundStyle(.secondary)}
            Text("入力したレスと生成結果はDeepSeekのサーバーへ送信されます。端末内だけで生成したい場合はLFMを選んでください。").font(.caption).foregroundStyle(.secondary)
        }
        Section("ネットスラング辞書"){
            Toggle("辞書を使う",isOn:$slangEnabled)
            LabeledContent("収録",value:"\(slangCount)語（読み専用 \(slangRisky)語）")
            Text(slangSource).font(.caption).foregroundStyle(.secondary)
            if !slangProblem.isEmpty{Text(slangProblem).font(.caption).foregroundStyle(.red)}
            HStack{TextField("辞書を引く（例: ぴえん）",text:$slangQuery);Button("検索"){lookup()}.disabled(slangQuery.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
            ForEach(slangHits,id:\.self){line in Text(line).font(.caption)}
            Button("辞書を再読み込み"){reloadDictionary()}
            if !slangStatus.isEmpty{Text(slangStatus).font(.caption).foregroundStyle(.secondary)}
            Text("辞書はJSONLです。語を1行足すと振る舞いが変わり、再学習は不要です。注意(medium/high)の語は読み専用で、書き込みには使いません。").font(.caption).foregroundStyle(.secondary)
        }
        Section("文字の大きさ・表示設定"){
            Picker("外観モード",selection:$appearance){Text("システム準拠").tag("system");Text("ライト").tag("light");Text("ダーク").tag("dark")}
            HStack{Text("レスの文字サイズ");Slider(value:$fontSize,in:12...28,step:1);Text("\(Int(fontSize))")}
            Toggle("画像サムネイルを表示",isOn:$thumbnails)
        }
        Section("NGの管理"){
            HStack{TextField("NGワード",text:$word);Button("追加"){add(word,to:&model.ngWords);word=""}.disabled(word.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
            ForEach(model.ngWords,id:\.self){item in HStack{Text(item);Spacer();Button(role:.destructive){model.ngWords.removeAll{$0==item}}label:{Image(systemName:"trash")}}}
            HStack{TextField("NG URL・ドメイン",text:$url).textInputAutocapitalization(.never);Button("追加"){add(url,to:&model.ngURLs);url=""}.disabled(url.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
            ForEach(model.ngURLs,id:\.self){item in HStack{Text(item);Spacer();Button(role:.destructive){model.ngURLs.removeAll{$0==item}}label:{Image(systemName:"trash")}}}
            LabeledContent("NG ID",value:"\(model.hiddenIDs.count)件")
            Button("NGをすべて解除",role:.destructive){model.clearNG()}
        }
        Section("操作の設定"){Toggle("ジェスチャ操作を使用する",isOn:$gestures);Text("左右スワイプで板・スレ・レス画面を移動します。").font(.caption).foregroundStyle(.secondary)}
        Section("読み上げ"){HStack{Text("速さ");Slider(value:$speechRate,in:0.35...0.75,step:0.05);Text(String(format:"%.2f",speechRate))};Text("レスごとの「読み上げ」ボタンで日本語の音声読み上げを行います。").font(.caption).foregroundStyle(.secondary)}
        Section("書き込みの設定"){TextField("既定の名前",text:$postName);TextField("既定のメール",text:$postMail).textInputAutocapitalization(.never)}
        Section("下書き"){if model.draftList.isEmpty{Text("保存された下書きはありません").foregroundStyle(.secondary)};ForEach(model.draftList){item in VStack(alignment:.leading,spacing:4){Text(item.record.threadTitle).font(.subheadline).lineLimit(1);Text(item.record.message.replacingOccurrences(of:"\n",with:" ")).font(.caption).foregroundStyle(.secondary).lineLimit(2);HStack{Text("\(item.record.boardName)・\(item.record.updatedAt.formatted(date:.numeric,time:.shortened))").font(.caption2).foregroundStyle(.secondary);Spacer();Button(role:.destructive){model.removeDraft(id:item.id)}label:{Image(systemName:"trash")}}};Text("書き込み画面を閉じても、スレごとに自動保存されます。").font(.caption).foregroundStyle(.secondary)}}
        Section("書き込みログ"){if model.postingLog.isEmpty{Text("書き込み履歴はありません").foregroundStyle(.secondary)};ForEach(Array(model.postingLog.prefix(100))){item in VStack(alignment:.leading,spacing:4){HStack{Text(item.number.map{"\($0)番"} ?? "書き込み").font(.subheadline).bold();Spacer();Text(item.date.formatted(date:.numeric,time:.shortened)).font(.caption2).foregroundStyle(.secondary)};Text(item.threadTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1);Text(item.message).font(.caption).lineLimit(3)}.contextMenu{Button("本文をコピー"){UIPasteboard.general.string=item.message}}};if !model.postingLog.isEmpty{Button("ログを消去",role:.destructive){model.clearPostingLog()}}}
        Section("データ管理"){LabeledContent("お気に入り",value:"\(model.favoriteThreads.count)件");LabeledContent("履歴",value:"\(model.historyThreads.count)件");Button("閲覧履歴を消去",role:.destructive){model.clearHistory()}}
        Section("ローカルAI"){AISettingsSummary()}
    }.navigationTitle("設定").toolbar{Button("完了"){dismiss()}}.onAppear{deepseekStored=APIKeyStore.load() != nil;APIDiagnostics.log("settings onAppear stored=\(deepseekStored)");refreshDictionary()}.confirmationDialog("DeepSeekのAPIキーを削除しますか？",isPresented:$confirmDelete,titleVisibility:.visible){Button("削除",role:.destructive){APIKeyStore.delete();deepseekStored=false;deepseekStatus="APIキーを削除しました"};Button("キャンセル",role:.cancel){}}}}
    private func refreshDictionary(){
        let source=SlangDictionary.source()
        slangCount=source.entries.count
        slangRisky=source.riskyCount
        slangSource="\(source.description): \(source.path)"
        slangProblem=SlangDictionary.loadError ?? ""
    }
    private func lookup(){
        let hits=SlangDictionary.search(slangQuery.trimmingCharacters(in:.whitespacesAndNewlines),tag:nil,risk:nil)
        slangHits=hits.prefix(5).map{$0.displayLine}
        if hits.isEmpty{slangHits=["該当する語がありません"]}
    }
    private func reloadDictionary(){
        SlangDictionary.reload()
        refreshDictionary()
        slangHits=[]
        slangStatus="辞書を読み直しました（\(slangCount)語）"
    }
    private func add(_ value:String,to list:inout[String]){let v=value.trimmingCharacters(in:.whitespacesAndNewlines);if !v.isEmpty && !list.contains(v){list.append(v)}}
    private func saveDeepSeekKey(){
        let value=deepseekKey.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.isEmpty else{return}
        let storage=APIKeyStore.save(value)
        deepseekKey=""
        deepseekStored=APIKeyStore.load() != nil
        if deepseekStored{
            AIModelChoice.makeDefault(.deepseek)
            deepseekStatus="保存しました（\(storage)）。生成モデルをDeepSeekに切り替えました。\(APIKeyStore.lastStatus)"
        }else{
            deepseekStatus="APIキーを保存できませんでした。\(APIKeyStore.lastStatus)"
        }
    }
    @MainActor private func testDeepSeek() async {
        // 入力欄に値があれば、その場で保存してから試す。
        // 「保存」を押し忘れても接続テストが通るようにする。
        let typed=deepseekKey.trimmingCharacters(in:.whitespacesAndNewlines)
        if !typed.isEmpty{
            let storage=APIKeyStore.save(typed)
            deepseekKey=""
            deepseekStored=APIKeyStore.load() != nil
            AIModelChoice.makeDefault(.deepseek)
            APIDiagnostics.log("test auto-save storage=\(storage)")
        }
        guard let key=APIKeyStore.load() else{deepseekStatus="APIキーが未登録です。入力欄にキーを貼り付けて保存してください。";APIDiagnostics.log("test blocked: load returned nil");return}
        APIDiagnostics.log("test start keyLength=\(key.count)")
        deepseekBusy=true;deepseekStatus="";defer{deepseekBusy=false}
        do{let reply=try await AIBackend.testDeepSeek(apiKey:key);deepseekStatus="接続成功: \(String(reply.prefix(40)))";APIDiagnostics.log("test ok")}
        catch{deepseekStatus=error.localizedDescription;APIDiagnostics.log("test failed: \(error.localizedDescription)")}
    }
}

private struct AISettingsSummary:View{var body:some View{Group{
    LabeledContent("選択モデル",value:AIModelChoice.selected.label)
    if AIModelChoice.selected == .deepseek{LabeledContent("APIキー",value:APIKeyStore.storageDescription)}
    Text("AIアシスト画面でモデルを選べます。DeepSeekを使うにはAPIキーの登録が必要です。")
}.font(.callout)}}
