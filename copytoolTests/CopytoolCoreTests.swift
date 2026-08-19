import XCTest
import CryptoKit
import SQLite3
@testable import CopytoolCore

final class CopytoolCoreTests: XCTestCase {
    private struct LegacyArchiveFixture: Codable {
        let schemaVersion: Int
        let items: [LegacyItemFixture]
    }

    private struct LegacyItemFixture: Codable {
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

    func testHotkeyDisplayUsesCorrectMacVirtualKeyCodes() {
        XCTAssertEqual(
            HotkeyConfiguration(keyCode: 0, modifiers: [.command, .option]).displayString,
            "Cmd + Opt + A"
        )
        XCTAssertEqual(
            HotkeyConfiguration(keyCode: 31, modifiers: [.command, .shift]).displayString,
            "Cmd + Shift + O"
        )
        XCTAssertEqual(
            HotkeyConfiguration(keyCode: 18, modifiers: [.control]).displayString,
            "Ctrl + 1"
        )
    }

    func testMultipleFilesRoundTripWithoutDroppingItems() throws {
        let urls = [
            URL(fileURLWithPath: "/tmp/first.txt"),
            URL(fileURLWithPath: "/tmp/second.pdf")
        ]
        let item = try XCTUnwrap(HistoryItem(fileURLs: urls))
        let decoded = try JSONDecoder().decode(
            HistoryItem.self,
            from: JSONEncoder().encode(item)
        )

        XCTAssertEqual(decoded.fileName, "2 个文件")
        XCTAssertEqual(decoded.resolvedFileURLs, urls)
    }

    func testImageDigestIsStableAndContentSensitive() {
        let first = Data("first image".utf8)
        let second = Data("second image".utf8)

        XCTAssertEqual(
            HistoryItem.imageDigest(for: first),
            HistoryItem.imageDigest(for: first)
        )
        XCTAssertNotEqual(
            HistoryItem.imageDigest(for: first),
            HistoryItem.imageDigest(for: second)
        )
    }

    func testPreviewImageDataUsesInMemoryDataWithoutDiskAccess() {
        let data = Data("preview-image-data".utf8)
        let item = HistoryItem(
            id: UUID(),
            contentType: .image,
            textContent: nil,
            imageData: data,
            timestamp: Date()
        )

        XCTAssertEqual(item.previewImageData(), data)
    }

    func testPreviewImageDataReadsImageFileItem() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("copytool-preview-\(UUID().uuidString).png")
        let data = Data("preview-file-data".utf8)
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertEqual(HistoryItem(fileURL: fileURL).previewImageData(), data)
    }

    func testSearchableTextIncludesContentPastDisplaySummary() {
        let suffix = "only-found-after-fifty-characters"
        let item = HistoryItem(text: String(repeating: "x", count: 60) + suffix)

        XCTAssertFalse(item.displayText.contains(suffix))
        XCTAssertTrue(item.searchableText.contains(suffix))
    }

    func testHistoryEncryptionRoundTripAndRejectsWrongKey() throws {
        let data = Data("私密剪贴板内容".utf8)
        let key = SymmetricKey(size: .bits256)
        let encrypted = try HistoryCrypto.encrypt(data, using: key)

        XCTAssertNotEqual(encrypted, data)
        XCTAssertEqual(try HistoryCrypto.decrypt(encrypted, using: key), data)
        XCTAssertThrowsError(
            try HistoryCrypto.decrypt(encrypted, using: SymmetricKey(size: .bits256))
        )
    }

    func testLegacyFileItemFallsBackToSingleFileURL() throws {
        let legacyJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "contentType": "file",
          "fileName": "legacy.txt",
          "fileURL": "file:///tmp/legacy.txt",
          "timestamp": 0
        }
        """
        let item = try JSONDecoder().decode(HistoryItem.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(item.resolvedFileURLs, [URL(fileURLWithPath: "/tmp/legacy.txt")])
        XCTAssertFalse(item.isFavorite)
    }

    func testSQLiteStoreSupportsIncrementalPaginationSearchAndFavorites() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("copytool-store-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let key = SymmetricKey(size: .bits256)
        let store = HistoryStore(
            appDirectory: directory,
            encryptionKey: key,
            migratesUserDefaults: false
        )

        for index in 0..<205 {
            let item = HistoryItem(text: "record-\(index)-private-content")
            let storedItem = await store.upsert(item)
            XCTAssertNotNil(storedItem)
        }

        let firstPage = await store.loadPage(.history, offset: 0, limit: 100, searchText: "")
        let secondPage = await store.loadPage(.history, offset: 100, limit: 100, searchText: "")
        XCTAssertEqual(firstPage.items.count, 100)
        XCTAssertEqual(secondPage.items.count, 100)
        XCTAssertEqual(firstPage.totalCount, 205)
        XCTAssertTrue(firstPage.hasMore)

        let searchPage = await store.loadPage(
            .history,
            offset: 0,
            limit: 20,
            searchText: "record-137-private-content"
        )
        let matchedItem = try XCTUnwrap(searchPage.items.first)
        XCTAssertEqual(searchPage.totalCount, 1)

        await store.setFavorite(id: matchedItem.id, isFavorite: true)
        let favoritePage = await store.loadPage(.favorites, offset: 0, limit: 20, searchText: "")
        XCTAssertEqual(favoritePage.items.map(\.id), [matchedItem.id])

        await store.delete(id: matchedItem.id)
        let counts = await store.counts()
        XCTAssertEqual(counts.history, 204)
        XCTAssertEqual(counts.favorites, 0)

        let databaseData = try Data(
            contentsOf: directory.appendingPathComponent("clipboardHistory.sqlite")
        )
        XCTAssertFalse(String(decoding: databaseData, as: UTF8.self).contains("private-content"))
    }

    func testFavoriteCategoriesSupportDefaultFilteringMovingAndDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("copytool-category-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = HistoryStore(
            appDirectory: directory,
            encryptionKey: SymmetricKey(size: .bits256),
            migratesUserDefaults: false
        )
        let defaultItem = HistoryItem(text: "default favorite")
        let workItem = HistoryItem(text: "work favorite")
        let storedDefaultItem = await store.upsert(defaultItem)
        let storedWorkItem = await store.upsert(workItem)
        XCTAssertNotNil(storedDefaultItem)
        XCTAssertNotNil(storedWorkItem)

        let createdWorkCategory = await store.createCategory(name: "工作")
        let work = try XCTUnwrap(createdWorkCategory)
        let duplicateCategory = await store.createCategory(name: "工作")
        XCTAssertNil(duplicateCategory)
        await store.setFavorite(id: defaultItem.id, isFavorite: true)
        await store.setFavorite(id: workItem.id, isFavorite: true, categoryID: work.id)

        let all = await store.loadFavoritePage(
            filter: .all,
            offset: 0,
            limit: 20,
            searchText: ""
        )
        let uncategorized = await store.loadFavoritePage(
            filter: .uncategorized,
            offset: 0,
            limit: 20,
            searchText: ""
        )
        let categorized = await store.loadFavoritePage(
            filter: .category(work.id),
            offset: 0,
            limit: 20,
            searchText: ""
        )
        XCTAssertEqual(all.totalCount, 2)
        XCTAssertEqual(uncategorized.items.map(\.id), [defaultItem.id])
        XCTAssertEqual(categorized.items.map(\.id), [workItem.id])
        XCTAssertEqual(categorized.items.first?.favoriteCategoryID, work.id)

        await store.moveFavorite(id: workItem.id, categoryID: nil)
        let movedToDefault = await store.loadFavoritePage(
            filter: .uncategorized,
            offset: 0,
            limit: 20,
            searchText: ""
        )
        XCTAssertEqual(movedToDefault.totalCount, 2)

        await store.moveFavorite(id: workItem.id, categoryID: work.id)
        let deletedCategory = await store.deleteCategory(id: work.id)
        let remainingCategories = await store.loadCategories()
        let itemsAfterDeletion = await store.loadFavoritePage(
            filter: .uncategorized,
            offset: 0,
            limit: 20,
            searchText: ""
        )
        XCTAssertTrue(deletedCategory)
        XCTAssertTrue(remainingCategories.isEmpty)
        XCTAssertEqual(itemsAfterDeletion.totalCount, 2)
    }

    func testExistingSQLiteDatabaseAddsFavoriteCategorySchema() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("copytool-category-migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let databaseURL = directory.appendingPathComponent("clipboardHistory.sqlite")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        guard let database else { return XCTFail("无法创建旧版测试数据库") }
        let oldSchema = """
            CREATE TABLE history_items (
                id TEXT PRIMARY KEY NOT NULL,
                payload BLOB NOT NULL,
                timestamp REAL NOT NULL,
                is_favorite INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE store_metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
            INSERT INTO store_metadata(key, value) VALUES('legacy_migration_completed', '1');
            """
        XCTAssertEqual(sqlite3_exec(database, oldSchema, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let store = HistoryStore(
            appDirectory: directory,
            encryptionKey: SymmetricKey(size: .bits256),
            migratesUserDefaults: false
        )
        _ = await store.bootstrap(pageSize: 20, expiredBefore: nil)
        let category = await store.createCategory(name: "迁移后分类")
        let categories = await store.loadCategories()

        XCTAssertNotNil(category)
        XCTAssertEqual(categories.count, 1)
    }

    func testSQLiteStoreMigratesEncryptedArchive() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("copytool-migration-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let key = SymmetricKey(size: .bits256)
        let fixture = LegacyArchiveFixture(
            schemaVersion: 1,
            items: [
                LegacyItemFixture(
                    id: UUID(),
                    contentType: .text,
                    textContent: "legacy encrypted record",
                    imageFileName: nil,
                    imageDigest: nil,
                    fileName: nil,
                    fileURL: nil,
                    fileURLs: nil,
                    timestamp: Date(),
                    isFavorite: true
                )
            ]
        )
        let archiveData = try JSONEncoder().encode(fixture)
        let encryptedArchive = try HistoryCrypto.encrypt(archiveData, using: key)
        let archiveURL = directory.appendingPathComponent("clipboardHistory.json")
        try encryptedArchive.write(to: archiveURL)

        let store = HistoryStore(
            appDirectory: directory,
            encryptionKey: key,
            migratesUserDefaults: false
        )
        let result = await store.bootstrap(pageSize: 100, expiredBefore: nil)

        XCTAssertTrue(result.migratedLegacyData)
        XCTAssertEqual(result.history.items.first?.textContent, "legacy encrypted record")
        XCTAssertEqual(result.favorites.totalCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))
    }

    func testSQLiteStorePreservesUnreadableLegacyArchive() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("copytool-invalid-migration-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let archiveURL = directory.appendingPathComponent("clipboardHistory.json")
        try Data("not-a-valid-archive".utf8).write(to: archiveURL)
        let store = HistoryStore(
            appDirectory: directory,
            encryptionKey: SymmetricKey(size: .bits256),
            migratesUserDefaults: false
        )

        let result = await store.bootstrap(pageSize: 100, expiredBefore: nil)

        XCTAssertFalse(result.migratedLegacyData)
        XCTAssertEqual(result.history.totalCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
    }
}
