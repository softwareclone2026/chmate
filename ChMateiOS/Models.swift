import Foundation

struct BoardCategory: Identifiable, Hashable { var id: String { name }; let name: String; let boards: [Board] }
struct Board: Identifiable, Hashable, Codable { var id: String { url.absoluteString }; let name: String; let url: URL }
struct ThreadSummary: Identifiable, Hashable, Codable { var id: String { board.id + key }; let key: String; let title: String; let postCount: Int; let speed: Int; let board: Board }
struct Post: Identifiable, Hashable { var id: Int { number }; let number: Int; let name: String; let mail: String; let date: String; let posterID: String; let message: String; let anchors: [Int] }

enum SJIS {
    static func decode(_ data: Data) -> String? { String(data: data, encoding: .shiftJIS) ?? String(data: data, encoding: .utf8) }
    static func plain(_ s: String) -> String { s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines) }
    static func escape(_ value: String) -> String {
        let safe = value.unicodeScalars.map { scalar in String(scalar).data(using: .shiftJIS) == nil ? "&#\(scalar.value);" : String(scalar) }.joined()
        return (safe.data(using: .shiftJIS) ?? Data()).map { byte in
            if (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || [42,45,46,95].contains(byte) { return String(UnicodeScalar(byte)) }
            return byte == 32 ? "+" : String(format: "%%%02X", byte)
        }.joined()
    }
}

@MainActor final class AppModel: ObservableObject {
    enum ThreadSort: String, CaseIterable, Identifiable { case speed="勢い", newest="新しい順", posts="レス数"; var id:String{rawValue} }
    @Published var categories: [BoardCategory] = []
    @Published var selectedBoard: Board?; @Published var threads: [ThreadSummary] = []
    @Published var selectedThread: ThreadSummary?; @Published var posts: [Post] = []
    @Published var loading = false; @Published var status = "準備完了"
    @Published var boardSearch = ""; @Published var threadSearch = ""; @Published var postSearch = ""
    @Published var composeDraft = ""
    @Published var favoriteThreads: [ThreadSummary] { didSet { save(favoriteThreads,key:"favoriteThreads") } }
    @Published var historyThreads: [ThreadSummary] { didSet { save(historyThreads,key:"historyThreads") } }
    @Published var threadSort: ThreadSort = .speed
    @Published var hiddenIDs: Set<String> { didSet { UserDefaults.standard.set(Array(hiddenIDs), forKey: "hiddenIDs") } }
    @Published var ngWords:[String]{didSet{UserDefaults.standard.set(ngWords,forKey:"ngWords")}}
    @Published var ngURLs:[String]{didSet{UserDefaults.standard.set(ngURLs,forKey:"ngURLs")}}
    @Published var postingLog: [PostedItem] { didSet { save(Array(postingLog.prefix(300)), key: "postingLog") } }
    @Published var drafts: [String: DraftRecord] { didSet { save(drafts, key: "threadDrafts") } }
    @Published var lastRead: [String: Int] { didSet { UserDefaults.standard.set(lastRead, forKey: "lastReadPosts") } }
    @Published var nextThreads: [ThreadSummary] = []
    init() {
        hiddenIDs = Set(UserDefaults.standard.stringArray(forKey: "hiddenIDs") ?? [])
        ngWords = UserDefaults.standard.stringArray(forKey:"ngWords") ?? []
        ngURLs = UserDefaults.standard.stringArray(forKey:"ngURLs") ?? []
        favoriteThreads = Self.load([ThreadSummary].self,key:"favoriteThreads") ?? []
        historyThreads = Self.load([ThreadSummary].self,key:"historyThreads") ?? []
        postingLog = Self.load([PostedItem].self, key: "postingLog") ?? []
        drafts = Self.load([String: DraftRecord].self, key: "threadDrafts") ?? [:]
        lastRead = (UserDefaults.standard.dictionary(forKey: "lastReadPosts") as? [String: Int]) ?? [:]
    }

    static let fallback = [BoardCategory(name: "標準の板", boards: [
        Board(name:"ニュー速(嫌儲)",url:URL(string:"https://greta.5ch.io/poverty/")!), Board(name:"ニュース速報+",url:URL(string:"https://asahi.5ch.io/newsplus/")!),
        Board(name:"芸スポ速報+",url:URL(string:"https://hayabusa9.5ch.io/mnewsplus/")!), Board(name:"ニュース速報(VIP)",url:URL(string:"https://mi.5ch.io/news4vip/")!),
        Board(name:"なんでも実況J",url:URL(string:"https://eagle.5ch.io/livejupiter/")!), Board(name:"iOS",url:URL(string:"https://fate.5ch.io/ios/")!),
        Board(name:"Mac",url:URL(string:"https://egg.5ch.io/mac/")!), Board(name:"プログラミング",url:URL(string:"https://mevius.5ch.io/tech/")!), Board(name:"アニメ",url:URL(string:"https://pug.5ch.io/anime/")!)])]
    var visibleCategories: [BoardCategory] { boardSearch.isEmpty ? categories : categories.compactMap { let b=$0.boards.filter{$0.name.localizedCaseInsensitiveContains(boardSearch)}; return b.isEmpty ? nil : BoardCategory(name:$0.name,boards:b) } }
    var visibleThreads: [ThreadSummary] {
        let filtered=threads.filter { threadSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(threadSearch) }
        switch threadSort { case .speed:return filtered.sorted{$0.speed>$1.speed};case .newest:return filtered.sorted{$0.key>$1.key};case .posts:return filtered.sorted{$0.postCount>$1.postCount} }
    }
    var visiblePosts: [Post] { posts.filter { post in !hiddenIDs.contains(post.posterID) && !ngWords.contains(where:{!$0.isEmpty && post.message.localizedCaseInsensitiveContains($0)}) && !ngURLs.contains(where:{!$0.isEmpty && post.message.localizedCaseInsensitiveContains($0)}) && (postSearch.isEmpty || post.message.localizedCaseInsensitiveContains(postSearch) || post.posterID.localizedCaseInsensitiveContains(postSearch)) } }

    func start() async { if categories.isEmpty { await loadBoards() } }
    func loadBoards() async {
        loading=true; status="板メニューを取得中…"; defer { loading=false }
        do {
            var req=URLRequest(url:URL(string:"https://menu.5ch.net/bbsmenu.json")!); req.setValue("Monazilla/1.00 (ChMate-iOS/0.2)",forHTTPHeaderField:"User-Agent")
            let (data,response)=try await URLSession.shared.data(for:req); guard (response as? HTTPURLResponse)?.statusCode==200 else { throw URLError(.badServerResponse) }
            let root=try JSONSerialization.jsonObject(with:data) as? [String:Any], menus=root?["menu_list"] as? [[String:Any]] ?? []
            let parsed=menus.compactMap { item -> BoardCategory? in
                guard let name=item["category_name"] as? String, !name.contains("特別"), !name.contains("ツール") else{return nil}
                let boards=(item["category_content"] as? [[String:Any]] ?? []).compactMap { e -> Board? in guard let n=e["board_name"] as? String,let s=e["url"] as? String,let u=Self.boardURL(s) else{return nil}; return Board(name:SJIS.plain(n),url:u) }
                return boards.isEmpty ? nil : BoardCategory(name:SJIS.plain(name),boards:boards)
            }
            categories=parsed.isEmpty ? Self.fallback:parsed; status="\(categories.reduce(0){$0+$1.boards.count}) 板"
        } catch { categories=Self.fallback; status="標準の板を表示: \(error.localizedDescription)" }
    }
    func select(_ board: Board) async {
        selectedBoard=board; selectedThread=nil; posts=[]; threads=[]; loading=true; status="\(board.name)を取得中…"; defer{loading=false}
        do { threads=try await fetchThreads(board); status="\(threads.count) スレッド"
        } catch { status="取得失敗: \(error.localizedDescription)" }
    }

    private func fetchThreads(_ board: Board) async throws -> [ThreadSummary] {
        let text=try await fetch(board.url.appendingPathComponent("subject.txt")), now=Date().timeIntervalSince1970
        return text.split(whereSeparator:\.isNewline).compactMap { line in
            guard let m=String(line).wholeMatch(of:/([0-9]+)\.dat<>(.*?)\s*\(([0-9]+)\)\s*/),let count=Int(m.3) else{return nil}; let key=String(m.1),age=max(0.1,(now-(Double(key) ?? now))/86400)
            return ThreadSummary(key:key,title:SJIS.plain(String(m.2)),postCount:count,speed:Int((Double(count)/age).rounded()),board:board)
        }.sorted{$0.speed>$1.speed}
    }
    func select(_ thread: ThreadSummary, quiet: Bool=false) async {
        if !quiet { historyThreads.removeAll{$0.id==thread.id};historyThreads.insert(thread,at:0);if historyThreads.count>100{historyThreads.removeLast(historyThreads.count-100)} }
        selectedThread=thread; if !quiet { posts=[]; loading=true; status="レスを取得中…" }; defer{loading=false}
        do { let text=try await fetch(thread.board.url.appendingPathComponent("dat/\(thread.key).dat"))
            posts=text.split(whereSeparator:\.isNewline).enumerated().compactMap { i,line in let f=String(line).components(separatedBy:"<>"); guard f.count>=4 else{return nil}; let date=SJIS.plain(f[2]),pid=date.firstMatch(of:/ID:([^\s<>]+)/).map{String($0.1)} ?? "",msg=SJIS.plain(f[3]); return Post(number:i+1,name:SJIS.plain(f[0]).isEmpty ? "名無しさん":SJIS.plain(f[0]),mail:SJIS.plain(f[1]),date:date,posterID:pid,message:msg,anchors:msg.matches(of:/>>([0-9]+)/).compactMap{Int($0.1)}) }; status="\(posts.count) レス"
        } catch { status="取得失敗: \(error.localizedDescription)" }
    }
    func hide(_ id:String){if !id.isEmpty{hiddenIDs.insert(id)}}; func unhideAll(){hiddenIDs.removeAll()}
    func clearHistory(){historyThreads=[]}
    func clearNG(){hiddenIDs=[];ngWords=[];ngURLs=[]}

    // MARK: - 書き込みログ

    func recordPost(number: Int?, message: String, name: String, mail: String) {
        guard let thread = selectedThread else { return }
        let item = PostedItem(date: Date(), boardName: thread.board.name, threadTitle: thread.title, threadKey: thread.key,
                              boardURL: thread.board.url.absoluteString, number: number, name: name, mail: mail, message: message)
        postingLog.insert(item, at: 0)
    }

    func clearPostingLog() { postingLog = [] }

    // MARK: - スレごとの下書き

    var currentDraft: DraftRecord? { selectedThread.flatMap { drafts[$0.id] } }

    var draftList: [DraftSummary] {
        drafts.map { DraftSummary(id: $0.key, record: $0.value) }.sorted { $0.record.updatedAt > $1.record.updatedAt }
    }

    func saveDraft(message: String, name: String, mail: String) {
        guard let thread = selectedThread else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && name.isEmpty && mail.isEmpty { drafts[thread.id] = nil; return }
        drafts[thread.id] = DraftRecord(message: message, name: name, mail: mail, updatedAt: Date(),
                                        threadTitle: thread.title, boardName: thread.board.name)
    }

    func clearDraft() {
        guard let thread = selectedThread else { return }
        drafts[thread.id] = nil
    }

    func removeDraft(id: String) { drafts[id] = nil }

    // MARK: - 既読位置

    func markRead(_ number: Int, thread: ThreadSummary? = nil) {
        guard let id = (thread ?? selectedThread)?.id else { return }
        if number > (lastRead[id] ?? 0) { lastRead[id] = number }
    }

    func lastReadNumber(for thread: ThreadSummary?) -> Int? {
        guard let thread, let number = lastRead[thread.id], number > 0 else { return nil }
        return number
    }

    // MARK: - 次スレ

    /// 現在の板のスレ一覧から次スレ候補を探す。レス数が少ないうちは何もしない。
    func refreshNextThreads(force: Bool = false) async {
        guard let thread = selectedThread else { nextThreads = []; return }
        guard force || posts.count >= 900 else { nextThreads = []; return }
        do {
            // 板のスレ一覧だけを取り直す。読み中のレス一覧と選択状態は保持する。
            let list = try await fetchThreads(thread.board)
            if let refreshed = list.first(where: { $0.id == thread.id }) { selectedThread = refreshed }
            nextThreads = NextThreadFinder.candidates(current: selectedThread ?? thread, in: list)
        } catch { nextThreads = [] }
    }

    func isFavorite(_ thread:ThreadSummary)->Bool{favoriteThreads.contains{$0.id==thread.id}}
    func toggleFavorite(_ thread:ThreadSummary){if let i=favoriteThreads.firstIndex(where:{$0.id==thread.id}){favoriteThreads.remove(at:i)}else{favoriteThreads.insert(thread,at:0)}}
    @discardableResult
    func post(message:String,name:String,mail:String) async throws -> Int? {
        guard let t=selectedThread else{throw URLError(.badURL)}; let b=t.board.url.pathComponents.filter{$0 != "/"}.last ?? ""
        let fields=["bbs":b,"key":t.key,"FROM":name.isEmpty ? "名無しさん＠お腹いっぱい。":name,"mail":mail,"MESSAGE":message.replacingOccurrences(of:"\n",with:"\r\n"),"submit":"書き込む","time":String(Int(Date().timeIntervalSince1970))]
        let body=fields.map{"\(SJIS.escape($0.key))=\(SJIS.escape($0.value))"}.joined(separator:"&").data(using:.ascii); guard let u=URL(string:"https://\(t.board.url.host ?? "")/test/bbs.cgi") else{throw URLError(.badURL)}
        var req=URLRequest(url:u); req.httpMethod="POST"; req.httpBody=body; req.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type"); req.setValue("Monazilla/1.00 (ChMate-iOS/0.2)",forHTTPHeaderField:"User-Agent"); req.setValue(t.board.url.absoluteString,forHTTPHeaderField:"Referer")
        let(data,response)=try await URLSession.shared.data(for:req),text=SJIS.decode(data) ?? ""; let http=response as? HTTPURLResponse
        let resnum = http?.value(forHTTPHeaderField:"x-resnum").flatMap { Int($0.trimmingCharacters(in:.whitespaces)) }
        guard http?.statusCode==200 else{throw URLError(.badServerResponse)}; guard resnum != nil || text.contains("書きこみました") || text.contains("書き込みました") || text.contains("_X:success") else{throw NSError(domain:"ChMate.Post",code:1,userInfo:[NSLocalizedDescriptionKey:String(SJIS.plain(text).prefix(1000))])}; await select(t,quiet:true)
        return resnum
    }
    private func fetch(_ url:URL) async throws -> String { var r=URLRequest(url:url); r.setValue("Monazilla/1.00 (ChMate-iOS/0.2)",forHTTPHeaderField:"User-Agent"); let(d,res)=try await URLSession.shared.data(for:r); guard (res as? HTTPURLResponse)?.statusCode==200,let s=SJIS.decode(d) else{throw URLError(.badServerResponse)}; return s }
    private static func boardURL(_ value:String)->URL? { guard var c=URLComponents(string:value),let h=c.host,(h.hasSuffix("5ch.net") || h.hasSuffix("5ch.io")) else{return nil}; c.scheme="https"; c.host=h.replacingOccurrences(of:".5ch.net",with:".5ch.io"); c.query=nil;c.fragment=nil; guard c.path.wholeMatch(of:/\/[A-Za-z0-9_]+\//) != nil else{return nil};return c.url }
    private func save<T:Encodable>(_ value:T,key:String){if let data=try? JSONEncoder().encode(value){UserDefaults.standard.set(data,forKey:key)}}
    private static func load<T:Decodable>(_ type:T.Type,key:String)->T?{guard let data=UserDefaults.standard.data(forKey:key)else{return nil};return try? JSONDecoder().decode(type,from:data)}
}
