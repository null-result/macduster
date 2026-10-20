import Foundation
import IOKit

/// Lectura de sensores del SMC (solo Macs Intel; en Apple Silicon devuelve nil).
public enum Temperature {
    private typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                               UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0; var attributes: UInt8 = 0; var pad: (UInt8, UInt8, UInt8) = (0, 0, 0) }
    private struct KeyData {
        var key: UInt32 = 0
        var vers = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let connection: io_connect_t? = {
        guard MemoryLayout<KeyData>.stride == 80 else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        return IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS ? conn : nil
    }()

    private static func call(_ input: inout KeyData, _ conn: io_connect_t) -> KeyData? {
        var output = KeyData()
        var size = MemoryLayout<KeyData>.stride
        let result = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<KeyData>.stride, &output, &size)
        return result == KERN_SUCCESS && output.result == 0 ? output : nil
    }

    private static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    private static func read(_ key: String, _ conn: io_connect_t) -> Double? {
        var input = KeyData()
        input.key = fourCC(key)
        input.data8 = 9 // leer información de la clave
        guard let info = call(&input, conn)?.keyInfo else { return nil }
        input.keyInfo.dataSize = info.dataSize
        input.data8 = 5 // leer valor
        guard let bytes = call(&input, conn)?.bytes else { return nil }
        switch info.dataType {
        case fourCC("sp78"): return Double(Int16(bitPattern: UInt16(bytes.0) << 8 | UInt16(bytes.1))) / 256
        case fourCC("flt "): return Double(Float(bitPattern: UInt32(bytes.0) | UInt32(bytes.1) << 8 | UInt32(bytes.2) << 16 | UInt32(bytes.3) << 24))
        default: return nil
        }
    }

    /// Temperatura del procesador en °C, si el Mac la expone.
    public static func cpu() -> Double? {
        guard let conn = connection else { return nil }
        for key in ["TC0P", "TC0D", "TC0E", "TC0F", "TC0H"] {
            if let value = read(key, conn), value > 1, value < 125 { return value }
        }
        return nil
    }
}
