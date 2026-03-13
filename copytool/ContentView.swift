import SwiftUI

struct ContentView: View {
    @ObservedObject private var clipboardManager = ClipboardManager.shared

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
    }

    private var headerView: some View {
        HStack {
            Text("剪贴板历史记录")
                .font(.headline)
                .foregroundColor(.primary)

            Spacer()

            Text("共 \(clipboardManager.history.count) 条记录")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var historyListView: some View {
        Group {
            if clipboardManager.history.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(0..<clipboardManager.history.count, id: \.self) { index in
                            HistoryItemView(item: clipboardManager.history[index], index: index)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
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

            Text("快捷键: Cmd + Opt + V")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

struct HistoryItemView: View {
    let item: HistoryItem
    let index: Int
    @ObservedObject private var clipboardManager = ClipboardManager.shared

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                contentPreview

                Spacer()

                deleteButton
            }
            .padding(12)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
            .onTapGesture {
                clipboardManager.copyToClipboard(item: item)
            }
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
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
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
            }
        }
        .frame(width: 32, height: 32)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
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