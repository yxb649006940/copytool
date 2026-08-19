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
    @State private var favoritePickerItem: HistoryItem?
    @State private var isShowingNewCategoryDialog = false
    @State private var categoryNameDraft = ""
    @State private var categoryBeingRenamed: FavoriteCategory?
    @State private var categoryBeingDeleted: FavoriteCategory?
    @State private var pendingFavoriteScrollToTop = false

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
                if selectedTab == .history {
                    scrollToTop = true
                    clipboardManager.searchHistory(newText)
                } else {
                    pendingFavoriteScrollToTop = true
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
        .onChange(of: clipboardManager.favoriteFilter) { _, _ in
            selectedItemID = nil
            scrollToTop = false
            pendingFavoriteScrollToTop = true
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
        .sheet(item: $favoritePickerItem) { item in
            FavoriteCategoryPickerSheet(
                categories: clipboardManager.favoriteCategories,
                onSelect: { categoryID in
                    clipboardManager.setFavorite(item: item, categoryID: categoryID)
                    favoritePickerItem = nil
                },
                onCreate: { name in
                    Task {
                        if let category = await clipboardManager.createFavoriteCategory(name: name) {
                            clipboardManager.setFavorite(item: item, categoryID: category.id)
                        }
                        favoritePickerItem = nil
                    }
                },
                onCancel: {
                    favoritePickerItem = nil
                }
            )
        }
        .alert("新建分类", isPresented: $isShowingNewCategoryDialog) {
            TextField("分类名称", text: $categoryNameDraft)
            Button("取消", role: .cancel) {
                categoryNameDraft = ""
            }
            Button("创建") {
                let name = categoryNameDraft
                categoryNameDraft = ""
                Task {
                    if let category = await clipboardManager.createFavoriteCategory(name: name) {
                        clipboardManager.selectFavoriteFilter(.category(category.id))
                    }
                }
            }
            .disabled(!isValidCategoryName(categoryNameDraft))
        } message: {
            Text("创建后可以把收藏移动到该分类。")
        }
        .alert("重命名分类", isPresented: renameCategoryDialogBinding) {
            TextField("分类名称", text: $categoryNameDraft)
            Button("取消", role: .cancel) {
                categoryBeingRenamed = nil
                categoryNameDraft = ""
            }
            Button("保存") {
                guard let category = categoryBeingRenamed else { return }
                let name = categoryNameDraft
                categoryBeingRenamed = nil
                categoryNameDraft = ""
                Task {
                    _ = await clipboardManager.renameFavoriteCategory(category, name: name)
                }
            }
            .disabled(!isValidCategoryName(categoryNameDraft))
        }
        .alert("删除分类？", isPresented: deleteCategoryDialogBinding) {
            Button("取消", role: .cancel) {
                categoryBeingDeleted = nil
            }
            Button("删除", role: .destructive) {
                guard let category = categoryBeingDeleted else { return }
                categoryBeingDeleted = nil
                Task {
                    _ = await clipboardManager.deleteFavoriteCategory(category)
                }
            }
        } message: {
            Text("分类中的收藏不会被删除，将自动移到默认分类。")
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

    private var renameCategoryDialogBinding: Binding<Bool> {
        Binding(
            get: { categoryBeingRenamed != nil },
            set: { if !$0 { categoryBeingRenamed = nil } }
        )
    }

    private var deleteCategoryDialogBinding: Binding<Bool> {
        Binding(
            get: { categoryBeingDeleted != nil },
            set: { if !$0 { categoryBeingDeleted = nil } }
        )
    }

    private func isValidCategoryName(_ name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty
            && !["默认", "全部"].contains(where: {
                $0.caseInsensitiveCompare(trimmedName) == .orderedSame
            })
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
                                    if item.isFavorite {
                                        clipboardManager.toggleFavorite(item: item)
                                    } else {
                                        favoritePickerItem = item
                                    }
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
        VStack(spacing: 0) {
            favoriteCategoryBar
            Divider()

            Group {
                if filteredFavorites.isEmpty && clipboardManager.isLoadingFavorites {
                    ProgressView("正在加载…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredFavorites.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: searchText.isEmpty ? "folder" : "magnifyingglass")
                            .font(.system(size: 42))
                            .foregroundColor(.secondary)

                        Text(searchText.isEmpty ? "此分类暂无收藏" : "未找到匹配的收藏")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text(
                            searchText.isEmpty
                                ? "收藏时可选择该分类，或把已有收藏移动到这里"
                                : "尝试使用其他关键词搜索"
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.6))
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(filteredFavorites) { item in
                                FavoriteItemView(
                                    item: item,
                                    categories: clipboardManager.favoriteCategories,
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
                                    onMove: { categoryID in
                                        clipboardManager.moveFavorite(item, to: categoryID)
                                    },
                                    onUnfavorite: {
                                        clipboardManager.toggleFavorite(item: item)
                                    }
                                )
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .id(item.id)
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
                        .id(favoriteListIdentity)
                        .onHover { isHovered in
                            if !isHovered {
                                updateHoverPreview(nil)
                            }
                        }
                        .onAppear {
                            if pendingFavoriteScrollToTop,
                               !clipboardManager.isLoadingFavorites {
                                finishPendingFavoriteScroll(using: proxy)
                            } else if let firstItem = filteredFavorites.first {
                                proxy.scrollTo(firstItem.id, anchor: .top)
                            }
                        }
                        .onChange(of: clipboardManager.isLoadingFavorites) { _, isLoading in
                            if !isLoading, pendingFavoriteScrollToTop {
                                finishPendingFavoriteScroll(using: proxy)
                            }
                        }
                        .onChange(of: filteredFavorites.first?.id) { _, _ in
                            if !clipboardManager.isLoadingFavorites,
                               pendingFavoriteScrollToTop {
                                finishPendingFavoriteScroll(using: proxy)
                            }
                        }
                        .onChange(of: scrollToTop) { _, shouldScroll in
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

    private var favoriteCategoryBar: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        FavoriteCategoryChip(
                            title: "全部",
                            systemImage: "square.grid.2x2",
                            isSelected: clipboardManager.favoriteFilter == .all
                        ) {
                            clipboardManager.selectFavoriteFilter(.all)
                        }
                        .id("favorite-category-all")

                        FavoriteCategoryChip(
                            title: "默认",
                            systemImage: "tray",
                            isSelected: clipboardManager.favoriteFilter == .uncategorized
                        ) {
                            clipboardManager.selectFavoriteFilter(.uncategorized)
                        }
                        .id("favorite-category-default")

                        ForEach(clipboardManager.favoriteCategories) { category in
                            FavoriteCategoryChip(
                                title: category.name,
                                systemImage: "folder",
                                isSelected: clipboardManager.favoriteFilter == .category(category.id)
                            ) {
                                clipboardManager.selectFavoriteFilter(.category(category.id))
                            }
                            .contextMenu {
                                Button("重命名") {
                                    beginRenamingCategory(category)
                                }
                                Divider()
                                Button("删除分类", role: .destructive) {
                                    categoryBeingDeleted = category
                                }
                            }
                            .help("点击切换分类，右键可重命名或删除")
                            .id(category.id)
                        }
                    }
                    .padding(.trailing, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    scrollSelectedFavoriteCategory(using: proxy, animated: false)
                }
                .onChange(of: clipboardManager.favoriteFilter) { _, _ in
                    scrollSelectedFavoriteCategory(using: proxy, animated: true)
                }
            }
            .padding(.leading, 10)
            .layoutPriority(1)

            if case let .category(id) = clipboardManager.favoriteFilter,
               let category = clipboardManager.favoriteCategories.first(where: { $0.id == id }) {
                Menu {
                    Button("重命名") {
                        beginRenamingCategory(category)
                    }
                    Divider()
                    Button("删除分类", role: .destructive) {
                        categoryBeingDeleted = category
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("管理当前分类")
            }

            Button {
                categoryNameDraft = ""
                isShowingNewCategoryDialog = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("新建分类")
            .padding(.trailing, 10)
        }
        .frame(height: 42)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
    }

    private func beginRenamingCategory(_ category: FavoriteCategory) {
        categoryNameDraft = category.name
        categoryBeingRenamed = category
    }

    private var favoriteListIdentity: String {
        switch clipboardManager.favoriteFilter {
        case .all:
            return "favorite-list-all"
        case .uncategorized:
            return "favorite-list-default"
        case .category(let id):
            return "favorite-list-\(id.uuidString)"
        }
    }

    private func finishPendingFavoriteScroll(using proxy: ScrollViewProxy) {
        guard let firstItemID = filteredFavorites.first?.id else {
            pendingFavoriteScrollToTop = false
            return
        }

        pendingFavoriteScrollToTop = false
        DispatchQueue.main.async {
            proxy.scrollTo(firstItemID, anchor: .top)
            // List 会在数据替换后恢复旧锚点，再下一帧定位一次可确保真正回到顶部。
            DispatchQueue.main.async {
                proxy.scrollTo(firstItemID, anchor: .top)
            }
        }
    }

    private func scrollSelectedFavoriteCategory(
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        let target: AnyHashable
        let anchor: UnitPoint
        switch clipboardManager.favoriteFilter {
        case .all:
            target = "favorite-category-all"
            anchor = .leading
        case .uncategorized:
            target = "favorite-category-default"
            anchor = .center
        case .category(let id):
            target = id
            anchor = .trailing
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(target, anchor: anchor)
            }
        } else {
            proxy.scrollTo(target, anchor: anchor)
        }
    }
}

private struct FavoriteCategoryChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.clear)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.5) : Color(NSColor.separatorColor),
                            lineWidth: 0.5
                        )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct FavoriteCategoryPickerSheet: View {
    let categories: [FavoriteCategory]
    let onSelect: (UUID?) -> Void
    let onCreate: (String) -> Void
    let onCancel: () -> Void
    @State private var newCategoryName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("收藏到分类")
                        .font(.headline)
                    Text("选择一个分类，也可以直接新建")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }

            ScrollView {
                VStack(spacing: 8) {
                    categoryButton(title: "默认", systemImage: "tray") {
                        onSelect(nil)
                    }
                    ForEach(categories) { category in
                        categoryButton(title: category.name, systemImage: "folder") {
                            onSelect(category.id)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)

            Divider()

            HStack(spacing: 8) {
                TextField("新分类名称", text: $newCategoryName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createCategory)
                Button("新建并收藏", action: createCategory)
                    .disabled(!isValidCategoryName)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var trimmedCategoryName: String {
        newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValidCategoryName: Bool {
        !trimmedCategoryName.isEmpty
            && !["默认", "全部"].contains(where: {
                $0.caseInsensitiveCompare(trimmedCategoryName) == .orderedSame
            })
    }

    private func createCategory() {
        guard isValidCategoryName else { return }
        onCreate(trimmedCategoryName)
    }

    private func categoryButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
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
    let categories: [FavoriteCategory]
    let isSelected: Bool
    let onSelect: () -> Void
    let onHover: (HistoryItem?) -> Void
    let onCopy: () -> Void
    let onMove: (UUID?) -> Void
    let onUnfavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            contentPreview
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                moveButton
                unfavoriteButton
            }
            .fixedSize()
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

                Label(categoryName, systemImage: item.favoriteCategoryID == nil ? "tray" : "folder")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var categoryName: String {
        guard let categoryID = item.favoriteCategoryID else { return "默认" }
        return categories.first(where: { $0.id == categoryID })?.name ?? "默认"
    }

    private var moveButton: some View {
        Menu {
            Button {
                onMove(nil)
            } label: {
                if item.favoriteCategoryID == nil {
                    Label("默认", systemImage: "checkmark")
                } else {
                    Text("默认")
                }
            }

            if !categories.isEmpty {
                Divider()
            }
            ForEach(categories) { category in
                Button {
                    onMove(category.id)
                } label: {
                    if item.favoriteCategoryID == category.id {
                        Label(category.name, systemImage: "checkmark")
                    } else {
                        Text(category.name)
                    }
                }
            }
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("移动到其他分类")
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
