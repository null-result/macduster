import XCTest
@testable import MacDusterCore

final class FileSystemTests: XCTestCase {
    func testSafetyGuard() {
        XCTAssertFalse(FileSystem.isSafeToRemove(URL(fileURLWithPath: "/System/Library")))
        XCTAssertFalse(FileSystem.isSafeToRemove(FileSystem.home))
        XCTAssertFalse(FileSystem.isSafeToRemove(URL(fileURLWithPath: "/Applications")))
        XCTAssertTrue(FileSystem.isSafeToRemove(FileSystem.home.appendingPathComponent("Library/Caches/foo")))
        XCTAssertTrue(FileSystem.isSafeToRemove(URL(fileURLWithPath: "/Applications/Foo.app")))
    }

    func testSizeAndLargeFileScan() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(count: 2_000_000).write(to: dir.appendingPathComponent("big.bin"))
        try Data(count: 10).write(to: dir.appendingPathComponent("small.bin"))
        XCTAssertGreaterThanOrEqual(FileSystem.size(of: dir), 2_000_000)
        let found = LargeFiles.scan(LargeFileQuery(root: dir, minSize: 1_000_000))
        XCTAssertEqual(found.map(\.name), ["big.bin"])
    }
}
