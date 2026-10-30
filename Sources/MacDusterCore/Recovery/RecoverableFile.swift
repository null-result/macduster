import Foundation

public enum FileCategory: String, CaseIterable, Identifiable {
    case images = "Imágenes"
    case videos = "Vídeos"
    case audio = "Audio"
    case documents = "Documentos"
    case archives = "Comprimidos"
    case other = "Otros"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .images: return "photo"
        case .videos: return "film"
        case .audio: return "music.note"
        case .documents: return "doc.text"
        case .archives: return "doc.zipper"
        case .other: return "doc"
        }
    }

    /// Nombre base de los archivos recuperados por firma, que no conservan el original.
    var namePrefix: String {
        switch self {
        case .images: return "Imagen"
        case .videos: return "Vídeo"
        case .audio: return "Audio"
        case .documents: return "Documento"
        case .archives: return "Comprimido"
        case .other: return "Archivo"
        }
    }

    private static let byExtension: [String: FileCategory] = {
        var map = [String: FileCategory]()
        let groups: [(FileCategory, [String])] = [
            (.images, ["jpg", "jpeg", "png", "gif", "bmp", "tif", "tiff", "heic", "heif", "webp", "psd", "raw", "cr2", "nef", "arw", "dng", "svg", "ico", "avif"]),
            (.videos, ["mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "mpg", "mpeg", "3gp", "mts"]),
            (.audio, ["mp3", "m4a", "wav", "flac", "aac", "ogg", "wma", "aif", "aiff", "opus"]),
            (.documents, ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "odt", "ods", "odp", "pages", "numbers", "key", "csv", "md", "epub", "sqlite", "html", "xml", "json"]),
            (.archives, ["zip", "rar", "7z", "gz", "tar", "bz2", "dmg", "iso", "xz"]),
        ]
        for (category, list) in groups { for e in list { map[e] = category } }
        return map
    }()

    public static func forExtension(_ ext: String) -> FileCategory {
        byExtension[ext.lowercased()] ?? .other
    }
}

/// Tramo contiguo de bytes dentro del dispositivo.
public struct Extent: Hashable {
    public let offset: Int64
    public let length: Int64
    public init(offset: Int64, length: Int64) {
        self.offset = offset
        self.length = length
    }
}

public struct RecoverableFile: Identifiable, Hashable {
    public enum Source: String {
        case quick = "Escaneo rápido"   // entrada de directorio borrada: conserva nombre y carpeta
        case deep = "Escaneo profundo"  // reconstruido por firma: nombre genérico
    }

    /// Probabilidad de que el contenido siga intacto.
    public enum Chance: String {
        case high = "Alta"
        case low = "Baja"
    }

    public var id: Int64 { offset }
    public let name: String
    public let folder: String?
    public let category: FileCategory
    public let extents: [Extent]
    public let size: Int64
    public let source: Source
    public let chance: Chance

    public var offset: Int64 { extents[0].offset }

    /// `extents` debe tener al menos un tramo; si no se indica, el archivo es contiguo desde `offset`.
    public init(name: String, folder: String? = nil, category: FileCategory, offset: Int64, size: Int64,
                extents: [Extent]? = nil, source: Source, chance: Chance = .high) {
        self.name = name
        self.folder = folder
        self.category = category
        self.extents = extents ?? [Extent(offset: offset, length: size)]
        self.size = size
        self.source = source
        self.chance = chance
    }
}

public enum ScanMode: Hashable {
    case quick, deep
}

public enum ScanEvent {
    case phase(String)
    case progress(Double)
    case found([RecoverableFile])
}
