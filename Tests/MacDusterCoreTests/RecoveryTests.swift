import XCTest
@testable import MacDusterCore

final class RecoveryTests: XCTestCase {
    private func makeImage(_ pieces: [(name: String, data: Data)]) throws -> (URL, [String: Int64]) {
        var image = Data(repeating: 0xA5, count: 1 << 20)
        var offsets = [String: Int64]()
        for piece in pieces {
            image.append(Data(repeating: 0, count: (512 - image.count % 512) % 512 + 1024))
            offsets[piece.name] = Int64(image.count)
            image.append(piece.data)
        }
        image.append(Data(repeating: 0xA5, count: 1 << 16))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".img")
        try image.write(to: url)
        return (url, offsets)
    }

    private func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }

    /// JPEG con una miniatura que contiene su propio FFD9: el carver no debe cortar ahí.
    private var jpeg: Data {
        let thumb: [UInt8] = [0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x04, 0x00, 0x00, 0xFF, 0xD9]
        let app1: [UInt8] = [0xFF, 0xE1, UInt8((thumb.count + 2) >> 8), UInt8((thumb.count + 2) & 0xFF)] + thumb
        let scan: [UInt8] = [0xFF, 0xDA, 0x00, 0x02] + [UInt8](repeating: 0x11, count: 3000) + [0xFF, 0x00, 0x22]
        return Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00] + app1 + scan + [0xFF, 0xD9])
    }

    private var png: Data {
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] { be32(body.count) + Array(type.utf8) + body + [0, 0, 0, 0] }
        let header = [UInt8](repeating: 0, count: 13)
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", header)
            + chunk("IDAT", [UInt8](repeating: 7, count: 2000)) + chunk("IEND", []))
    }

    func testCarvesFilesWithExactSize() throws {
        let (url, offsets) = try makeImage([("jpg", jpeg), ("png", png)])
        defer { try? FileManager.default.removeItem(at: url) }
        let device = try RawDevice(path: url.path)
        var found = [RecoverableFile]()
        RecoveryEngine.scan(device: device, modes: [.deep], token: CancelToken()) { event in
            if case .found(let files) = event { found += files }
        }
        let byOffset = Dictionary(uniqueKeysWithValues: found.map { ($0.offset, $0) })
        XCTAssertEqual(byOffset[offsets["jpg"]!]?.size, Int64(jpeg.count))
        XCTAssertEqual(byOffset[offsets["jpg"]!]?.category, .images)
        XCTAssertEqual(byOffset[offsets["png"]!]?.size, Int64(png.count))
    }

    func testRecoverWritesIdenticalBytesAndAvoidsOverwriting() throws {
        let (url, _) = try makeImage([("png", png)])
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: out) }
        let device = try RawDevice(path: url.path)
        var found = [RecoverableFile]()
        RecoveryEngine.scan(device: device, modes: [.deep], token: CancelToken()) { if case .found(let f) = $0 { found += f } }
        XCTAssertEqual(found.count, 1)

        for _ in 0..<2 { // la segunda recuperación no debe pisar la primera
            let report = RecoveryEngine.recover(found, from: device, to: out, token: CancelToken()) { _ in }
            XCTAssertEqual(report.recovered, 1)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
        XCTAssertEqual(names.count, 2)
        for name in names { XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent(name)), png) }
    }

    func testRandomDataProducesNoFiles() throws {
        var rng = SystemRandomNumberGenerator()
        let noise = Data((0..<(2 << 20)).map { _ in UInt8.random(in: 0...255, using: &rng) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".img")
        try noise.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var count = 0
        RecoveryEngine.scan(device: try RawDevice(path: url.path), modes: [.deep], token: CancelToken()) {
            if case .found(let f) = $0 { count += f.count }
        }
        XCTAssertEqual(count, 0)
    }

    func testCategoryByExtension() {
        XCTAssertEqual(FileCategory.forExtension("JPG"), .images)
        XCTAssertEqual(FileCategory.forExtension("mov"), .videos)
        XCTAssertEqual(FileCategory.forExtension("docx"), .documents)
        XCTAssertEqual(FileCategory.forExtension("xyz"), .other)
    }
}
