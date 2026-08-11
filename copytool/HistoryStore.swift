import Foundation
import CryptoKit
import SQLite3

/// SQLite 增量存储：每条记录独立加密，图片保持分文件存放。
actor HistoryStore {
    enum Collection: Sendable {
        case history
        case favorites
    }

    struct Page: Sendable {
        let items: [HistoryItem]
        let totalCount: Int
        let hasMore: Bool
    }

    struct BootstrapResult: Sendable {
        let history: Page
        let favorites: Page
        let migratedLegacyData: Bool
    }

    struct Counts: Sendable {
        let history: Int
        let favorites: Int
    }

    private struct LegacyArchive: Codable {
        let schemaVersion: Int
        let items: [LegacyStoredItem]
    }

    private struct LegacyStoredItem: Codable {
        let id: UUID
        let contentType: ContentType
        let textContent: String?
        let imageFileName: String?
        let imageDigest: String?
        let fileName: String?
        let fileURL: String?
        let fileURLs: [String]?
        let timestamp: Date
        let isFavorite: Bool
    }

    /// 只有分页和排序需要的字段留在 SQLite 列中，其余内容整体加密。
    private struct EncryptedPayload: Codable {
        let contentType: ContentType
        let textContent: String?
        let imageFileName: String?
        let imageDigest: String?
        let fileName: String?
        let fileURL: String?
        let fileURLs: [String]?
    }

    private enum StoreError: Error {
        case sqlite(String)
        case invalidRow
        case invalidLegacyArchive
    }

    private let fileManager = FileManager.default
    private let crypto = HistoryCrypto.shared
    private let appDirectory: URL
    private let imagesDirectory: URL
    private let databaseURL: URL
    private let legacyHistoryFileURL: URL
    private let testEncryptionKey: SymmetricKey?
    private let migratesUserDefaults: Bool

    init(
        appDirectory: URL? = nil,
        encryptionKey: SymmetricKey? = nil,
        migratesUserDefaults: Bool = true
    ) {
        let defaultDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("yxb.copytool", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("yxb.copytool", isDirectory: true)

        let resolvedDirectory = appDirectory ?? defaultDirectory
        self.appDirectory = resolvedDirectory
        imagesDirectory = resolvedDirectory.appendingPathComponent("images", isDirectory: true)
        databaseURL = resolvedDirectory.appendingPathComponent("clipboardHistory.sqlite")
        legacyHistoryFileURL = resolvedDirectory.appendingPathComponent("clipboardHistory.json")
        testEncryptionKey = encryptionKey
        self.migratesUserDefaults = migratesUserDefaults
    }

    func bootstrap(pageSize: Int, expiredBefore: Date?) -> BootstrapResult {
        do {
            let database = try openDatabase()
            defer { sqlite3_close(database) }

            let migrated = try migrateLegacyDataIfNeeded(database)
            if let expiredBefore {
                try deleteExpiredItems(before: expiredBefore, database: database)
            }

            return BootstrapResult(
                history: try loadPage(.history, offset: 0, limit: pageSize, searchText: "", database: database),
                favorites: try loadPage(.favorites, offset: 0, limit: pageSize, searchText: "", database: database),
                migratedLegacyData: migrated
            )
        } catch {
            print("SQLite 历史记录初始化失败: \(error)")
            let emptyPage = Page(items: [], totalCount: 0, hasMore: false)
            return BootstrapResult(history: emptyPage, favorites: emptyPage, migratedLegacyData: false)
        }
    }

    func loadPage(
        _ collection: Collection,
        offset: Int,
        limit: Int,
        searchText: String
    ) -> Page {
        do {
            let database = try openDatabase()
            defer { sqlite3_close(database) }
            _ = try migrateLegacyDataIfNeeded(database)
            return try loadPage(collection, offset: offset, limit: limit, searchText: searchText, database: database)
        } catch {
            print("SQLite 分页加载失败: \(error)")
            return Page(items: [], totalCount: 0, hasMore: false)
        }
    }

    func counts() -> Counts {
        do {
            let database = try openDatabase()
            defer { sqlite3_close(database) }
            _ = try migrateLegacyDataIfNeeded(database)
            return Counts(
                history: try scalarInt("SELECT COUNT(*) FROM history_items", database: database),
                favorites: try scalarInt(
                    "SELECT COUNT(*) FROM history_items WHERE is_favorite = 1",
                    database: database
                )
            )
        } catch {
            print("SQLite 读取记录数量失败: \(error)")
            return Counts(history: 0, favorites: 0)
        }
    }

    /// 新增或更新单条记录，返回释放了内存图片的可展示模型。
    func upsert(_ item: HistoryItem) -> HistoryItem? {
        do {
            let database = try openDatabase()
            defer { sqlite3_close(database) }
            _ = try migrateLegacyDataIfNeeded(database)
            return try upsert(item, database: database)
        } catch {
            print("SQLite 保存记录失败: \(error)")
            return nil
        }
    }

    func setFavorite(id: UUID, isFavorite: Bool) {
        do {
            let database = try openDatabase()
            defer { sqlite3_close(database) }
            try execute(
                "UPDATE history_items SET is_favorite = ? WHERE id = ?",
                database: database,
                bindings: [.integer(isFavorite ? 1 : 0), .text(id.uuidString)]
            )
        } catch {
            print("SQLite 更新收藏状态失败: \(error)")
        }
    }

    func delete(id: UUID) {
        do {
            let database = try openDatabase()
            defer { sqlite3_close(database) }
            let imageFileName = try imageFileName(for: id, database: database)
            try execute(
                "DELETE FROM history_items WHERE id = ?",
                database: database,
                bindings: [.text(id.uuidString)]
            )
            removeImageFile(named: imageFileName)
        } catch {
            print("SQLite 删除记录失败: \(error)")
        }
    }

    func deleteAll() {
        do {
            let database = try openDatabase()
            defer { sqlite3_close(database) }
            try execute("DELETE FROM history_items", database: database)
            if fileManager.fileExists(atPath: imagesDirectory.path) {
                try? fileManager.removeItem(at: imagesDirectory)
            }
            try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        } catch {
            print("SQLite 清空记录失败: \(error)")
        }
    }

    func deleteExpired(before date: Date) {
        do {
            let database = try openDatabase()
            defer { sqlite3_close(database) }
            try deleteExpiredItems(before: date, database: database)
        } catch {
            print("SQLite 清理过期记录失败: \(error)")
        }
    }

    // MARK: - Database

    private enum Binding {
        case integer(Int64)
        case double(Double)
        case text(String)
        case blob(Data)
        case null
    }

    private func openDatabase() throws -> OpaquePointer {
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            if let database { sqlite3_close(database) }
            throw StoreError.sqlite(message)
        }

        do {
            sqlite3_busy_timeout(database, 5_000)
            try execute("PRAGMA journal_mode = WAL", database: database)
            try execute("PRAGMA synchronous = NORMAL", database: database)
            try execute(
                """
                CREATE TABLE IF NOT EXISTS history_items (
                    id TEXT PRIMARY KEY NOT NULL,
                    payload BLOB NOT NULL,
                    timestamp REAL NOT NULL,
                    is_favorite INTEGER NOT NULL DEFAULT 0
                )
                """,
                database: database
            )
            try execute(
                "CREATE INDEX IF NOT EXISTS idx_history_timestamp ON history_items(timestamp DESC)",
                database: database
            )
            try execute(
                "CREATE INDEX IF NOT EXISTS idx_history_favorite_timestamp ON history_items(is_favorite, timestamp DESC)",
                database: database
            )
            try execute(
                "CREATE TABLE IF NOT EXISTS store_metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)",
                database: database
            )
            return database
        } catch {
            sqlite3_close(database)
            throw error
        }
    }

    private func loadPage(
        _ collection: Collection,
        offset: Int,
        limit: Int,
        searchText: String,
        database: OpaquePointer
    ) throws -> Page {
        let safeOffset = max(0, offset)
        let safeLimit = max(1, limit)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if query.isEmpty {
            let whereClause = collection == .favorites ? " WHERE is_favorite = 1" : ""
            let totalCount = try scalarInt("SELECT COUNT(*) FROM history_items\(whereClause)", database: database)
            let sql = """
                SELECT id, payload, timestamp, is_favorite
                FROM history_items\(whereClause)
                ORDER BY timestamp DESC
                LIMIT ? OFFSET ?
                """
            let items = try queryItems(
                sql,
                database: database,
                bindings: [.integer(Int64(safeLimit)), .integer(Int64(safeOffset))]
            )
            return Page(
                items: items,
                totalCount: totalCount,
                hasMore: safeOffset + items.count < totalCount
            )
        }

        // 内容在库内保持加密，搜索在 HistoryStore actor 中解密过滤，不阻塞 UI。
        let whereClause = collection == .favorites ? " WHERE is_favorite = 1" : ""
        var statement: OpaquePointer?
        let sql = """
            SELECT id, payload, timestamp, is_favorite
            FROM history_items\(whereClause)
            ORDER BY timestamp DESC
            """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        var matchCount = 0
        var pageItems: [HistoryItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if Task.isCancelled { break }
            guard let item = historyItem(from: statement) else { continue }
            guard item.searchableText.localizedCaseInsensitiveContains(query) else { continue }
            if matchCount >= safeOffset, pageItems.count < safeLimit {
                pageItems.append(item)
            }
            matchCount += 1
        }
        return Page(
            items: pageItems,
            totalCount: matchCount,
            hasMore: safeOffset + pageItems.count < matchCount
        )
    }

    private func upsert(_ item: HistoryItem, database: OpaquePointer) throws -> HistoryItem {
        var imageFileName: String?
        if item.contentType == .image {
            let fileName = "\(item.id.uuidString).data"
            let fileURL = imagesDirectory.appendingPathComponent(fileName)
            if let imageData = item.imageData {
                try encrypt(imageData).write(to: fileURL, options: .atomic)
            } else if let existingURLString = item.imageFileURL,
                      let existingURL = URL(string: existingURLString),
                      fileManager.fileExists(atPath: existingURL.path) {
                if existingURL.standardizedFileURL != fileURL.standardizedFileURL {
                    try fileManager.copyItem(at: existingURL, to: fileURL)
                }
            }
            if fileManager.fileExists(atPath: fileURL.path) {
                imageFileName = fileName
            }
        }

        let payload = EncryptedPayload(
            contentType: item.contentType,
            textContent: item.textContent,
            imageFileName: imageFileName,
            imageDigest: item.imageDigest,
            fileName: item.fileName,
            fileURL: item.fileURL,
            fileURLs: item.fileURLs
        )
        let encryptedPayload = try encrypt(JSONEncoder().encode(payload))
        try execute(
            """
            INSERT INTO history_items(id, payload, timestamp, is_favorite)
            VALUES(?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                payload = excluded.payload,
                timestamp = excluded.timestamp,
                is_favorite = excluded.is_favorite
            """,
            database: database,
            bindings: [
                .text(item.id.uuidString),
                .blob(encryptedPayload),
                .double(item.timestamp.timeIntervalSince1970),
                .integer(item.isFavorite ? 1 : 0)
            ]
        )

        return HistoryItem(
            id: item.id,
            contentType: item.contentType,
            textContent: item.textContent,
            imageData: nil,
            imageFileURL: imageFileName.map { imagesDirectory.appendingPathComponent($0).absoluteString },
            imageDigest: item.imageDigest,
            fileName: item.fileName,
            fileURL: item.fileURL,
            fileURLs: item.fileURLs,
            timestamp: item.timestamp,
            isFavorite: item.isFavorite
        )
    }

    private func queryItems(
        _ sql: String,
        database: OpaquePointer,
        bindings: [Binding] = []
    ) throws -> [HistoryItem] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement, database: database)

        var items: [HistoryItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if Task.isCancelled { break }
            if let item = historyItem(from: statement) {
                items.append(item)
            }
        }
        return items
    }

    private func historyItem(from statement: OpaquePointer) -> HistoryItem? {
        guard let idText = sqlite3_column_text(statement, 0),
              let id = UUID(uuidString: String(cString: idText)),
              let encryptedPayload = data(from: statement, column: 1),
              let decryptedPayload = try? decrypt(encryptedPayload),
              let payload = try? JSONDecoder().decode(EncryptedPayload.self, from: decryptedPayload) else {
            return nil
        }

        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        let isFavorite = sqlite3_column_int(statement, 3) != 0
        let imageFileURL = payload.imageFileName.map {
            imagesDirectory.appendingPathComponent($0).absoluteString
        }
        if payload.contentType == .image {
            guard let imageFileName = payload.imageFileName,
                  fileManager.fileExists(
                    atPath: imagesDirectory.appendingPathComponent(imageFileName).path
                  ) else { return nil }
        }

        return HistoryItem(
            id: id,
            contentType: payload.contentType,
            textContent: payload.textContent,
            imageData: nil,
            imageFileURL: imageFileURL,
            imageDigest: payload.imageDigest,
            fileName: payload.fileName,
            fileURL: payload.fileURL,
            fileURLs: payload.fileURLs,
            timestamp: timestamp,
            isFavorite: isFavorite
        )
    }

    private func deleteExpiredItems(before date: Date, database: OpaquePointer) throws {
        let items = try queryItems(
            """
            SELECT id, payload, timestamp, is_favorite
            FROM history_items
            WHERE is_favorite = 0 AND timestamp < ?
            """,
            database: database,
            bindings: [.double(date.timeIntervalSince1970)]
        )
        try execute(
            "DELETE FROM history_items WHERE is_favorite = 0 AND timestamp < ?",
            database: database,
            bindings: [.double(date.timeIntervalSince1970)]
        )
        for item in items {
            removeImageFile(for: item)
        }
    }

    // MARK: - Legacy migration

    private func migrateLegacyDataIfNeeded(_ database: OpaquePointer) throws -> Bool {
        guard try metadataValue(for: "legacy_migration_completed", database: database) != "1" else {
            return false
        }

        let legacyItems = try loadLegacyItems()
        if !legacyItems.isEmpty {
            try execute("BEGIN IMMEDIATE TRANSACTION", database: database)
            do {
                for item in legacyItems {
                    _ = try upsert(item, database: database)
                }
                try setMetadataValue("1", for: "legacy_migration_completed", database: database)
                try execute("COMMIT", database: database)
            } catch {
                try? execute("ROLLBACK", database: database)
                throw error
            }
        } else {
            try setMetadataValue("1", for: "legacy_migration_completed", database: database)
        }

        if fileManager.fileExists(atPath: legacyHistoryFileURL.path) {
            try? fileManager.removeItem(at: legacyHistoryFileURL)
        }
        if migratesUserDefaults {
            UserDefaults.standard.removeObject(forKey: "clipboardHistory")
            UserDefaults.standard.removeObject(forKey: "favoriteHistory")
        }
        cleanupOrphanedImages(database: database)
        return !legacyItems.isEmpty
    }

    private func loadLegacyItems() throws -> [HistoryItem] {
        var items: [HistoryItem] = []
        if fileManager.fileExists(atPath: legacyHistoryFileURL.path) {
            let storedData = try Data(contentsOf: legacyHistoryFileURL)
            let archiveData = (try? decrypt(storedData)) ?? storedData
            guard let archive = try? JSONDecoder().decode(LegacyArchive.self, from: archiveData) else {
                throw StoreError.invalidLegacyArchive
            }
            items = archive.items.compactMap(historyItem(from:))
        }

        guard migratesUserDefaults else { return items }
        if items.isEmpty,
           let data = UserDefaults.standard.data(forKey: "clipboardHistory") {
            guard let decodedItems = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
                throw StoreError.invalidLegacyArchive
            }
            items = decodedItems
        }

        guard let favoriteData = UserDefaults.standard.data(forKey: "favoriteHistory") else {
            return items
        }
        guard let legacyFavorites = try? JSONDecoder().decode([HistoryItem].self, from: favoriteData) else {
            throw StoreError.invalidLegacyArchive
        }

        var itemIDs = Set(items.map(\.id))
        for favorite in legacyFavorites {
            if let index = items.firstIndex(where: { $0.id == favorite.id }) {
                items[index].isFavorite = true
            } else if itemIDs.insert(favorite.id).inserted {
                var restoredFavorite = favorite
                restoredFavorite.isFavorite = true
                items.append(restoredFavorite)
            }
        }
        return items
    }

    private func historyItem(from storedItem: LegacyStoredItem) -> HistoryItem? {
        var imageFileURL: String?
        var imageDigest = storedItem.imageDigest
        if let imageFileName = storedItem.imageFileName {
            let imageURL = imagesDirectory.appendingPathComponent(imageFileName)
            if fileManager.fileExists(atPath: imageURL.path) {
                imageFileURL = imageURL.absoluteString
                if imageDigest == nil, let storedData = try? Data(contentsOf: imageURL) {
                    let imageData = (try? decrypt(storedData)) ?? storedData
                    imageDigest = HistoryItem.imageDigest(for: imageData)
                }
            }
        }
        if storedItem.contentType == .image, imageFileURL == nil { return nil }

        return HistoryItem(
            id: storedItem.id,
            contentType: storedItem.contentType,
            textContent: storedItem.textContent,
            imageData: nil,
            imageFileURL: imageFileURL,
            imageDigest: imageDigest,
            fileName: storedItem.fileName,
            fileURL: storedItem.fileURL,
            fileURLs: storedItem.fileURLs,
            timestamp: storedItem.timestamp,
            isFavorite: storedItem.isFavorite
        )
    }

    // MARK: - Helpers

    private func encrypt(_ data: Data) throws -> Data {
        if let testEncryptionKey {
            return try HistoryCrypto.encrypt(data, using: testEncryptionKey)
        }
        return try crypto.encrypt(data)
    }

    private func decrypt(_ data: Data) throws -> Data {
        if let testEncryptionKey {
            return try HistoryCrypto.decrypt(data, using: testEncryptionKey)
        }
        return try crypto.decrypt(data)
    }

    private func metadataValue(for key: String, database: OpaquePointer) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT value FROM store_metadata WHERE key = ?",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        try bind([.text(key)], to: statement, database: database)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: value)
    }

    private func setMetadataValue(_ value: String, for key: String, database: OpaquePointer) throws {
        try execute(
            "INSERT OR REPLACE INTO store_metadata(key, value) VALUES(?, ?)",
            database: database,
            bindings: [.text(key), .text(value)]
        )
    }

    private func scalarInt(_ sql: String, database: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func execute(
        _ sql: String,
        database: OpaquePointer,
        bindings: [Binding] = []
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement, database: database)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func bind(_ bindings: [Binding], to statement: OpaquePointer, database: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .integer(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, transient)
            case .blob(let value):
                result = value.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), transient)
                }
            case .null:
                result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else {
                throw StoreError.sqlite(String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    private func data(from statement: OpaquePointer, column: Int32) -> Data? {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private func imageFileName(for id: UUID, database: OpaquePointer) throws -> String? {
        let items = try queryItems(
            "SELECT id, payload, timestamp, is_favorite FROM history_items WHERE id = ? LIMIT 1",
            database: database,
            bindings: [.text(id.uuidString)]
        )
        guard let item = items.first, let urlString = item.imageFileURL else { return nil }
        return URL(string: urlString)?.lastPathComponent
    }

    private func removeImageFile(for item: HistoryItem) {
        removeImageFile(named: item.imageFileURL.flatMap { URL(string: $0)?.lastPathComponent })
    }

    private func removeImageFile(named fileName: String?) {
        guard let fileName else { return }
        try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(fileName))
    }

    private func cleanupOrphanedImages(database: OpaquePointer) {
        let referencedFiles = Set(
            (try? queryItems(
                "SELECT id, payload, timestamp, is_favorite FROM history_items",
                database: database
            ))?.compactMap { item in
                item.imageFileURL.flatMap { URL(string: $0)?.lastPathComponent }
            } ?? []
        )
        guard let existingFiles = try? fileManager.contentsOfDirectory(
            at: imagesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for fileURL in existingFiles where !referencedFiles.contains(fileURL.lastPathComponent) {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
