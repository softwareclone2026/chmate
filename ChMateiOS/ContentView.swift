import SwiftUI

struct ContentView: View {
    private enum SidebarMode:String,CaseIterable,Identifiable{case favorites="お気に入り",history="履歴",boards="板";var id:String{rawValue}}
    @StateObject private var model=AppModel()
    @State private var columns:NavigationSplitViewVisibility = .all
    @State private var webURL:URL?; @State private var imageURL:URL?; @State private var compose=false; @State private var aiPost:Post?; @State private var settings=false
    @State private var sidebarMode:SidebarMode = .boards
    @AppStorage("gesturesEnabled") private var gesturesEnabled=true
    @AppStorage("appearanceMode") private var appearanceMode="system"
    var body:some View {
        NavigationSplitView(columnVisibility:$columns) {
            VStack(spacing:0){Picker("表示",selection:$sidebarMode){ForEach(SidebarMode.allCases){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented).padding()
                if sidebarMode == .boards {List(selection:Binding(get:{model.selectedBoard},set:{board in if let board{Task{await model.select(board)}}})) {ForEach(model.visibleCategories){category in Section(category.name){ForEach(category.boards){board in Label(board.name,systemImage:"rectangle.stack").tag(board)}}}}.searchable(text:$model.boardSearch,prompt:"板を検索")}
                else {SavedThreadList(threads:sidebarMode == .favorites ? model.favoriteThreads:model.historyThreads,model:model)}
            }
            .navigationTitle(sidebarMode.rawValue)
            .toolbar { ToolbarItemGroup(placement:.topBarTrailing){Button{Task{await model.loadBoards()}}label:{Image(systemName:"arrow.clockwise")};Button{settings=true}label:{Image(systemName:"gearshape")}} }
        } content: {
            Group { if model.selectedBoard != nil {
                List(model.visibleThreads,selection:Binding(get:{model.selectedThread},set:{thread in if let thread{Task{await model.select(thread)}}})){thread in
                    HStack{VStack(alignment:.leading,spacing:5){Text(thread.title).font(.headline).lineLimit(2);HStack{Text("\(thread.postCount)レス");Text("勢い \(thread.speed)")}.font(.caption).foregroundStyle(.secondary)};Spacer();Button{model.toggleFavorite(thread)}label:{Image(systemName:model.isFavorite(thread) ? "star.fill":"star").foregroundStyle(model.isFavorite(thread) ? .yellow:.secondary)}.buttonStyle(.borderless)}.tag(thread)
                }.searchable(text:$model.threadSearch,prompt:"スレッドを検索")
            } else { ContentUnavailableView("板を選択",systemImage:"rectangle.stack",description:Text("左の板一覧から板を選んでください")) } }
            .navigationTitle(model.selectedBoard?.name ?? "スレッド一覧").toolbar{ToolbarItem(placement:.topBarTrailing){Picker("並べ替え",selection:$model.threadSort){ForEach(AppModel.ThreadSort.allCases){Text($0.rawValue).tag($0)}}}}
        } detail: {
            ThreadReader(model:model,webURL:$webURL,imageURL:$imageURL,compose:$compose,aiPost:$aiPost)
        }
        .navigationSplitViewStyle(.balanced)
        .simultaneousGesture(DragGesture(minimumDistance:70).onEnded { value in
            guard gesturesEnabled, abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
            if value.translation.width < -90 {
                if model.selectedThread != nil { columns = .detailOnly }
                else if model.selectedBoard != nil { columns = .doubleColumn }
            } else if value.translation.width > 90 { columns = .all }
        })
        .task{await model.start()}
        .overlay(alignment:.bottom){Text(model.status).font(.caption).padding(.horizontal,12).padding(.vertical,6).background(.ultraThinMaterial,in:Capsule()).padding(.bottom,6)}
        .sheet(item:$webURL){WebSheet(url:$0)}.fullScreenCover(item:$imageURL){ImageSheet(url:$0)}
        .sheet(isPresented:$compose){ComposeView(model:model)}.sheet(item:$aiPost){AIAssistView(model:model,initial:$0)}.sheet(isPresented:$settings){AppSettingsView(model:model)}
        .preferredColorScheme(appearanceMode=="dark" ? .dark:appearanceMode=="light" ? .light:nil)
        .onReceive(NotificationCenter.default.publisher(for:.useAIDraft)){note in if let text=note.object as? String{model.composeDraft=text;compose=true}}
    }
}

private struct SavedThreadList:View{
    let threads:[ThreadSummary];@ObservedObject var model:AppModel
    var body:some View{List(threads){thread in Button{Task{await model.select(thread.board);await model.select(thread)}}label:{VStack(alignment:.leading,spacing:4){Text(thread.title).lineLimit(2);Text(thread.board.name).font(.caption).foregroundStyle(.secondary)}}.buttonStyle(.plain).contextMenu{Button(model.isFavorite(thread) ? "お気に入り解除":"お気に入りに追加"){model.toggleFavorite(thread)}}}.overlay{if threads.isEmpty{ContentUnavailableView("まだありません",systemImage:"tray")}}}
}

private struct ThreadReader:View {
    @ObservedObject var model:AppModel; @Binding var webURL:URL?; @Binding var imageURL:URL?; @Binding var compose:Bool; @Binding var aiPost:Post?
    @State private var anchorPost:Post?;@State private var selectedPosterID:String?;@State private var imageGrid=false
    @State private var tools=false;@State private var nextThreadSheet=false;@State private var restoredFor:String?
    var body:some View { Group { if let thread=model.selectedThread {
        ScrollViewReader { proxy in
            List(model.visiblePosts){post in PostRow(post:post,openWeb:{webURL=$0},openImage:{imageURL=$0},openAnchor:showAnchor,showPoster:{selectedPosterID=post.posterID},reply:{reply(to:post)},ai:{aiPost=post},hide:{model.hide(post.posterID)}).onAppear{model.markRead(post.number)}.id(post.number) }.listStyle(.plain).searchable(text:$model.postSearch,prompt:"レスを検索")
                .navigationTitle(thread.title).navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItemGroup(placement:.topBarTrailing){Button{model.toggleFavorite(thread)}label:{Image(systemName:model.isFavorite(thread) ? "star.fill":"star")}.help("お気に入り");Button{tools=true}label:{Image(systemName:"chart.bar.doc.horizontal")}.help("スレ分析・要約");Button{nextThreadSheet=true;Task{await model.refreshNextThreads(force:true)}}label:{Image(systemName:"arrow.right.doc.on.clipboard")}.help("次スレ候補");Button{imageGrid=true}label:{Image(systemName:"photo.on.rectangle.angled")}.help("画像一覧");Button{scroll(to:model.visiblePosts.first?.number,proxy:proxy)}label:{Image(systemName:"arrow.up.to.line")}.help("一番上のレスへ").disabled(model.visiblePosts.isEmpty);Button{scroll(to:model.visiblePosts.last?.number,proxy:proxy)}label:{Image(systemName:"arrow.down.to.line")}.help("一番下のレスへ").disabled(model.visiblePosts.isEmpty);Button{Task{await model.select(thread)}}label:{Image(systemName:"arrow.clockwise")}.help("更新");Button{compose=true}label:{Image(systemName:"square.and.pencil")}.help("書き込む")}}
                .task(id:model.posts.count){await restoreScroll(proxy)}
        }
    } else { ContentUnavailableView("スレッドを選択",systemImage:"text.bubble",description:Text("板を選び、次にスレッドを選んでください")) } }
    .sheet(item:$anchorPost){post in NavigationStack{ScrollView{PostRow(post:post,openWeb:{webURL=$0},openImage:{imageURL=$0},openAnchor:showAnchor,showPoster:{selectedPosterID=post.posterID},reply:{anchorPost=nil;reply(to:post)},ai:{anchorPost=nil;aiPost=post},hide:{model.hide(post.posterID);anchorPost=nil}).padding()}.navigationTitle(">>\(post.number)").navigationBarTitleDisplayMode(.inline).toolbar{Button("閉じる"){anchorPost=nil}}}.presentationDetents([.medium,.large])}
    .sheet(isPresented:$imageGrid){ImageGrid(posts:model.posts,open:{imageURL=$0})}
    .sheet(isPresented:$tools){ThreadToolsView(model:model)}
    .sheet(isPresented:$nextThreadSheet){NextThreadSheet(model:model)}
    .sheet(item:Binding(get:{selectedPosterID.map{PosterSelection(id:$0)}},set:{if $0==nil{selectedPosterID=nil}})){selection in PosterPostsView(id:selection.id,posts:model.posts.filter{$0.posterID==selection.id},openAnchor:showAnchor,close:{selectedPosterID=nil})}
}
    /// 前回読んだ位置まで戻す。読み込み直後に一度だけ実行する。
    @MainActor private func restoreScroll(_ proxy:ScrollViewProxy) async {
        guard let thread=model.selectedThread, restoredFor != thread.id else{return}
        restoredFor=thread.id
        guard let target=model.lastReadNumber(for:thread), model.posts.contains(where:{$0.number==target}) else{return}
        try? await Task.sleep(nanoseconds:400_000_000)
        withAnimation(.easeInOut(duration:0.3)){proxy.scrollTo(target,anchor:.center)}
    }
    private func showAnchor(_ number:Int){anchorPost=model.posts.first{$0.number==number && !model.hiddenIDs.contains($0.posterID)}}
    private func reply(to post:Post){model.composeDraft += model.composeDraft.isEmpty ? ">>\(post.number)\n" : "\n>>\(post.number)\n";compose=true}
    private func scroll(to number:Int?,proxy:ScrollViewProxy){guard let number else{return};withAnimation(.easeInOut(duration:0.25)){proxy.scrollTo(number,anchor:.center)}}
}

private struct PostRow:View {
    @AppStorage("responseFontSize") private var responseFontSize=16.0
    @ObservedObject private var speaker=SpeakManager.shared
    let post:Post;let openWeb:(URL)->Void;let openImage:(URL)->Void;let openAnchor:(Int)->Void;let showPoster:()->Void;let reply:()->Void;let ai:()->Void;let hide:()->Void
    var body:some View { VStack(alignment:.leading,spacing:8){HStack{Text("\(post.number)").bold();Text(post.name).font(.subheadline).bold();Spacer()};HStack{Text(post.date).font(.caption).foregroundStyle(.secondary);if !post.posterID.isEmpty{Text("ID:\(post.posterID)").font(.caption).foregroundStyle(.blue).onTapGesture(perform:showPoster).onLongPressGesture(minimumDuration:0.55,perform:hide)}};LinkText(text:post.message,openWeb:openWeb,openImage:openImage,openAnchor:openAnchor).font(.system(size:responseFontSize));HStack(spacing:12){PostActionButton(title:"返信",systemImage:"arrowshape.turn.up.left",action:reply);PostActionButton(title:"AI",systemImage:"sparkles",action:ai);PostActionButton(title:speaker.isSpeaking(number:post.number) ? "停止":"読み上げ",systemImage:"speaker.wave.2",action:{speaker.toggle(number:post.number,text:post.message)});if !post.posterID.isEmpty{Button("NG ID",role:.destructive,action:hide).frame(minHeight:44)}}.buttonStyle(.borderless)}.padding(.vertical,7).swipeActions(edge:.trailing){if !post.posterID.isEmpty{Button("NG ID",role:.destructive,action:hide)}} }
}

private struct PosterSelection:Identifiable{let id:String}
private struct PosterPostsView:View{let id:String;let posts:[Post];let openAnchor:(Int)->Void;let close:()->Void;var body:some View{NavigationStack{List(posts){post in Button{close();openAnchor(post.number)}label:{VStack(alignment:.leading,spacing:5){Text(">>\(post.number)").bold();Text(post.message).lineLimit(5)}}.buttonStyle(.plain)}.navigationTitle("ID:\(id)（\(posts.count)件）").toolbar{Button("閉じる",action:close)}}}}
private struct ImageGrid:View{let posts:[Post];let open:(URL)->Void;@Environment(\.dismiss)private var dismiss;private var urls:[URL]{Array(Set(posts.flatMap{$0.message.split(whereSeparator:\.isWhitespace).compactMap{URL(string:String($0).trimmingCharacters(in:CharacterSet(charactersIn:"[]()")))}}.filter{["png","jpg","jpeg","gif","webp"].contains($0.pathExtension.lowercased())})).sorted{$0.absoluteString<$1.absoluteString}};var body:some View{NavigationStack{ScrollView{LazyVGrid(columns:[GridItem(.adaptive(minimum:140))]){ForEach(urls,id:\.absoluteString){url in AsyncImage(url:url){$0.resizable().scaledToFill()}placeholder:{ProgressView()}.frame(height:140).clipped().contentShape(Rectangle()).onTapGesture{open(url)}}}.padding()}.navigationTitle("画像一覧（\(urls.count)）").toolbar{Button("閉じる"){dismiss()}}.overlay{if urls.isEmpty{ContentUnavailableView("画像がありません",systemImage:"photo")}}}}}

private struct PostActionButton: View {
    let title:String; let systemImage:String; let action:()->Void
    var body:some View {
        Button(action:action){Label(title,systemImage:systemImage).font(.body.weight(.semibold)).padding(.horizontal,14).frame(minHeight:44).contentShape(Rectangle())}
            .buttonStyle(.bordered)
    }
}

private struct LinkText:View {
    @AppStorage("showThumbnails") private var showThumbnails=true
    let text:String;let openWeb:(URL)->Void;let openImage:(URL)->Void;let openAnchor:(Int)->Void
    var body:some View{VStack(alignment:.leading,spacing:8){Text(linkedText).environment(\.openURL,OpenURLAction{url in if url.scheme=="chmate-anchor",let number=Int(url.host ?? ""){openAnchor(number);return .handled};if let scheme=url.scheme,["http","https"].contains(scheme){openWeb(url);return .handled};return .discarded});if showThumbnails{ForEach(urls,id:\.absoluteString){url in if isImage(url){AsyncImage(url:url){$0.resizable().scaledToFit()}placeholder:{ProgressView()}.frame(maxHeight:220).clipShape(RoundedRectangle(cornerRadius:8)).onTapGesture{openImage(url)}}}}}}
    private var linkedText:AttributedString {
        var value = AttributedString(text)
        let regex = try! NSRegularExpression(pattern: #">>([0-9]+)"#)
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text),
                  let numberRange = Range(match.range(at: 1), in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: value),
                  let upper = AttributedString.Index(range.upperBound, within: value) else { continue }
            value[lower..<upper].link = URL(string: "chmate-anchor://\(text[numberRange])")
            value[lower..<upper].foregroundColor = .accentColor
            value[lower..<upper].underlineStyle = .single
        }
        return value
    }
    private var urls:[URL]{text.split(whereSeparator:\.isWhitespace).compactMap{URL(string:String($0).trimmingCharacters(in:CharacterSet(charactersIn:"[]()")))}.filter{["http","https"].contains($0.scheme)}}
    private func isImage(_ u:URL)->Bool{["png","jpg","jpeg","gif","webp"].contains(u.pathExtension.lowercased())}
}

extension Notification.Name { static let replyToPost=Notification.Name("replyToPost") }
extension URL:@retroactive Identifiable{public var id:String{absoluteString}}
