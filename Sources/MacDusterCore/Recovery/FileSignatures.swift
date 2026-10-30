import Foundation

/// Resultado de interpretar un candidato: longitud exacta y tipo final.
struct Resolution {
    let size: Int64
    let ext: String
    let category: FileCategory
}

/// Una firma de cabecera y la regla que determina dónde termina el archivo.
struct FileSignature {
    let magic: [UInt8]
    let offset: Int
    let minSize: Int64
    let maxSize: Int64
    /// Filtro barato sobre los bytes ya en memoria, para descartar antes de leer del disco.
    var prefilter: ((UnsafeRawBufferPointer, Int) -> Bool)?
    /// (dispositivo, inicio absoluto, longitud máxima) -> resolución.
    let resolve: (RawDevice, Int64, Int64) -> Resolution?

    init(magic: [UInt8], offset: Int = 0, minSize: Int64 = 1024, maxSize: Int64,
         prefilter: ((UnsafeRawBufferPointer, Int) -> Bool)? = nil,
         resolve: @escaping (RawDevice, Int64, Int64) -> Resolution?) {
        self.magic = magic
        self.offset = offset
        self.minSize = minSize
        self.maxSize = maxSize
        self.prefilter = prefilter
        self.resolve = resolve
    }
}

enum FileSignatures {
    private static let MB: Int64 = 1 << 20
    private static let GB: Int64 = 1 << 30

    static let all: [FileSignature] = [
        FileSignature(magic: [0xFF, 0xD8, 0xFF], minSize: 2048, maxSize: 100 * MB, resolve: Resolvers.jpeg),
        FileSignature(magic: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], maxSize: 200 * MB, resolve: Resolvers.png),
        FileSignature(magic: Array("GIF8".utf8), minSize: 128, maxSize: 100 * MB, resolve: Resolvers.gif),
        FileSignature(magic: Array("BM".utf8), minSize: 4096, maxSize: 200 * MB, resolve: Resolvers.bmp),
        FileSignature(magic: Array("ftyp".utf8), offset: 4, minSize: 4096, maxSize: 16 * GB, resolve: Resolvers.isoBMFF),
        FileSignature(magic: Array("RIFF".utf8), minSize: 4096, maxSize: 8 * GB, resolve: Resolvers.riff),
        FileSignature(magic: Array("%PDF-1.".utf8), minSize: 512, maxSize: 1 * GB, resolve: Resolvers.pdf),
        FileSignature(magic: [0x50, 0x4B, 0x03, 0x04], minSize: 100, maxSize: 4 * GB, resolve: Resolvers.zip),
        FileSignature(magic: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1], minSize: 2048, maxSize: 512 * MB, resolve: Resolvers.ole),
        FileSignature(magic: Array("{\\rtf".utf8), minSize: 64, maxSize: 64 * MB, resolve: Resolvers.rtf),
        FileSignature(magic: Array("SQLite format 3".utf8) + [0], minSize: 4096, maxSize: 4 * GB, resolve: Resolvers.sqlite),
        FileSignature(magic: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C], minSize: 64, maxSize: 8 * GB, resolve: Resolvers.sevenZip),
        FileSignature(magic: [0x1A, 0x45, 0xDF, 0xA3], minSize: 4096, maxSize: 16 * GB, resolve: Resolvers.matroska),
        FileSignature(magic: Array("ID3".utf8), minSize: 8192, maxSize: 256 * MB, resolve: Resolvers.mp3),
        FileSignature(magic: [0xFF, 0xFB], minSize: 16384, maxSize: 256 * MB,
                      prefilter: { Resolvers.mp3FrameLength($0, $1) != nil }, resolve: Resolvers.mp3),
        FileSignature(magic: [0xFF, 0xFA], minSize: 16384, maxSize: 256 * MB,
                      prefilter: { Resolvers.mp3FrameLength($0, $1) != nil }, resolve: Resolvers.mp3),
        FileSignature(magic: Array("fLaC".utf8) + [0, 0, 0, 0x22], minSize: 8192, maxSize: 512 * MB, resolve: Resolvers.flac),
        FileSignature(magic: Array("Rar!".utf8) + [0x1A, 0x07], minSize: 256, maxSize: 4 * GB, resolve: Resolvers.rar),
    ]

    /// Firmas con la cabecera al inicio, indexadas por su primer byte para no probarlas todas en cada sector.
    static let byFirstByte: [[Int]] = {
        var table = [[Int]](repeating: [], count: 256)
        for (i, s) in all.enumerated() where s.offset == 0 { table[Int(s.magic[0])].append(i) }
        return table
    }()

    /// Firmas cuya cabecera empieza más adentro (p. ej. `ftyp` en el byte 4).
    static let shifted: [Int] = all.indices.filter { all[$0].offset != 0 }
}

/// Búsqueda de un patrón de bytes en el dispositivo por bloques de 1 MiB.
enum Search {
    static func find(_ device: RawDevice, pattern: [UInt8], from: Int64, to: Int64) -> Int64? {
        let block = 1 << 20
        let needle = Data(pattern)
        let end = min(to, device.size)
        var pos = from
        while pos < end {
            let data = device.read(at: pos, length: min(block + pattern.count - 1, Int(end - pos)))
            if let r = data.range(of: needle) { return pos + Int64(r.lowerBound) }
            guard data.count > block else { return nil }
            pos += Int64(block)
        }
        return nil
    }
}

enum Resolvers {
    // MARK: Imágenes

    static func jpeg(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        let r = WindowReader(device: dev, start: start, maxLength: max)
        guard let m = r.u8(start + 3), (0xE0...0xEF).contains(m) || m == 0xDB || m == 0xFE else { return nil }
        var pos = start + 2
        while let b0 = r.u8(pos), let marker = r.u8(pos + 1) {
            guard b0 == 0xFF else { return nil }
            switch marker {
            case 0xD9: return Resolution(size: pos + 2 - start, ext: "jpg", category: .images)
            case 0xFF: pos += 1
            case 0x00: return nil
            case 0x01, 0xD0...0xD8: pos += 2
            default:
                guard let len = r.be16(pos + 2), len >= 2 else { return nil }
                pos += 2 + len
                if marker == 0xDA { // datos entropy-coded: hasta el siguiente marcador real
                    var p = pos
                    var next: Int64?
                    while let b = r.u8(p) {
                        if b == 0xFF, let n = r.u8(p + 1), n != 0x00, !(0xD0...0xD7).contains(n) { next = p; break }
                        p += 1
                    }
                    guard let found = next else { return nil }
                    pos = found
                }
            }
        }
        return nil
    }

    static func png(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        let r = WindowReader(device: dev, start: start, maxLength: max)
        guard r.be32(start + 8) == 13, r.bytes(start + 12, 4) == Array("IHDR".utf8) else { return nil }
        var pos = start + 8
        for _ in 0..<200_000 {
            guard let len = r.be32(pos), let type = r.bytes(pos + 4, 4),
                  type.allSatisfy({ ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) }) else { return nil }
            pos += 12 + len
            if type == Array("IEND".utf8) { return Resolution(size: pos - start, ext: "png", category: .images) }
            if pos - start > max { return nil }
        }
        return nil
    }

    static func gif(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        let r = WindowReader(device: dev, start: start, maxLength: max)
        guard let v = r.u8(start + 4), v == 0x37 || v == 0x39, r.u8(start + 5) == 0x61, let flags = r.u8(start + 10) else { return nil }
        var pos = start + 13
        if flags & 0x80 != 0 { pos += 3 << (Int64(flags & 7) + 1) }
        func skipSubBlocks(_ p: inout Int64) -> Bool {
            while let n = r.u8(p) {
                p += 1 + Int64(n)
                if n == 0 { return true }
            }
            return false
        }
        var frames = 0
        while let b = r.u8(pos) {
            switch b {
            case 0x3B:
                return frames > 0 ? Resolution(size: pos + 1 - start, ext: "gif", category: .images) : nil
            case 0x21:
                pos += 2
                guard skipSubBlocks(&pos) else { return nil }
            case 0x2C:
                guard let f = r.u8(pos + 9) else { return nil }
                pos += 10
                if f & 0x80 != 0 { pos += 3 << (Int64(f & 7) + 1) }
                pos += 1
                guard skipSubBlocks(&pos) else { return nil }
                frames += 1
            default: return nil
            }
        }
        return nil
    }

    static func bmp(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        let r = WindowReader(device: dev, start: start, maxLength: 64)
        guard let size = r.le32(start + 2), let dataOffset = r.le32(start + 10), let dib = r.le32(start + 14),
              r.bytes(start + 6, 4) == [0, 0, 0, 0], [12, 40, 52, 56, 64, 108, 124].contains(dib),
              size >= 4096, size <= max, dataOffset >= 26, dataOffset < size,
              let width = r.le32(start + 18), width > 0, width < 30_000 else { return nil }
        return Resolution(size: size, ext: "bmp", category: .images)
    }

    // MARK: Contenedores multimedia

    static func isoBMFF(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        let r = WindowReader(device: dev, start: start, maxLength: max)
        guard let ftypSize = r.be32(start), ftypSize >= 16, ftypSize <= 256,
              let brandBytes = r.bytes(start + 8, 4) else { return nil }
        let atoms: Set<String> = ["ftyp", "moov", "mdat", "free", "skip", "wide", "pnot", "uuid", "meta",
                                  "moof", "mfra", "sidx", "styp", "pdin", "junk"]
        var pos = start
        var hasIndex = false
        while let sizeField = r.be32(pos), let t = r.bytes(pos + 4, 4),
              let type = String(bytes: t, encoding: .ascii), atoms.contains(type) {
            var size = sizeField
            if sizeField == 1 {
                guard let hi = r.be32(pos + 8), let lo = r.be32(pos + 12) else { break }
                size = hi << 32 | lo
            }
            if size < 8 { break }
            if type == "moov" || type == "meta" || type == "moof" { hasIndex = true }
            pos += size
            if pos - start > max { return nil }
        }
        guard hasIndex, pos - start > 4096, pos <= dev.size else { return nil }
        let brand = String(bytes: brandBytes, encoding: .ascii) ?? ""
        let (ext, category): (String, FileCategory)
        switch brand {
        case "qt  ": (ext, category) = ("mov", .videos)
        case "M4A ", "M4B ": (ext, category) = ("m4a", .audio)
        case "heic", "heix", "hevc", "heim", "heis", "mif1", "msf1": (ext, category) = ("heic", .images)
        case "avif": (ext, category) = ("avif", .images)
        case "crx ": (ext, category) = ("cr3", .images)
        case "M4V ": (ext, category) = ("m4v", .videos)
        default: (ext, category) = brand.hasPrefix("3g") ? ("3gp", .videos) : ("mp4", .videos)
        }
        return Resolution(size: pos - start, ext: ext, category: category)
    }

    static func riff(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        let r = WindowReader(device: dev, start: start, maxLength: 16)
        guard let size = r.le32(start + 4), let kind = r.bytes(start + 8, 4),
              size >= 4, size + 8 <= max else { return nil }
        let total = size + 8
        switch String(bytes: kind, encoding: .ascii) {
        case "AVI ": return Resolution(size: total, ext: "avi", category: .videos)
        case "WAVE": return Resolution(size: total, ext: "wav", category: .audio)
        case "WEBP": return Resolution(size: total, ext: "webp", category: .images)
        default: return nil
        }
    }

    static func matroska(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        let r = WindowReader(device: dev, start: start, maxLength: max)
        /// Entero de longitud variable EBML: (valor, bytes usados).
        func vint(_ at: Int64) -> (Int64, Int64)? {
            guard let first = r.u8(at), first != 0 else { return nil }
            let length = first.leadingZeroBitCount + 1
            var value = Int64(first) & (0xFF >> length)
            var allOnes = value == Int64(0xFF >> length)
            for i in 1..<Swift.max(length, 1) {
                guard let b = r.u8(at + Int64(i)) else { return nil }
                value = value << 8 | Int64(b)
                if b != 0xFF { allOnes = false }
            }
            return allOnes ? nil : (value, Int64(length))
        }
        guard let (headerSize, headerLen) = vint(start + 4) else { return nil }
        let segment = start + 4 + headerLen + headerSize
        guard r.bytes(segment, 4) == [0x18, 0x53, 0x80, 0x67], let (segSize, segLen) = vint(segment + 4) else { return nil }
        let total = segment + 4 + segLen + segSize - start
        guard total > 4096, total <= max else { return nil }
        return Resolution(size: total, ext: "mkv", category: .videos)
    }

    // MARK: Documentos

    static func pdf(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        let r = WindowReader(device: dev, start: start, maxLength: max)
        let eof = Array("%%EOF".utf8)
        var pos = start + 8
        var end: Int64?
        // Un PDF con actualizaciones incrementales o linealizado tiene varios %%EOF.
        while let hit = Search.find(dev, pattern: eof, from: pos, to: start + max) {
            var e = hit + 5
            for _ in 0..<2 { if let b = r.u8(e), b == 0x0A || b == 0x0D { e += 1 } }
            end = e
            let next = String(decoding: r.bytes(e, 24) ?? [], as: UTF8.self)
            guard next.hasPrefix("xref") || next.range(of: #"^\d+ \d+ obj"#, options: .regularExpression) != nil else { break }
            pos = e
        }
        guard let e = end else { return nil }
        return Resolution(size: e - start, ext: "pdf", category: .documents)
    }

    static func zip(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        let r = WindowReader(device: dev, start: start, maxLength: max)
        guard let version = r.bytes(start + 4, 2), version[1] == 0, version[0] <= 63 else { return nil }
        var pos = start + 30
        while let hit = Search.find(dev, pattern: [0x50, 0x4B, 0x05, 0x06], from: pos, to: start + max) {
            // El directorio central debe terminar exactamente donde empieza este registro.
            if let cdSize = r.le32(hit + 12), let cdOffset = r.le32(hit + 16), cdOffset + cdSize == hit - start,
               let c = r.bytes(hit + 20, 2) {
                let total = hit - start + 22 + (Int64(c[0]) | Int64(c[1]) << 8)
                let (ext, category) = zipKind(dev.read(at: start, length: 65_536))
                return Resolution(size: total, ext: ext, category: category)
            }
            pos = hit + 4
        }
        return nil
    }

    private static func zipKind(_ head: Data) -> (String, FileCategory) {
        let text = String(data: head, encoding: .isoLatin1) ?? ""
        func has(_ s: String) -> Bool { text.contains(s) }
        if has("application/vnd.oasis.opendocument.text") { return ("odt", .documents) }
        if has("application/vnd.oasis.opendocument.spreadsheet") { return ("ods", .documents) }
        if has("application/vnd.oasis.opendocument.presentation") { return ("odp", .documents) }
        if has("application/epub+zip") { return ("epub", .documents) }
        if has("word/") { return ("docx", .documents) }
        if has("xl/") { return ("xlsx", .documents) }
        if has("ppt/") { return ("pptx", .documents) }
        if has("AndroidManifest.xml") { return ("apk", .archives) }
        if has("META-INF/MANIFEST.MF") { return ("jar", .archives) }
        return ("zip", .archives)
    }

    /// Documentos de Office antiguos: contenedor OLE/CFB. El tamaño sale del último sector usado de la FAT.
    static func ole(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        let r = WindowReader(device: dev, start: start, maxLength: max)
        guard r.bytes(start + 28, 2) == [0xFE, 0xFF], let shift = r.u8(start + 30), shift == 9 || shift == 12,
              let fatCount = r.le32(start + 44), let firstDir = r.le32(start + 48), fatCount > 0, fatCount < 4096 else { return nil }
        let ss = Int64(1) << Int64(shift)
        let free: Int64 = 0xFFFF_FFFF, endOfChain: Int64 = 0xFFFF_FFFE
        func sectorOffset(_ n: Int64) -> Int64 { start + (n + 1) * ss }

        var fatSectors = [Int64]()
        for i in 0..<Int64(109) {
            guard let s = r.le32(start + 76 + 4 * i) else { return nil }
            if s < 0xFFFF_FFF0 { fatSectors.append(s) }
        }
        if fatSectors.count < Int(fatCount) { // lista DIFAT adicional
            guard var next = r.le32(start + 68) else { return nil }
            var guardCount = 0
            while next < 0xFFFF_FFF0, guardCount < 64 {
                for i in 0..<(ss / 4 - 1) {
                    guard let s = r.le32(sectorOffset(next) + 4 * i) else { return nil }
                    if s < 0xFFFF_FFF0 { fatSectors.append(s) }
                }
                guard let n = r.le32(sectorOffset(next) + ss - 4) else { return nil }
                next = n
                guardCount += 1
            }
        }
        var fat = [Int64]()
        var highest: Int64 = 0
        for s in fatSectors.prefix(Int(fatCount)) {
            for i in 0..<(ss / 4) {
                guard let v = r.le32(sectorOffset(s) + 4 * i) else { return nil }
                if v != free { highest = Int64(fat.count) }
                fat.append(v)
            }
        }
        let total = (highest + 2) * ss
        guard total >= 2 * ss, total <= max else { return nil }

        // Tipo de documento a partir de los nombres de los streams del directorio.
        var sector = firstDir
        var visited = 0
        while sector < endOfChain, Int(sector) < fat.count, visited < 64 {
            for e in 0..<(ss / 128) {
                let entry = sectorOffset(sector) + e * 128
                guard let lenBytes = r.bytes(entry + 64, 2) else { return nil }
                let nameLen = Int(lenBytes[0]) | Int(lenBytes[1]) << 8
                guard nameLen >= 2, nameLen <= 64, let raw = r.bytes(entry, nameLen - 2) else { continue }
                let name = String(data: Data(raw), encoding: .utf16LittleEndian) ?? ""
                switch name {
                case "WordDocument": return Resolution(size: total, ext: "doc", category: .documents)
                case "Workbook", "Book": return Resolution(size: total, ext: "xls", category: .documents)
                case "PowerPoint Document": return Resolution(size: total, ext: "ppt", category: .documents)
                default: break
                }
            }
            sector = fat[Int(sector)]
            visited += 1
        }
        return nil
    }

    static func rtf(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        let r = WindowReader(device: dev, start: start, maxLength: max)
        guard r.bytes(start + 5, 1) == [0x31] else { return nil }
        var depth = 0, pos = start
        var escaped = false
        while let b = r.u8(pos) {
            pos += 1
            if escaped { escaped = false; continue }
            switch b {
            case 0x5C: escaped = true
            case 0x7B: depth += 1
            case 0x7D:
                depth -= 1
                if depth == 0 { return Resolution(size: pos - start, ext: "rtf", category: .documents) }
            default: break
            }
        }
        return nil
    }

    static func sqlite(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        let r = WindowReader(device: dev, start: start, maxLength: 128)
        guard var pageSize = r.be16(start + 16), let pages = r.be32(start + 28), pages > 0 else { return nil }
        if pageSize == 1 { pageSize = 65_536 }
        guard pageSize >= 512, pageSize & (pageSize - 1) == 0, pageSize * pages <= max else { return nil }
        return Resolution(size: pageSize * pages, ext: "sqlite", category: .documents)
    }

    // MARK: Archivos y audio

    static func sevenZip(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        let r = WindowReader(device: dev, start: start, maxLength: 64)
        guard let offset = r.le64(start + 12), let size = r.le64(start + 20), offset >= 0, size > 0 else { return nil }
        let total = 32 + offset + size
        guard total > 32, total <= max else { return nil }
        return Resolution(size: total, ext: "7z", category: .archives)
    }

    static func mp3FrameLength(_ buf: UnsafeRawBufferPointer, _ i: Int) -> Int64? {
        frameLength(buf[i], buf[i + 1], buf[i + 2])
    }

    private static func frameLength(_ h0: UInt8, _ h1: UInt8, _ h2: UInt8) -> Int64? {
        guard h0 == 0xFF, h1 & 0xE0 == 0xE0, (h1 >> 1) & 3 == 1 else { return nil } // solo Layer III
        let version = Int((h1 >> 3) & 3) // 3 = MPEG1, 2 = MPEG2, 0 = MPEG2.5
        guard version != 1 else { return nil }
        let bitrateIndex = Int(h2 >> 4), rateIndex = Int((h2 >> 2) & 3)
        guard bitrateIndex > 0, bitrateIndex < 15, rateIndex < 3 else { return nil }
        let v1Bitrates = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
        let v2Bitrates = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]
        let rates = version == 3 ? [44_100, 48_000, 32_000] : (version == 2 ? [22_050, 24_000, 16_000] : [11_025, 12_000, 8_000])
        let bitrate = (version == 3 ? v1Bitrates : v2Bitrates)[bitrateIndex] * 1000
        let padding = Int((h2 >> 1) & 1)
        return Int64((version == 3 ? 144 : 72) * bitrate / rates[rateIndex] + padding)
    }

    static func mp3(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        let r = WindowReader(device: dev, start: start, maxLength: max)
        var pos = start
        let tagged = r.bytes(start, 3) == Array("ID3".utf8)
        if tagged {
            guard let flags = r.u8(start + 5), let s = r.bytes(start + 6, 4), s.allSatisfy({ $0 < 0x80 }) else { return nil }
            let size = s.reduce(Int64(0)) { $0 << 7 | Int64($1) }
            pos = start + 10 + size + (flags & 0x10 != 0 ? 10 : 0)
        }
        var frames = 0
        while let h = r.bytes(pos, 3), let len = frameLength(h[0], h[1], h[2]) {
            pos += len
            frames += 1
        }
        guard frames >= (tagged ? 8 : 24) else { return nil }
        if r.bytes(pos, 3) == Array("TAG".utf8) { pos += 128 }
        return Resolution(size: pos - start, ext: "mp3", category: .audio)
    }

    /// Formatos sin tamaño en la cabecera: se corta en el primer bloque de 64 KiB completamente a cero.
    private static func untilZeros(_ dev: RawDevice, _ start: Int64, _ max: Int64, ext: String, category: FileCategory) -> Resolution? {
        let block = 65_536
        var pos = start
        while pos - start < max {
            let data = dev.read(at: pos, length: block)
            if data.isEmpty { break }
            if !data.contains(where: { $0 != 0 }) { break }
            pos += Int64(data.count)
            if data.count < block { break }
        }
        return pos - start > 8192 ? Resolution(size: pos - start, ext: ext, category: category) : nil
    }

    static func flac(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        untilZeros(dev, start, max, ext: "flac", category: .audio)
    }

    static func rar(_ dev: RawDevice, _ start: Int64, _ max: Int64) -> Resolution? {
        untilZeros(dev, start, max, ext: "rar", category: .archives)
    }
}
