import Foundation

public struct DiskVolume: Identifiable, Hashable {
    public var id: String { identifier }
    public let identifier: String      // p. ej. "disk4s1"
    public let name: String
    public let size: Int64
    public let filesystem: String
    public let isExternal: Bool
    public let isWholeDisk: Bool
    public let mountPoint: String?

    public var rawPath: String { "/dev/r\(identifier)" }
    public var title: String { name.isEmpty ? (isWholeDisk ? "Disco completo" : "Sin nombre") : name }
}

public enum DiskCatalog {
    /// Discos y particiones físicas visibles para `diskutil`, listos para escanear.
    public static func list() -> [DiskVolume] {
        guard let top = plist(["list", "-plist"]), let disks = top["AllDisksAndPartitions"] as? [[String: Any]] else { return [] }
        var ids = [String]()
        for disk in disks {
            if let id = disk["DeviceIdentifier"] as? String { ids.append(id) }
            for p in disk["Partitions"] as? [[String: Any]] ?? [] {
                if let id = p["DeviceIdentifier"] as? String { ids.append(id) }
            }
        }
        let skipContent: Set<String> = ["EFI", "Apple_APFS_Recovery", "Apple_APFS_ISC", "Apple_partition_map", "Apple_Boot"]
        return ids.compactMap { id in
            guard let info = plist(["info", "-plist", id]) else { return nil }
            let size = (info["Size"] as? NSNumber)?.int64Value ?? 0
            let content = info["Content"] as? String ?? ""
            let whole = info["WholeDisk"] as? Bool ?? false
            // Los volúmenes "sintetizados" de APFS no son soporte físico: se escanea su partición contenedora.
            let synthesized = info["APFSPhysicalStores"] != nil
            guard size > 0, !skipContent.contains(content), !synthesized else { return nil }
            let fs = (info["FilesystemName"] as? String) ?? (info["FilesystemType"] as? String) ?? ""
            let mount = (info["MountPoint"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return DiskVolume(identifier: id, name: info["VolumeName"] as? String ?? "", size: size,
                              filesystem: fs.isEmpty ? content : fs,
                              isExternal: !(info["Internal"] as? Bool ?? false),
                              isWholeDisk: whole, mountPoint: mount)
        }
    }

    /// Identificadores de disco (partición, disco entero y almacén físico APFS) que respaldan una ruta.
    public static func backingIdentifiers(of url: URL) -> Set<String> {
        guard let info = plist(["info", "-plist", url.path]) else { return [] }
        var ids = Set<String>()
        func add(_ id: String?) {
            guard let id, !id.isEmpty else { return }
            ids.insert(id)
            if let r = id.range(of: #"s\d+$"#, options: .regularExpression) { ids.insert(String(id[..<r.lowerBound])) }
        }
        add(info["DeviceIdentifier"] as? String)
        add(info["ParentWholeDisk"] as? String)
        for store in info["APFSPhysicalStores"] as? [[String: Any]] ?? [] { add(store["APFSPhysicalStore"] as? String) }
        return ids
    }

    private static func plist(_ args: [String]) -> [String: Any]? {
        let result = Shell.run("/usr/sbin/diskutil", args)
        guard result.ok, let data = result.output.data(using: .utf8) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }
}
