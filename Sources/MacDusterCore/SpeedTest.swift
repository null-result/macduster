import Foundation

public struct SpeedTestResult: Equatable {
    /// Bits por segundo.
    public let download: Double
    public let upload: Double
    /// Round trips por minuto bajo carga (cuanto más alto, más ágil la conexión), si está disponible.
    public let responsiveness: Int?
}

public enum SpeedTest {
    /// Mide la conexión con la herramienta `networkQuality` de macOS (servidores de Apple). Tarda unos 20 s.
    public static func run() -> SpeedTestResult? {
        let result = Shell.run("/usr/bin/networkQuality", ["-c"])
        return result.ok ? parse(result.output) : nil
    }

    public static func parse(_ json: String) -> SpeedTestResult? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let down = (object["dl_throughput"] as? NSNumber)?.doubleValue,
              let up = (object["ul_throughput"] as? NSNumber)?.doubleValue else { return nil }
        return SpeedTestResult(download: down, upload: up, responsiveness: (object["responsiveness"] as? NSNumber)?.intValue)
    }
}
