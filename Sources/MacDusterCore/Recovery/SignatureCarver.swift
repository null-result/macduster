import Foundation

/// Escaneo profundo: recorre el dispositivo sector a sector buscando cabeceras conocidas
/// y reconstruye cada archivo a partir de su propia estructura interna.
enum SignatureCarver {
    private static let chunkSize = 4 << 20
    private static let sector = 512

    /// - Parameter isKnown: devuelve true si el offset ya pertenece a un archivo encontrado por el escaneo rápido.
    static func scan(device: RawDevice, token: CancelToken, isKnown: (Int64) -> Bool,
                     progress: (Double) -> Void, emit: ([RecoverableFile]) -> Void) {
        let signatures = FileSignatures.all
        var counters = [FileCategory: Int]()
        var batch = [RecoverableFile]()
        var lastFlush = Date()
        var skipUntil: Int64 = 0
        var pos: Int64 = 0

        func flush(force: Bool = false) {
            guard !batch.isEmpty, force || batch.count >= 200 || Date().timeIntervalSince(lastFlush) > 0.25 else { return }
            emit(batch)
            batch.removeAll(keepingCapacity: true)
            lastFlush = Date()
        }

        while pos < device.size, !token.isCancelled {
            let data = device.read(at: pos, length: chunkSize)
            if data.isEmpty { pos += Int64(chunkSize); continue }

            data.withUnsafeBytes { buf in
                var i = 0
                let last = buf.count - 16
                while i <= last {
                    let absolute = pos + Int64(i)
                    defer { i += sector }
                    if absolute < skipUntil { continue }

                    var candidates = FileSignatures.byFirstByte[Int(buf[i])]
                    for s in FileSignatures.shifted where buf[i + signatures[s].offset] == signatures[s].magic[0] {
                        candidates.append(s)
                    }
                    for index in candidates {
                        let sig = signatures[index]
                        guard matches(sig, buf, i) else { continue }
                        if let filter = sig.prefilter, !filter(buf, i) { continue }
                        let room = min(sig.maxSize, device.size - absolute)
                        guard let found = sig.resolve(device, absolute, room),
                              found.size >= sig.minSize, found.size <= room else { continue }
                        skipUntil = absolute + (found.size + Int64(sector) - 1) / Int64(sector) * Int64(sector)
                        if !isKnown(absolute) {
                            let n = (counters[found.category] ?? 0) + 1
                            counters[found.category] = n
                            batch.append(RecoverableFile(name: "\(found.category.namePrefix) \(n).\(found.ext)",
                                                         category: found.category, offset: absolute,
                                                         size: found.size, source: .deep))
                        }
                        break
                    }
                }
            }
            flush()
            progress(Double(pos) / Double(device.size))
            pos = max(pos + Int64(chunkSize), skipUntil)
        }
        flush(force: true)
        progress(1)
    }

    private static func matches(_ sig: FileSignature, _ buf: UnsafeRawBufferPointer, _ i: Int) -> Bool {
        for (k, byte) in sig.magic.enumerated() where buf[i + sig.offset + k] != byte { return false }
        return true
    }
}
