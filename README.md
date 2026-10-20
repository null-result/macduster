<p align="center">
  <img src="docs/icon.png" width="128" alt="MacDuster">
</p>

<h1 align="center">MacDuster</h1>

<p align="center">
  Un plumero para tu Mac: limpieza, desinstalador, archivos grandes y un panel de estado en la barra de menú.<br>
  Hecha con SwiftUI, sin dependencias y sin necesidad de Xcode.
</p>

---

## Características

### Aplicación

| Módulo | Qué hace |
|---|---|
| **Limpieza** | Analiza cachés de usuario, registros, restos de Xcode, cachés de desarrollo, adjuntos de Mail, copias de iOS y la Papelera. Muestra cuánto ocupa cada categoría y deja elegir qué eliminar. |
| **Desinstalador** | Lista las aplicaciones instaladas y borra también sus restos (preferencias, cachés, datos de soporte). |
| **Archivos grandes** | Busca los archivos más pesados, con filtro por tamaño y por tiempo sin usar, y permite revelarlos en el Finder. |
| **Rendimiento** | Procesos que más memoria consumen, elementos de inicio de sesión y tareas de mantenimiento: liberar RAM, vaciar caché DNS, reindexar Spotlight, reconstruir Launch Services, reiniciar Quick Look, reducir instantáneas de Time Machine y reiniciar Finder y Dock. |

### Panel de la barra de menú

Un clic en el icono del plumero abre un panel con datos en vivo:

- **Disco**: espacio libre y usado, y tamaño de la Papelera con acceso directo para vaciarla.
- **Memoria** y **procesador**: porcentaje de uso y temperatura de la CPU (Macs Intel).
- **Red**: velocidad de subida y bajada en tiempo real, y nombre y velocidad de enlace de la Wi-Fi.
- **Batería**: nivel y estado de carga.
- **Prueba de velocidad**: mide descarga, subida y agilidad de la conexión con la herramienta `networkQuality` de macOS.
- **Avisos** cuando queda poco espacio o la Papelera está muy llena, con notificaciones opcionales.
- Ajustes para iniciar la app al arrancar el Mac.

El panel solo mide mientras está abierto, así que no consume recursos en segundo plano.

### Seguridad

- Una guarda de seguridad impide borrar rutas del sistema, el directorio personal o `/Applications`.
- Lo que no es definitivo se envía a la Papelera en lugar de eliminarse.
- Las tareas que requieren privilegios piden la contraseña de administrador a través de macOS.

## Requisitos

- macOS 12 o posterior
- Herramientas de línea de comandos de Xcode (`xcode-select --install`)

Para eliminar algunos elementos (por ejemplo, cachés de otras apps) conviene conceder **Acceso total al disco** a MacDuster en *Ajustes del Sistema → Privacidad y seguridad*.

## Compilar e instalar

```sh
git clone https://github.com/null-result/macduster.git
cd macduster
zsh Scripts/build_app.sh
open build/MacDuster.app
```

El script compila con `swiftc` (no hace falta Xcode ni SwiftPM), empaqueta `build/MacDuster.app` y lo firma con una firma ad hoc. Para instalarla, copia el `.app` a `/Applications`.

### Pruebas

El paquete también es compatible con SwiftPM (con Xcode instalado):

```sh
swift test
```

## Estructura

```
Sources/
  MacDusterCore/   Lógica sin interfaz: análisis, borrado seguro, estadísticas del sistema,
                   temperatura (SMC), prueba de velocidad, mantenimiento
  MacDuster/       Interfaz SwiftUI y panel de la barra de menú
Scripts/
  build_app.sh     Compila y empaqueta la aplicación
  make_icon.swift  Dibuja el icono en vectorial y genera el .icns
Tests/             Pruebas de la capa Core
```

## Diseño

Fondo grafito neutro, superficies translúcidas con filo fino y un único color de acento por módulo (turquesa, rosa, azul y ámbar). El icono se genera por código desde `Scripts/make_icon.swift`:

```sh
swift Scripts/make_icon.swift
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
```

## Notas

- La temperatura de la CPU se lee del SMC, por lo que está disponible en Macs Intel; en Apple Silicon la tarjeta muestra solo el uso.
- El nombre de la red Wi-Fi puede no mostrarse si macOS no concede el permiso de ubicación.

## Licencia

[MIT](LICENSE)
