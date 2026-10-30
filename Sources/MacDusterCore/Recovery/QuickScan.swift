import Foundation

/// Lo que el escaneo rápido sabe del volumen: archivos borrados y zonas ocupadas por archivos vivos.
struct QuickScanResult {
    var deleted: [RecoverableFile] = []
    var live: [Extent] = []
}

private func le16(_ d: Data, _ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 }
private func le32(_ d: Data, _ o: Int) -> Int { le16(d, o) | le16(d, o + 2) << 16 }
private func le64(_ d: Data, _ o: Int) -> Int64 { Int64(le32(d, o)) | Int64(le32(d, o + 4)) << 32 }

/// Recorre los directorios de un volumen FAT32 o exFAT y recupera las entradas marcadas como borradas.
/// Al borrar, estos sistemas solo marcan la entrada y liberan los clústeres: el contenido sigue ahí
/// hasta que se reutiliza el espacio.
enum QuickScan {
    private static let maxTableBytes = 512 << 20

    /// Nombre del sistema de archivos si el escaneo rápido lo soporta.
    static func detect(_ device: RawDevice) -> String? {
        let boot = device.read(at: 0, length: 512)
        guard boot.count == 512 else { return nil }
        if boot[3..<11].elementsEqual(Array("EXFAT   ".utf8)) { return "exFAT" }
        if boot[510] == 0x55, boot[511] == 0xAA, boot[82..<87].elementsEqual(Array("FAT32".utf8)) { return "FAT32" }
        return nil
    }

    static func scan(device: RawDevice, token: CancelToken) -> QuickScanResult? {
        switch detect(device) {
        case "exFAT": return ExFATReader(device: device, token: token)?.run()
        case "FAT32": return FAT32Reader(device: device, token: token)?.run()
        default: return nil
        }
    }

    fileprivate static func file(named name: String, folder: String, extents: [Extent], size: Int64, free: Bool) -> RecoverableFile {
        let ext = (name as NSString).pathExtension
        return RecoverableFile(name: name, folder: folder, category: FileCategory.forExtension(ext),
                               offset: extents[0].offset, size: size, extents: extents,
                               source: .quick, chance: free ? .high : .low)
    }

    /// Une tramos consecutivos para describir una cadena de clústeres con pocos extents.
    static func merge(_ extents: [Extent]) -> [Extent] {
        var out = [Extent]()
        for e in extents {
            if let last = out.last, last.offset + last.length == e.offset {
                out[out.count - 1] = Extent(offset: last.offset, length: last.length + e.length)
            } else {
                out.append(e)
            }
        }
        return out
    }

    static func mergeSorted(_ extents: [Extent]) -> [Extent] {
        merge(extents.sorted { $0.offset < $1.offset })
    }

    /// Recorta los extents a `size` bytes (el último clúster está solo parcialmente ocupado).
    fileprivate static func trim(_ extents: [Extent], to size: Int64) -> [Extent] {
        var remaining = size
        var out = [Extent]()
        for e in extents where remaining > 0 {
            let take = min(e.length, remaining)
            out.append(Extent(offset: e.offset, length: take))
            remaining -= take
        }
        return out
    }
}

// MARK: - FAT32

private final class FAT32Reader {
    let device: RawDevice
    let token: CancelToken
    let bytesPerCluster: Int
    let dataStart: Int64
    let clusterCount: Int
    let rootCluster: Int
    var fat = Data()
    var result = QuickScanResult()
    var visited = Set<Int>()

    init?(device: RawDevice, token: CancelToken) {
        let boot = device.read(at: 0, length: 512)
        guard boot.count == 512 else { return nil }
        let bps = le16(boot, 11), spc = Int(boot[13]), reserved = le16(boot, 14), fats = Int(boot[16])
        let fatSectors = le32(boot, 36)
        let total = le32(boot, 32) != 0 ? le32(boot, 32) : le16(boot, 19)
        guard [512, 1024, 2048, 4096].contains(bps), spc > 0, spc & (spc - 1) == 0, fats > 0, fatSectors > 0,
              fatSectors * bps <= 512 << 20 else { return nil }
        self.device = device
        self.token = token
        bytesPerCluster = bps * spc
        dataStart = Int64(reserved + fats * fatSectors) * Int64(bps)
        clusterCount = max(0, (total * bps - Int(dataStart)) / bytesPerCluster)
        rootCluster = le32(boot, 44)
        fat = device.read(at: Int64(reserved * bps), length: fatSectors * bps)
    }

    private func next(_ cluster: Int) -> Int? {
        let o = cluster * 4
        guard cluster >= 2, o + 4 <= fat.count else { return nil }
        return le32(fat, o) & 0x0FFF_FFFF
    }

    private func offset(of cluster: Int) -> Int64 { dataStart + Int64(cluster - 2) * Int64(bytesPerCluster) }
    private func valid(_ cluster: Int) -> Bool { cluster >= 2 && cluster < clusterCount + 2 }

    private func chain(from first: Int) -> [Int] {
        var out = [Int]()
        var c = first
        while valid(c), out.count <= clusterCount, !token.isCancelled {
            out.append(c)
            guard let n = next(c), n != c else { break }
            c = n
        }
        return out
    }

    func run() -> QuickScanResult {
        var jobs: [(clusters: [Int], path: String)] = [(chain(from: rootCluster), "")]
        while let job = jobs.popLast(), !token.isCancelled {
            var dir = Data()
            for c in job.clusters { dir.append(device.read(at: offset(of: c), length: bytesPerCluster)) }
            parse(dir, path: job.path, into: &jobs)
        }
        result.live = QuickScan.mergeSorted(result.live)
        return result
    }

    private func parse(_ dir: Data, path: String, into jobs: inout [(clusters: [Int], path: String)]) {
        var parts = [[UInt16]]()
        var i = 0
        while i + 32 <= dir.count {
            defer { i += 32 }
            let first = dir[i], attr = dir[i + 11]
            if first == 0x00 { break }
            if attr == 0x0F { // entrada de nombre largo: 13 caracteres UTF-16
                var chars = [UInt16]()
                for o in [1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30] { chars.append(UInt16(le16(dir, i + o))) }
                parts.append(chars)
                continue
            }
            defer { parts = [] }
            if attr & 0x08 != 0 { continue } // etiqueta de volumen
            let deleted = first == 0xE5
            let name = displayName(dir, at: i, longParts: parts, deleted: deleted)
            if name == "." || name == ".." { continue }

            let start = (le16(dir, i + 20) << 16) | le16(dir, i + 26)
            let size = Int64(le32(dir, i + 28))
            if attr & 0x10 != 0 {
                guard valid(start), visited.insert(start).inserted else { continue }
                let sub = path.isEmpty ? name : path + "/" + name
                jobs.append((deleted ? [start] : chain(from: start), sub))
                continue
            }
            guard size > 0, valid(start) else { continue }
            if deleted {
                // La cadena se pierde al borrar: se asume contigua. Si la FAT sigue libre ahí, el contenido está intacto.
                let needed = Int((size + Int64(bytesPerCluster) - 1) / Int64(bytesPerCluster))
                guard start + needed <= clusterCount + 2, offset(of: start) + size <= device.size else { continue }
                let free = (0..<needed).allSatisfy { next(start + $0) == 0 }
                result.deleted.append(QuickScan.file(named: name, folder: path,
                                                     extents: [Extent(offset: offset(of: start), length: size)],
                                                     size: size, free: free))
            } else {
                result.live += chain(from: start).map { Extent(offset: offset(of: $0), length: Int64(bytesPerCluster)) }
            }
        }
    }

    private func displayName(_ dir: Data, at i: Int, longParts: [[UInt16]], deleted: Bool) -> String {
        if !longParts.isEmpty {
            // Se escriben de la última a la primera: invertir para leerlas en orden.
            let units = longParts.reversed().flatMap { $0 }.prefix { $0 != 0 && $0 != 0xFFFF }
            let text = String(decoding: Array(units), as: UTF16.self)
            if !text.isEmpty { return text }
        }
        var bytes = Array(dir[i..<(i + 11)])
        if deleted { bytes[0] = UInt8(ascii: "_") }
        let lowerBase = dir[i + 12] & 0x08 != 0, lowerExt = dir[i + 12] & 0x10 != 0
        func text(_ slice: ArraySlice<UInt8>, lower: Bool) -> String {
            let s = String(decoding: slice, as: Unicode.ASCII.self).trimmingCharacters(in: .whitespaces)
            return lower ? s.lowercased() : s
        }
        let base = text(bytes[0..<8], lower: lowerBase), ext = text(bytes[8..<11], lower: lowerExt)
        return ext.isEmpty ? base : base + "." + ext
    }
}

// MARK: - exFAT

private final class ExFATReader {
    let device: RawDevice
    let token: CancelToken
    let bytesPerCluster: Int
    let heapStart: Int64
    let clusterCount: Int
    let rootCluster: Int
    let fatStart: Int64
    var fat = Data()
    var bitmap = Data()
    var result = QuickScanResult()
    var visited = Set<Int>()

    struct Job {
        var first: Int
        var contiguous: Bool
        var length: Int64
        var path: String
    }

    init?(device: RawDevice, token: CancelToken) {
        let boot = device.read(at: 0, length: 512)
        guard boot.count == 512 else { return nil }
        let bpsShift = Int(boot[108]), spcShift = Int(boot[109])
        guard (9...12).contains(bpsShift), spcShift <= 25 - bpsShift else { return nil }
        let bps = 1 << bpsShift
        self.device = device
        self.token = token
        bytesPerCluster = bps << spcShift
        fatStart = Int64(le32(boot, 80)) * Int64(bps)
        heapStart = Int64(le32(boot, 88)) * Int64(bps)
        clusterCount = le32(boot, 92)
        rootCluster = le32(boot, 96)
        let fatBytes = min(le32(boot, 84) * bps, ExFATReader.maxTable(clusterCount))
        fat = device.read(at: fatStart, length: fatBytes)
    }

    private static func maxTable(_ clusters: Int) -> Int { min((clusters + 2) * 4, 512 << 20) }

    private func offset(of cluster: Int) -> Int64 { heapStart + Int64(cluster - 2) * Int64(bytesPerCluster) }
    private func valid(_ cluster: Int) -> Bool { cluster >= 2 && cluster < clusterCount + 2 }

    private func chain(from first: Int) -> [Int] {
        var out = [Int]()
        var c = first
        while valid(c), out.count <= clusterCount, !token.isCancelled {
            out.append(c)
            let o = c * 4
            guard o + 4 <= fat.count else { break }
            let n = le32(fat, o)
            if n == c { break }
            c = n
        }
        return out
    }

    private func isFree(_ cluster: Int) -> Bool {
        let bit = cluster - 2
        guard bit >= 0, bit / 8 < bitmap.count else { return true }
        return bitmap[bit / 8] & (1 << UInt8(bit % 8)) == 0
    }

    /// Extents de datos de una entrada: contiguos (NoFatChain) o siguiendo la FAT.
    private func extents(first: Int, size: Int64, contiguous: Bool) -> [Extent]? {
        guard valid(first), size > 0 else { return nil }
        let needed = Int((size + Int64(bytesPerCluster) - 1) / Int64(bytesPerCluster))
        var clusters: [Int]
        if contiguous {
            clusters = Array(first..<(first + needed))
        } else {
            clusters = chain(from: first)
            if clusters.count < needed { clusters = Array(first..<(first + needed)) } // cadena perdida: asumir contiguo
            clusters = Array(clusters.prefix(needed))
        }
        guard let last = clusters.last, valid(last) else { return nil }
        let raw = clusters.map { Extent(offset: offset(of: $0), length: Int64(bytesPerCluster)) }
        return QuickScan.trim(QuickScan.merge(raw), to: size)
    }

    func run() -> QuickScanResult {
        let rootChain = chain(from: rootCluster)
        var root = Data()
        for c in rootChain { root.append(device.read(at: offset(of: c), length: bytesPerCluster)) }
        loadBitmap(from: root)

        var stack: [(data: Data, path: String)] = [(root, "")]
        while !token.isCancelled, let dir = stack.popLast() {
            var found = [Job]()
            parse(dir.data, path: dir.path, into: &found)
            stack += found.map { (read($0), $0.path) }
        }
        result.live = QuickScan.mergeSorted(result.live)
        return result
    }

    private func read(_ job: Job) -> Data {
        if job.contiguous {
            return device.read(at: offset(of: job.first), length: Int(min(job.length, 64 << 20)))
        }
        var data = Data()
        for c in chain(from: job.first).prefix(1 << 16) { data.append(device.read(at: offset(of: c), length: bytesPerCluster)) }
        return data
    }

    private func loadBitmap(from root: Data) {
        var i = 0
        while i + 32 <= root.count, root[i] != 0x00 {
            if root[i] == 0x81 {
                let length = Int(le64(root, i + 24))
                if length > 0, length <= 1 << 28 {
                    var data = Data()
                    for c in chain(from: le32(root, i + 20)) where data.count < length {
                        data.append(device.read(at: offset(of: c), length: bytesPerCluster))
                    }
                    bitmap = data
                }
                return
            }
            i += 32
        }
    }

    private func parse(_ dir: Data, path: String, into jobs: inout [Job]) {
        var i = 0
        while i + 32 <= dir.count {
            let type = dir[i]
            if type == 0x00 { break }
            guard type == 0x85 || type == 0x05 else { i += 32; continue }
            let secondary = Int(dir[i + 1])
            let end = i + 32 * (1 + secondary)
            defer { i = max(end, i + 32) }
            guard secondary >= 2, end <= dir.count, dir[i + 32] & 0x7F == 0x40 else { continue }

            let deleted = type == 0x05
            let isDirectory = le16(dir, i + 4) & 0x10 != 0
            let s = i + 32
            let contiguous = dir[s + 1] & 0x02 != 0
            let nameLength = Int(dir[s + 3])
            let first = le32(dir, s + 20)
            let size = le64(dir, s + 24)

            var units = [UInt16]()
            var n = s + 32
            while n < end { for o in stride(from: 2, to: 32, by: 2) { units.append(UInt16(le16(dir, n + o))) }; n += 32 }
            let name = String(decoding: units.prefix(nameLength), as: UTF16.self)
            guard !name.isEmpty else { continue }

            if isDirectory {
                if valid(first), visited.insert(first).inserted {
                    jobs.append(Job(first: first, contiguous: contiguous || deleted, length: size > 0 ? size : Int64(bytesPerCluster),
                                    path: path.isEmpty ? name : path + "/" + name))
                }
                continue
            }
            guard let parts = extents(first: first, size: size, contiguous: contiguous) else { continue }
            if deleted {
                let clusters = parts.flatMap { e -> [Int] in
                    let from = Int((e.offset - heapStart) / Int64(bytesPerCluster)) + 2
                    return Array(from..<(from + Int((e.length + Int64(bytesPerCluster) - 1) / Int64(bytesPerCluster))))
                }
                result.deleted.append(QuickScan.file(named: name, folder: path, extents: parts, size: size,
                                                     free: clusters.allSatisfy(isFree)))
            } else {
                result.live += parts
            }
        }
    }
}
