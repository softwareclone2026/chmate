# Geschar の機能分析と ChMate への移植

`/Applications/Geschar.app` は App Store 版の 5ch クライアントです。
iOS アプリを Mac 上で動かすラップ形式（`WrappedBundle`）で、
バージョン 3.71.0、Objective-C と Swift の混在、Realm と RevenueCat を同梱しています。

バイナリ内のクラス名から機能を洗い出しました。アプリ本体は FairPlay で
一部が暗号化されているため、表示文字列ではなく型名と構成から判断しています。

## 機能インベントリ

閲覧

- 板一覧、板の板（`BoardsOfBoardViewController`）、板の並べ替え（`BoardAsSectionHeaderOrderViewController`）
- スレ一覧、レス一覧、スレ表示
- お気に入り、履歴、しおり相当の位置記憶
- ジェスチャ操作（`GesturableTableViewController`）
- 自動スクロール（`AutoScrollToolManager`）

検索

- 板内検索、レス内検索、検索結果、検索語の保存、板をまたぐ検索

書き込み

- 下書き管理（`DraftManager`）、書き込みログ（`KakikomiLogManager`）
- ログイン状態の保持（`LoginManager`）

表示支援

- 画像の一覧・拡大（`GridThumbnailViewController`、`ZoomableImageViewController`）
- 動画の保存（`VideoDownloadManager`）
- 読み上げ（`SpeakManager`）
- フォント選択（`FontManager`、`UIFontPickerViewController`）

AI・分析

- スレ要約（`SummarizeManager`、`SummarizeViewController`）
- スレ分析（`ThreadAnalysisViewController`）

データ

- Realm による保存、圧縮、バックアップと復元、UserDefaults のバックアップ
- 共有拡張（テキストと URL を受け取る）

課金

- サブスクリプションと買い切りのペイウォール、コーヒー購入

## ChMate に移植した機能

ChMate の構成（SwiftUI、外部依存なし、ローカル AI あり）に合わせて、
効果が大きく単体で完結するものを移植しました。

| Geschar の機能 | ChMate での実装 |
| --- | --- |
| KakikomiLogManager | 書き込みログ。投稿の成否と本文を記録し、設定から確認・コピーできる |
| DraftManager | スレごとの下書き。書き込み画面を閉じても自動保存し、次回復元する |
| SpeakManager | レスごとの読み上げ。速度は設定で変更できる |
| ThreadAnalysisViewController | スレ分析。レス数、ID 数、アンカー数、画像数、勢い、時間帯、書き込みの多い ID |
| SummarizeManager | AI によるスレ要約。話題・対立点・未解決点を出力し、下書きへ渡せる |
| NextThreadTitleListViewController | 次スレ候補。タイトルを正規化して同じ板の後継スレを探す |
| しおり・自動スクロール | スレごとに最後に読んだレスを記録し、開いたときに位置へ戻る |

## 移植しなかった機能

- 板をまたぐ全文検索: 板ごとに dat を取得する必要があり、負荷と実装量が大きい
- Realm によるローカル DB とバックアップ: ChMate は UserDefaults と JSON で足りている
- 動画の保存、画像のアップロード: 権利とサーバー負荷の面で別途判断が必要
- 課金と広告: ChMate は配布形態が異なる
- フォント選択: Catalyst では標準フォントで十分なため保留

## 実装メモ

新しいファイルは `ChMateiOS/ReadingTools.swift` と `ChMateiOS/ThreadToolsView.swift` です。
Xcode の同期グループに含まれるため、プロジェクトファイルの編集は不要です。

次スレ検索はタイトルを正規化して照合します。先頭の【悲報】のような飾りと、
末尾の ★2 / Part 5 / その3 / (12) / 第4 を落としたうえで一致を見ます。
一致が無い場合は先頭 10 文字の前方一致まで緩めます。自動で移動はせず、
候補を一覧で提示して選ばせます。
