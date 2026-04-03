import SwiftUI

struct ContentView: View {
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    @State private var searchText = ""
    @State private var selectedIndex: Int?
    @State private var hoverItem: HistoryItem?
    @State private var windowAlwaysOnTop = SettingsManager.shared.windowAlwaysOnTop
    @State private var scrollToTop = false  // 标记是否需要滚动到顶部
    @State private var previousHistoryCount: Int = 0  // 记录上一次的历史记录数量
    @State private var selectedTab: Tab = .history  // 当前选中的 tab

    enum Tab {
        case history
        case favorites
    }

    var filteredHistory: [HistoryItem] {
        if searchText.isEmpty {
            return clipboardManager.history
        }
        return clipboardManager.history.filter { item in
            item.displayText.lowercased().contains(searchText.lowercased())
        }
    }

    var filteredFavorites: [HistoryItem] {
        if searchText.isEmpty {
            return clipboardManager.favorites
        }
        return clipboardManager.favorites.filter { item in
            item.displayText.lowercased().contains(searchText.lowercased())
        }
    }

    // 建立 history 的 id 到索引的映射，避免频繁的 O(n) 查找
    private var historyIdToIndexMap: [UUID: Int] {
        var map = [UUID: Int]()
        for (index, item) in clipboardManager.history.enumerated() {
            map[item.id] = index
        }
        return map
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            tabNavigationView

            // 根据选中的 tab 显示相应内容
            if selectedTab == .history {
                historyListView
            } else {
                favoritesListView
            }

            Divider()

            footerView
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color(NSColor.controlBackgroundColor))
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 400, minHeight: 400) // 添加最小尺寸限制
        .onAppear {
            // 打开面板时清理过期记录
            clipboardManager.cleanExpiredItems()
            // 初始化历史记录数量
            previousHistoryCount = clipboardManager.history.count
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("WindowAlwaysOnTopChanged"))) { _ in
            windowAlwaysOnTop = SettingsManager.shared.windowAlwaysOnTop
        }
        .onChange(of: hoverItem) { oldItem, newItem in
            if let item = newItem {
                PreviewWindowManager.shared.showPreview(for: item)
            } else {
                PreviewWindowManager.shared.hidePreview()
            }
        }
        .onChange(of: clipboardManager.history.count) { oldCount, newCount in
            // 当历史记录数量增加时（有新记录），标记需要滚动到顶部
            if newCount > oldCount {
                scrollToTop = true
            }
            previousHistoryCount = newCount
        }
        .onChange(of: searchText) { oldText, newText in
            // 当搜索文本变化时（特别是清空搜索时），标记需要滚动到顶部
            if oldText != newText {
                scrollToTop = true
            }
        }
        // 当主窗口消失时，确保预览窗口也隐藏
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in
            hoverItem = nil
            PreviewWindowManager.shared.hidePreview()
        }
        // 当应用失去焦点时，确保预览窗口也隐藏
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            hoverItem = nil
            PreviewWindowManager.shared.hidePreview()
        }
        // 当窗口即将关闭时隐藏预览
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            hoverItem = nil
            PreviewWindowManager.shared.hidePreview()
        }
    }

    private func showSettingsWindow() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
        }
    }

    // 新增：Tab 导航视图
    private var tabNavigationView: some View {
        HStack(spacing: 4) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = .history
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .medium))
                    Text("剪贴记录")
                        .font(.system(size: 13, weight: .medium))
                    Text("\(clipboardManager.history.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(selectedTab == .history ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.15))
                        )
                        .foregroundColor(selectedTab == .history ? .blue : .secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedTab == .history ? Color.blue.opacity(0.12) : Color.clear)
                )
                .foregroundColor(selectedTab == .history ? .blue : .secondary)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = .favorites
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .medium))
                    Text("收藏")
                        .font(.system(size: 13, weight: .medium))
                    Text("\(clipboardManager.favorites.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(selectedTab == .favorites ? Color.yellow.opacity(0.25) : Color.secondary.opacity(0.15))
                        )
                        .foregroundColor(selectedTab == .favorites ? .yellow : .secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedTab == .favorites ? Color.yellow.opacity(0.15) : Color.clear)
                )
                .foregroundColor(selectedTab == .favorites ? .yellow : .secondary)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding(4)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("剪贴板历史记录")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 8) {
                    // 窗口置顶快捷按钮
                    Button(action: {
                        SettingsManager.shared.windowAlwaysOnTop.toggle()
                        windowAlwaysOnTop = SettingsManager.shared.windowAlwaysOnTop
                    }) {
                        Image(systemName: windowAlwaysOnTop ? "pin.fill" : "pin")
                            .font(.system(size: 14))
                            .foregroundColor(windowAlwaysOnTop ? .orange : .secondary)
                            .padding(6)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { isHovered in
                        if isHovered {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .help("窗口置顶")

                    Button(action: {
                        showSettingsWindow()
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { isHovered in
                        if isHovered {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .help("设置")

                    Text("共 \(clipboardManager.history.count) 条记录")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            // 搜索框
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField("搜索...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
        }
    }

    private var historyListView: some View {
        Group {
            if filteredHistory.isEmpty {
                if searchText.isEmpty {
                    emptyStateView
                } else {
                    searchEmptyStateView
                }
            } else {
                // 使用 ScrollViewReader 来控制滚动位置
                ScrollViewReader { proxy in
                    // 使用 List 替代 ScrollView + VStack，利用懒加载优化性能
                    List {
                        // 预计算 id 到索引的映射，只计算一次
                        let idToIndexMap = historyIdToIndexMap
                        ForEach(filteredHistory) { item in
                            // 使用预计算的 id 到索引的映射，O(1) 查找
                            let originalIndex = idToIndexMap[item.id] ?? 0
                            HistoryItemView(
                                item: item,
                                index: originalIndex,
                                isSelected: selectedIndex == originalIndex,
                                onSelect: {
                                    selectedIndex = originalIndex
                                },
                                onHover: { hoverItem in
                                    self.hoverItem = hoverItem
                                },
                                onToggleFavorite: {
                                    clipboardManager.toggleFavorite(item: item)
                                }
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .id(item.id)  // 为每个项目添加 id 用于滚动定位
                        }
                    }
                    .listStyle(.plain)
                    .onHover { isHovered in
                        // 当鼠标离开整个列表区域时，确保预览窗口关闭
                        if !isHovered {
                            hoverItem = nil
                        }
                    }
                    .onAppear {
                        // 窗口出现时，滚动到顶部（显示最新记录）
                        if let firstItem = filteredHistory.first {
                            proxy.scrollTo(firstItem.id, anchor: .top)
                        }
                    }
                    .onChange(of: scrollToTop) { _, shouldScroll in
                        // 当需要滚动到顶部时
                        if shouldScroll, let firstItem = filteredHistory.first {
                            proxy.scrollTo(firstItem.id, anchor: .top)
                            scrollToTop = false
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                        // 窗口获得焦点时，确保最新记录可见
                        if let firstItem = filteredHistory.first {
                            proxy.scrollTo(firstItem.id, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private var searchEmptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("未找到匹配的记录")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("尝试使用其他关键词搜索")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("暂无剪贴板历史记录")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("开始复制文本或图片来建立历史记录")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var footerView: some View {
        HStack {
            Button(action: {
                clipboardManager.clearAll()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("清空所有")
                }
                .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            Text("快捷键: \(SettingsManager.shared.hotkey.displayString)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // 新增：收藏列表视图
    private var favoritesListView: some View {
        Group {
            if filteredFavorites.isEmpty {
                if searchText.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "star")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("暂无收藏记录")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("点击剪贴记录上的星标按钮来添加收藏")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("未找到匹配的收藏")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("尝试使用其他关键词搜索")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            } else {
                // 使用 ScrollViewReader 来控制滚动位置
                ScrollViewReader { proxy in
                    // 使用 List 替代 ScrollView + VStack，利用懒加载优化性能
                    List {
                        ForEach(filteredFavorites) { item in
                            // 使用 item.id 直接查找原始索引，减少遍历次数
                            FavoriteItemView(
                                item: item,
                                onSelect: { /* 处理选择 */ },
                                onHover: { hoverItem in
                                    self.hoverItem = hoverItem
                                },
                                onUnfavorite: {
                                    clipboardManager.toggleFavorite(item: item)
                                }
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .id(item.id)  // 为每个项目添加 id 用于滚动定位
                        }
                    }
                    .listStyle(.plain)
                    .onHover { isHovered in
                        // 当鼠标离开整个列表区域时，确保预览窗口关闭
                        if !isHovered {
                            hoverItem = nil
                        }
                    }
                    .onAppear {
                        // 窗口出现时，滚动到顶部（显示最新记录）
                        if let firstItem = filteredFavorites.first {
                            proxy.scrollTo(firstItem.id, anchor: .top)
                        }
                    }
                    .onChange(of: scrollToTop) { _, shouldScroll in
                        // 当需要滚动到顶部时
                        if shouldScroll, let firstItem = filteredFavorites.first {
                            proxy.scrollTo(firstItem.id, anchor: .top)
                            scrollToTop = false
                        }
                    }
                }
            }
        }
    }
}

struct HistoryItemView: View {
    let item: HistoryItem
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onHover: (HistoryItem?) -> Void
    let onToggleFavorite: () -> Void  // 新增：收藏按钮回调
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    @State private var animationProgress: CGFloat = 0
    @State private var startTrim: CGFloat = 0
    @State private var animationID = UUID()

    var body: some View {
        HStack(spacing: 12) {
            contentPreview

            Spacer()

            // 新增：收藏按钮
            favoriteButton

            deleteButton
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.textBackgroundColor))
        )
        .overlay(
            ZStack {
                // 基础边框
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)

                // 选中时的渐变边框效果
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .inset(by: 1)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.blue.opacity(0),
                                    Color.blue.opacity(0.6),
                                    Color.blue.opacity(1),
                                    Color.blue.opacity(1),
                                    Color.blue.opacity(0.6),
                                    Color.blue.opacity(0)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                        )
                        .shadow(color: .blue.opacity(0.4 * animationProgress), radius: 4 * animationProgress, x: 0, y: 0)
                        .opacity(animationProgress)
                        .id(animationID)
                        .onAppear {
                            animationProgress = 0
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                                withAnimation(.easeOut(duration: 0.6)) {
                                    animationProgress = 1
                                }
                            }
                        }
                }
            }
        )
        .onTapGesture { location in
            // 根据点击位置计算起始位置（0到1）
            let width = 400.0 // 假设宽度
            startTrim = max(0, min(1, location.x / width))
            animationID = UUID()
            animationProgress = 0
            onSelect()
            clipboardManager.copyToClipboard(item: item)
            onHover(nil)
            PreviewWindowManager.shared.hidePreview()

            // 启动动画
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.linear(duration: 0.8)) {
                    animationProgress = 1
                }
            }
        }
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
                onHover(item)
            } else {
                NSCursor.pop()
                onHover(nil)
                // 额外调用一次 hidePreview 确保窗口被隐藏
                PreviewWindowManager.shared.hidePreview()
            }
        }
        .onChange(of: isSelected) { _, selected in
            if selected {
                animationID = UUID()
                animationProgress = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.linear(duration: 0.8)) {
                        animationProgress = 1
                    }
                }
            } else {
                animationProgress = 0
            }
        }
    }

    private var contentPreview: some View {
        HStack(spacing: 12) {
            typeIcon

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.displayText)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    Spacer()
                }
            }
        }
    }

    private var typeIcon: some View {
        VStack {
            if item.contentType == .text {
                Image(systemName: "doc.text")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
            } else if item.contentType == .image {
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
            } else if item.contentType == .file {
                // 根据文件扩展名显示不同的图标
                Image(systemName: fileIconName(for: item.fileName))
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
            }
        }
        .frame(width: 32, height: 32)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func fileIconName(for fileName: String?) -> String {
        guard let name = fileName else {
            return "paperplane.fill" // 默认文件图标
        }

        let ext = (name as NSString).pathExtension.lowercased()

        // 图片文件
        if ["jpg", "jpeg", "png", "gif", "bmp", "tiff"].contains(ext) {
            return "photo.fill"
        }

        // 文档文件
        if ["pdf", "doc", "docx", "txt", "rtf", "html", "htm"].contains(ext) {
            return "doc.fill"
        }

        // 代码文件
        if ["swift", "java", "py", "js", "html", "css", "php", "rb", "go", "c", "cpp"].contains(ext) {
            return "chevron.left.forwardslash.chevron.right"
        }

        // 压缩文件
        if ["zip", "rar", "7z", "tar", "gz"].contains(ext) {
            return "folder.fill.badge.questionmark"
        }

        // 视频文件
        if ["mp4", "mov", "avi", "mkv", "flv"].contains(ext) {
            return "video.fill"
        }

        // 音频文件
        if ["mp3", "wav", "aac", "m4a"].contains(ext) {
            return "music.note"
        }

        // 文件夹
        if ext.isEmpty || ["folder", "dir"].contains(ext) {
            return "folder.fill"
        }

        return "paperplane.fill" // 默认文件图标
    }

    // 新增：收藏按钮
    private var favoriteButton: some View {
        Button(action: {
            onToggleFavorite()
        }) {
            Image(systemName: item.isFavorite ? "star.fill" : "star")
                .font(.system(size: 12))
                .foregroundColor(item.isFavorite ? .yellow : .secondary)
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var deleteButton: some View {
        Button(action: {
            clipboardManager.removeItem(at: index)
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// 新增：收藏项视图
struct FavoriteItemView: View {
    let item: HistoryItem
    let onSelect: () -> Void
    let onHover: (HistoryItem?) -> Void
    let onUnfavorite: () -> Void
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    @State private var animationProgress: CGFloat = 0
    @State private var startTrim: CGFloat = 0
    @State private var animationID = UUID()

    var body: some View {
        HStack(spacing: 12) {
            contentPreview

            Spacer()

            unfavoriteButton
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.textBackgroundColor))
        )
        .overlay(
            ZStack {
                // 基础边框
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)

                // 选中时的渐变边框效果
            }
        )
        .onTapGesture { location in
            // 根据点击位置计算起始位置（0到1）
            let width = 400.0 // 假设宽度
            startTrim = max(0, min(1, location.x / width))
            animationID = UUID()
            animationProgress = 0
            onSelect()
            clipboardManager.copyToClipboard(item: item)
            onHover(nil)
            PreviewWindowManager.shared.hidePreview()

            // 启动动画
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.linear(duration: 0.8)) {
                    animationProgress = 1
                }
            }
        }
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
                onHover(item)
            } else {
                NSCursor.pop()
                onHover(nil)
            }
        }
    }

    private var contentPreview: some View {
        HStack(spacing: 12) {
            typeIcon

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.displayText)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    Spacer()
                }
            }
        }
    }

    private var typeIcon: some View {
        VStack {
            if item.contentType == .text {
                Image(systemName: "doc.text")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
            } else if item.contentType == .image {
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
            } else if item.contentType == .file {
                // 根据文件扩展名显示不同的图标
                Image(systemName: fileIconName(for: item.fileName))
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
            }
        }
        .frame(width: 32, height: 32)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func fileIconName(for fileName: String?) -> String {
        guard let name = fileName else {
            return "paperplane.fill" // 默认文件图标
        }

        let ext = (name as NSString).pathExtension.lowercased()

        // 图片文件
        if ["jpg", "jpeg", "png", "gif", "bmp", "tiff"].contains(ext) {
            return "photo.fill"
        }

        // 文档文件
        if ["pdf", "doc", "docx", "txt", "rtf", "html", "htm"].contains(ext) {
            return "doc.fill"
        }

        // 代码文件
        if ["swift", "java", "py", "js", "html", "css", "php", "rb", "go", "c", "cpp"].contains(ext) {
            return "chevron.left.forwardslash.chevron.right"
        }

        // 压缩文件
        if ["zip", "rar", "7z", "tar", "gz"].contains(ext) {
            return "folder.fill.badge.questionmark"
        }

        // 视频文件
        if ["mp4", "mov", "avi", "mkv", "flv"].contains(ext) {
            return "video.fill"
        }

        // 音频文件
        if ["mp3", "wav", "aac", "m4a"].contains(ext) {
            return "music.note"
        }

        // 文件夹
        if ext.isEmpty || ["folder", "dir"].contains(ext) {
            return "folder.fill"
        }

        return "paperplane.fill" // 默认文件图标
    }

    private var unfavoriteButton: some View {
        Button(action: {
            onUnfavorite()
        }) {
            Image(systemName: "star.slash.fill")
                .font(.system(size: 12))
                .foregroundColor(.yellow)
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// 自定义形状，直接使用 RoundedRectangle
struct TrimmedRoundedRect: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: 1.25, dy: 1.25)
        return RoundedRectangle(cornerRadius: cornerRadius).path(in: insetRect)
    }
}

#Preview {
    ContentView()
}
