import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    @State private var searchText = ""
    @State private var selectedItemID: UUID?
    @State private var hoverItem: HistoryItem?
    @State private var pendingHoverItem: HistoryItem?
    @State private var isListScrolling = false
    @State private var windowAlwaysOnTop = SettingsManager.shared.windowAlwaysOnTop
    @State private var monitoringEnabled = SettingsManager.shared.monitoringEnabled
    @State private var scrollToTop = false  // 标记是否需要滚动到顶部
    @State private var selectedTab: Tab = .history  // 当前选中的 tab
    @State private var isShowingClearConfirmation = false

    enum Tab {
        case history
        case favorites
    }

    var filteredHistory: [HistoryItem] {
        clipboardManager.history
    }

    var filteredFavorites: [HistoryItem] {
        clipboardManager.favorites
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("WindowAlwaysOnTopChanged"))) { _ in
            windowAlwaysOnTop = SettingsManager.shared.windowAlwaysOnTop
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MonitoringChanged"))) { _ in
            monitoringEnabled = SettingsManager.shared.monitoringEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: NSScrollView.willStartLiveScrollNotification)) { _ in
            isListScrolling = true
            hoverItem = nil
            PreviewWindowManager.shared.hidePreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSScrollView.didEndLiveScrollNotification)) { _ in
            isListScrolling = false
            hoverItem = pendingHoverItem
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
        }
        .onChange(of: searchText) { oldText, newText in
            if oldText != newText {
                scrollToTop = true
                if selectedTab == .history {
                    clipboardManager.searchHistory(newText)
                } else {
                    clipboardManager.searchFavorites(newText)
                }
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .history {
                clipboardManager.searchHistory(searchText)
            } else {
                clipboardManager.searchFavorites(searchText)
            }
        }
        // 当主窗口消失时，确保预览窗口也隐藏
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in
            clearHoverPreview()
        }
        // 当应用失去焦点时，确保预览窗口也隐藏
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            clearHoverPreview()
        }
        // 当窗口即将关闭时隐藏预览
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            clearHoverPreview()
        }
        .alert("清空所有记录？", isPresented: $isShowingClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                clipboardManager.clearAll()
                selectedItemID = nil
            }
        } message: {
            Text("此操作会同时删除历史和收藏，且无法撤销。")
        }
    }

    private func showSettingsWindow() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
        }
    }

    private func updateHoverPreview(_ item: HistoryItem?) {
        pendingHoverItem = item
        guard !isListScrolling else { return }
        hoverItem = item
    }

    private func clearHoverPreview() {
        pendingHoverItem = nil
        hoverItem = nil
        PreviewWindowManager.shared.hidePreview()
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
                    Text("\(clipboardManager.historyTotalCount)")
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
                    Text("\(clipboardManager.favoriteTotalCount)")
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

                if !monitoringEnabled {
                    Text("已暂停")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }

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

                    Text("共 \(selectedTab == .history ? clipboardManager.historyTotalCount : clipboardManager.favoriteTotalCount) 条记录")
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
            if filteredHistory.isEmpty && clipboardManager.isLoadingHistory {
                ProgressView("正在加载…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredHistory.isEmpty {
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
                        ForEach(filteredHistory) { item in
                            HistoryItemView(
                                item: item,
                                isSelected: selectedItemID == item.id,
                                onSelect: {
                                    selectedItemID = item.id
                                },
                                onHover: { hoverItem in
                                    updateHoverPreview(hoverItem)
                                },
                                onCopy: {
                                    clipboardManager.copyToClipboard(item: item)
                                },
                                onToggleFavorite: {
                                    clipboardManager.toggleFavorite(item: item)
                                },
                                onDelete: {
                                    clipboardManager.removeItem(id: item.id)
                                }
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .id(item.id)  // 为每个项目添加 id 用于滚动定位
                        }
                        if clipboardManager.hasMoreHistory {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .listRowSeparator(.hidden)
                            .onAppear {
                                clipboardManager.loadMoreHistory()
                            }
                        }
                    }
                    .listStyle(.plain)
                    .onHover { isHovered in
                        // 当鼠标离开整个列表区域时，确保预览窗口关闭
                        if !isHovered {
                            updateHoverPreview(nil)
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
                isShowingClearConfirmation = true
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
            if filteredFavorites.isEmpty && clipboardManager.isLoadingFavorites {
                ProgressView("正在加载…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredFavorites.isEmpty {
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
                                isSelected: selectedItemID == item.id,
                                onSelect: {
                                    selectedItemID = item.id
                                },
                                onHover: { hoverItem in
                                    updateHoverPreview(hoverItem)
                                },
                                onCopy: {
                                    clipboardManager.copyToClipboard(item: item)
                                },
                                onUnfavorite: {
                                    clipboardManager.toggleFavorite(item: item)
                                }
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .id(item.id)  // 为每个项目添加 id 用于滚动定位
                        }
                        if clipboardManager.hasMoreFavorites {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .listRowSeparator(.hidden)
                            .onAppear {
                                clipboardManager.loadMoreFavorites()
                            }
                        }
                    }
                    .listStyle(.plain)
                    .onHover { isHovered in
                        // 当鼠标离开整个列表区域时，确保预览窗口关闭
                        if !isHovered {
                            updateHoverPreview(nil)
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

private struct ClipboardRowSelectionModifier: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.11)
                            : Color(NSColor.textBackgroundColor)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected
                            ? Color.accentColor.opacity(0.85)
                            : Color(NSColor.separatorColor),
                        lineWidth: isSelected ? 1.4 : 0.5
                    )
            )
            .shadow(
                color: Color.accentColor.opacity(isSelected ? 0.16 : 0),
                radius: isSelected ? 5 : 0,
                x: 0,
                y: 1
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}

struct HistoryItemView: View {
    let item: HistoryItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onHover: (HistoryItem?) -> Void
    let onCopy: () -> Void
    let onToggleFavorite: () -> Void  // 新增：收藏按钮回调
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            contentPreview

            Spacer()

            // 新增：收藏按钮
            favoriteButton

            deleteButton
        }
        .padding(12)
        .modifier(ClipboardRowSelectionModifier(isSelected: isSelected))
        .onTapGesture {
            onSelect()
            onCopy()
            onHover(nil)
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
            onDelete()
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
    let isSelected: Bool
    let onSelect: () -> Void
    let onHover: (HistoryItem?) -> Void
    let onCopy: () -> Void
    let onUnfavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            contentPreview

            Spacer()

            unfavoriteButton
        }
        .padding(12)
        .modifier(ClipboardRowSelectionModifier(isSelected: isSelected))
        .onTapGesture {
            onSelect()
            onCopy()
            onHover(nil)
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
