import Foundation

public enum RecoveryError: LocalizedError {
    case cannotOpen(String, Int32)
    case destinationOnSource
    case cannotCreate(String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let path, let code):
            let reason = code == EACCES || code == EPERM
                ? "Sin permiso de lectura. Concede «Acceso total al disco» a MacDuster."
                : String(cString: strerror(code))
            return "No se puede abrir \(path): \(reason)"
        case .destinationOnSource:
            return "La carpeta de destino está en el disco que se está recuperando. Elige otro disco."
        case .cannotCreate(let name):
            return "No se puede crear «\(name)» en la carpeta de destino."
        }
    }
}

/// Lectura de solo lectura sobre un dispositivo de bloques (`/dev/rdiskN`) o una imagen.
/// Los dispositivos en bruto exigen lecturas alineadas al sector, así que todo se alinea a 4 KiB.
public final class RawDevice {
    public let path: String
    public let size: Int64
    private let fd: Int32
    private static let alignment = 4096

    public init(path: String) throws {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { throw RecoveryError.cannotOpen(path, errno) }
        var info = stat()
        fstat(fd, &info)
        var size = Int64(info.st_size)
        if info.st_mode & 0o170000 != 0o100000 { // no es un archivo normal: preguntar al driver
            var blockSize: UInt32 = 0
            var blockCount: UInt64 = 0
            // DKIOCGETBLOCKSIZE / DKIOCGETBLOCKCOUNT
            if ioctl(fd, 0x4004_6418, &blockSize) == 0, ioctl(fd, 0x4008_6419, &blockCount) == 0 {
                size = Int64(blockSize) * Int64(blockCount)
            }
        }
        self.path = path
        self.fd = fd
        self.size = size
    }

    deinit { close(fd) }

    /// Lee hasta `length` bytes desde `offset`. Los sectores ilegibles se devuelven a cero.
    public func read(at offset: Int64, length: Int) -> Data {
        guard offset >= 0, offset < size, length > 0 else { return Data() }
        let length = Int(min(Int64(length), size - offset))
        let align = Int64(Self.alignment)
        let start = offset & ~(align - 1)
        let lead = Int(offset - start)
        let total = (lead + length + Self.alignment - 1) / Self.alignment * Self.alignment
        var buffer = [UInt8](repeating: 0, count: total)
        let got = fill(&buffer, from: start)
        guard got > lead else { return Data() }
        return Data(buffer[lead..<min(got, lead + length)])
    }

    /// Devuelve los bytes leídos; si un tramo falla lo reintenta por bloques pequeños dejando ceros.
    private func fill(_ buffer: inout [UInt8], from start: Int64) -> Int {
        let total = buffer.count
        let n = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, total, off_t(start)) }
        if n >= 0 { return n }
        var done = 0
        let piece = Self.alignment * 16
        while done < total {
            let want = min(piece, total - done)
            let r = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress!.advanced(by: done), want, off_t(start) + off_t(done)) }
            if r <= 0 { if r == 0 { break } } // r < 0: sector malo, se deja a cero
            done += r > 0 ? r : want
        }
        return min(done, total)
    }
}

/// Permite cancelar un escaneo o una recuperación desde otro hilo.
public final class CancelToken {
    private let lock = NSLock()
    private var flag = false
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    public func cancel() { lock.lock(); flag = true; lock.unlock() }
}

/// Lector con ventana de 1 MiB para recorrer estructuras de archivo sin una lectura por byte.
final class WindowReader {
    let device: RawDevice
    let limit: Int64
    private var base: Int64 = -1
    private var buffer = Data()
    private static let windowSize = 1 << 20

    init(device: RawDevice, start: Int64, maxLength: Int64) {
        self.device = device
        self.limit = min(device.size, start + maxLength)
    }

    func u8(_ offset: Int64) -> UInt8? {
        guard offset >= 0, offset < limit else { return nil }
        if offset < base || offset >= base + Int64(buffer.count) {
            base = offset
            buffer = device.read(at: offset, length: Self.windowSize)
            if buffer.isEmpty { base = -1; return nil }
        }
        return buffer[buffer.startIndex + Int(offset - base)]
    }

    func bytes(_ offset: Int64, _ count: Int) -> [UInt8]? {
        var out = [UInt8]()
        out.reserveCapacity(count)
        for i in 0..<Int64(count) {
            guard let b = u8(offset + i) else { return nil }
            out.append(b)
        }
        return out
    }

    func be16(_ o: Int64) -> Int64? { bytes(o, 2).map { Int64($0[0]) << 8 | Int64($0[1]) } }
    func be32(_ o: Int64) -> Int64? { bytes(o, 4).map { $0.reduce(0) { $0 << 8 | Int64($1) } } }
    func le32(_ o: Int64) -> Int64? { bytes(o, 4).map { $0.reversed().reduce(0) { $0 << 8 | Int64($1) } } }
    func le64(_ o: Int64) -> Int64? { bytes(o, 8).map { $0.reversed().reduce(0) { $0 << 8 | Int64($1 & 0xFF) } } }
}
