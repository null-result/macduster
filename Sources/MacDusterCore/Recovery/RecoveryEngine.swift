import Foundation

public struct RecoveryReport {
    public var recovered = 0
    public var bytes: Int64 = 0
    public var failures: [(name: String, reason: String)] = []
}

public enum RecoveryEngine {
    /// Abre el dispositivo en bruto. Si macOS niega la lectura se pide la contraseña de administrador
    /// una vez para asignar el nodo de dispositivo al usuario actual (se revierte al reiniciar o expulsar el disco).
    public static func open(_ volume: DiskVolume) throws -> RawDevice {
        do {
            return try RawDevice(path: volume.rawPath)
        } catch RecoveryError.cannotOpen(_, let code) where code == EACCES || code == EPERM {
            let grant = Shell.runAsAdmin("/usr/sbin/chown \(NSUserName()) \(volume.rawPath)")
            guard grant.ok else { throw RecoveryError.cannotOpen(volume.rawPath, code) }
            return try RawDevice(path: volume.rawPath)
        }
    }

    /// Escanea el dispositivo. El escaneo rápido (si el sistema de archivos lo permite) conserva nombres y
    /// carpetas; el profundo reconstruye por firma lo que quede y descarta lo que ya apareció en el rápido
    /// o pertenece a archivos que siguen existiendo.
    public static func scan(device: RawDevice, modes: Set<ScanMode>, token: CancelToken,
                            handler: @escaping (ScanEvent) -> Void) {
        var known = [Extent]()
        if modes.contains(.quick) {
            handler(.phase("Leyendo el sistema de archivos…"))
            if let quick = QuickScan.scan(device: device, token: token) {
                handler(.found(quick.deleted))
                known = QuickScan.mergeSorted(quick.live + quick.deleted.flatMap(\.extents))
            } else if !modes.contains(.deep) {
                handler(.phase("Escaneo rápido no disponible para este formato; usa el profundo."))
            }
        }
        guard modes.contains(.deep), !token.isCancelled else { return }
        handler(.phase("Buscando archivos por firma…"))
        SignatureCarver.scan(device: device, token: token,
                             isKnown: { offset in contains(known, offset) },
                             progress: { handler(.progress($0)) },
                             emit: { handler(.found($0)) })
    }

    private static func contains(_ sorted: [Extent], _ offset: Int64) -> Bool {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid].offset <= offset { lo = mid + 1 } else { hi = mid }
        }
        guard lo > 0 else { return false }
        let e = sorted[lo - 1]
        return offset < e.offset + e.length
    }

    /// El destino nunca puede estar en el disco que se recupera: escribir ahí sobrescribiría los datos perdidos.
    public static func destinationConflicts(_ folder: URL, with volume: DiskVolume) -> Bool {
        DiskCatalog.backingIdentifiers(of: folder).contains(volume.identifier)
    }

    public static func recover(_ files: [RecoverableFile], from device: RawDevice, to folder: URL,
                               token: CancelToken, progress: (Int64) -> Void) -> RecoveryReport {
        var report = RecoveryReport()
        let fm = FileManager.default
        var done: Int64 = 0
        for file in files where !token.isCancelled {
            let target = uniqueURL(for: file, in: folder)
            guard fm.createFile(atPath: target.path, contents: nil), let out = try? FileHandle(forWritingTo: target) else {
                report.failures.append((file.name, RecoveryError.cannotCreate(file.name).localizedDescription))
                continue
            }
            var remaining = file.size
            var failed = false
            extents: for extent in file.extents {
                var offset = extent.offset
                let end = extent.offset + min(extent.length, remaining)
                while offset < end {
                    if token.isCancelled { failed = true; break extents }
                    let data = device.read(at: offset, length: Int(min(4 << 20, end - offset)))
                    if data.isEmpty { failed = true; break extents }
                    out.write(data)
                    offset += Int64(data.count)
                    remaining -= Int64(data.count)
                    done += Int64(data.count)
                    progress(done)
                }
            }
            try? out.close()
            if failed || remaining > 0 {
                try? fm.removeItem(at: target)
                report.failures.append((file.name, "No se pudo leer todo el contenido"))
            } else {
                report.recovered += 1
                report.bytes += file.size
            }
        }
        return report
    }

    private static func uniqueURL(for file: RecoverableFile, in folder: URL) -> URL {
        let safe = file.name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let base = (safe as NSString).deletingPathExtension, ext = (safe as NSString).pathExtension
        var url = folder.appendingPathComponent(safe)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }
}
