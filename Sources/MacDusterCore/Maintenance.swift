import Foundation

public struct MaintenanceTask: Identifiable {
    public let id: String
    public let title: String
    public let explanation: String
    public let command: String
    public let needsAdmin: Bool

    public static let all: [MaintenanceTask] = [
        MaintenanceTask(id: "purge", title: "Liberar RAM",
                        explanation: "Libera la memoria inactiva y la caché de disco.",
                        command: "/usr/sbin/purge", needsAdmin: true),
        MaintenanceTask(id: "dns", title: "Vaciar caché DNS",
                        explanation: "Soluciona problemas de resolución de nombres y webs que no cargan.",
                        command: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder", needsAdmin: true),
        MaintenanceTask(id: "spotlight", title: "Reindexar Spotlight",
                        explanation: "Reconstruye el índice de búsqueda. Puede tardar un buen rato en segundo plano.",
                        command: "/usr/bin/mdutil -E /", needsAdmin: true),
        MaintenanceTask(id: "launchservices", title: "Reconstruir Launch Services",
                        explanation: "Arregla el menú «Abrir con» duplicado o apps asociadas a archivos incorrectos.",
                        command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user",
                        needsAdmin: false),
        MaintenanceTask(id: "quicklook", title: "Reiniciar Vista Previa (Quick Look)",
                        explanation: "Limpia la caché de miniaturas y previsualizaciones.",
                        command: "/usr/bin/qlmanage -r cache", needsAdmin: false),
        MaintenanceTask(id: "snapshots", title: "Reducir instantáneas de Time Machine",
                        explanation: "Elimina instantáneas locales para recuperar espacio.",
                        command: "/usr/bin/tmutil thinlocalsnapshots / 10000000000 4", needsAdmin: true),
        MaintenanceTask(id: "finderdock", title: "Reiniciar Finder y Dock",
                        explanation: "Útil si van lentos o se comportan de forma extraña.",
                        command: "/usr/bin/killall Finder Dock", needsAdmin: false),
    ]

    public static func task(id: String) -> MaintenanceTask? { all.first { $0.id == id } }

    public func run() -> ShellResult {
        needsAdmin ? Shell.runAsAdmin(command) : Shell.run("/bin/zsh", ["-c", command])
    }
}
