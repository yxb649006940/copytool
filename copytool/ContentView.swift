import SwiftUI

struct ContentView: View {
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    @State private var searchText = ""
    @State private var selectedIndex: Int?
    @State private var hoverItem: HistoryItem?

    var filteredHistory: [HistoryItem] {
        if searchText.isEmpty {
            return clipboardManager.history
        }
        return clipboardManager.history.filter { item in
            item.displayText.lowercased().contains(searchText.lowercased())
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            historyListView
                .padding(8)

            Divider()

            footerView
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 400, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: hoverItem) { _, newItem in
            if let item = newItem {
                PreviewWindowManager.shared.showPreview(for: item)
            } else {
                PreviewWindowManager.shared.hidePreview()
            }
        }
    }

    private func showSettingsWindow() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
        }
    }

    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("剪贴板历史记录")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 8) {
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
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(filteredHistory.enumerated()), id: \.element.id) { (filteredIndex, item) in
                            // 找到原始索引
                            if let originalIndex = clipboardManager.history.firstIndex(where: { $0.id == item.id }) {
                                HistoryItemView(
                                    item: item,
                                    index: originalIndex,
                                    isSelected: selectedIndex == originalIndex,
                                    onSelect: {
                                        selectedIndex = originalIndex
                                    },
                                    onHover: { hoverItem in
                                        self.hoverItem = hoverItem
                                    }
                                )
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .onHover { isHovered in
                    // 当鼠标离开整个列表区域时，确保预览窗口关闭
                    if !isHovered {
                        hoverItem = nil
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
}

struct HistoryItemView: View {
    let item: HistoryItem
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onHover: (HistoryItem?) -> Void
    @ObservedObject private var clipboardManager = ClipboardManager.shared

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                contentPreview

                Spacer()

                deleteButton
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.15) : Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color(NSColor.separatorColor), lineWidth: isSelected ? 1.5 : 0.5)
            )
            .onTapGesture {
                onSelect()
                clipboardManager.copyToClipboard(item: item)
                // 立即关闭预览窗口
                onHover(nil)
                PreviewWindowManager.shared.hidePreview()
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

                Text(item.timeString)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
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

#Preview {
    ContentView()
}
