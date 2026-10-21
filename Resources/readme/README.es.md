<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="cutaway-client-dark.svg">
    <img src="cutaway-client-light.svg" alt="Cutaway — Inspecciona las interfaces de iOS, capa por capa." width="850">
  </picture>
</p>

[![Swift](https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014+-blue)](#requirements)
[![License](https://img.shields.io/badge/License-GPL--3.0-lightgrey)](../../LICENSE)
[![check](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml/badge.svg)](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml)

[English](../../README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | **Español** | [Français](README.fr.md) | [Deutsch](README.de.md)

*Esto es una traducción; si difiere del [README en inglés](../../README.md), prevalece el README en inglés.*

Cutaway es una app de macOS para mirar dentro de la interfaz de una app de iOS en ejecución. Añade
[CutawayServer](https://github.com/nothingsh/CutawayServer) a tu app, ejecútala en el Simulator o en
un dispositivo conectado por USB, y Cutaway la muestra en su lista. Elígela, y Cutaway muestra el
árbol de capas de la app, una captura de pantalla de cada capa dispuesta en plano en 2D o separada en
3D, y los atributos y las restricciones de Auto Layout de la capa que selecciones. Las ediciones que
hagas en los atributos se aplican a la app en ejecución.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="overview-dark.png">
    <img src="overview-light.png" alt="Cutaway inspeccionando una app en 3D: el árbol de capas, las capas separadas con medidas y los atributos de la capa seleccionada." width="850">
  </picture>
</p>

<a id="features"></a>
## Características

- **Mira cómo está construida la interfaz.** El árbol de capas de cada ventana, con los controladores de vista y las variables miembro que contienen cada vista marcados. [La lista de capas](https://nothingsh.github.io/Cutaway/guide/hierarchy)
- **Desármala en 3D.** Una captura de cada capa, plana en 2D o separada en 3D; gira, haz zoom y cambia la separación. [La vista previa](https://nothingsh.github.io/Cutaway/guide/preview)
- **Mide.** Mantén pulsada ⌥ y señala otra capa, en la vista previa o en la lista, para ver las distancias en puntos. [Medir](https://nothingsh.github.io/Cutaway/guide/measuring)
- **Cámbiala mientras se ejecuta.** Edita atributos y se aplican al instante en la app en ejecución; ⌘Z los deshace. [Atributos](https://nothingsh.github.io/Cutaway/guide/attributes)
- **Sigue las restricciones.** Cada restricción de Auto Layout de una vista, con las que no están en vigor marcadas, y sus otros extremos. [Restricciones](https://nothingsh.github.io/Cutaway/guide/constraints)
- **Prueba el modo oscuro y el texto más grande.** Sustituye la apariencia, el tamaño del texto, la dirección del diseño y las clases de tamaño de la app. [Entorno](https://nothingsh.github.io/Cutaway/guide/environment)
- **Salta a tu código.** Abre una clase en Xcode, ve los nombres de los catálogos de recursos y de cadenas y copia un comando de LLDB. [Código fuente](https://nothingsh.github.io/Cutaway/guide/source)
- **Guarda lo que encontraste.** Guarda una inspección y ábrela en cualquier Mac sin el dispositivo; exporta una capa como PNG. [Archivos y exportación](https://nothingsh.github.io/Cutaway/guide/archives)

Cutaway solo se comunica con apps de este Mac y a través del cable USB: sin analíticas ni informes de fallos.
Está en inglés, chino simplificado, chino tradicional, japonés y coreano.

<a id="requirements"></a>
## Requisitos

- macOS 14 o posterior, en un Mac con una GPU compatible con Metal (todos los Mac que ejecutan
  macOS 14).
- Una app que incluya [CutawayServer](https://github.com/nothingsh/CutawayServer), ejecutándose en el
  iOS Simulator o en un iPhone o iPad conectado al Mac por USB.

<a id="installation"></a>
## Instalación

Descarga `Cutaway-<versión>.dmg` de la página de [Releases](https://github.com/nothingsh/Cutaway/releases), ábrelo y arrastra
Cutaway a Aplicaciones. Cutaway es de código abierto y sus builds no están notarizados por Apple, así
que la primera vez que lo abras macOS dirá que no puede verificar al desarrollador. Abre **Ajustes
del Sistema › Privacidad y seguridad** y elige **Abrir igualmente**, o ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

**Cutaway › Check for Updates…** te avisa cuando hay una versión más reciente.

## Inicio rápido

1. Añade [CutawayServer](https://github.com/nothingsh/CutawayServer) a tu app de iOS y llama a `CutawayServer.start()` una vez al iniciarse. Solo se
   compila en los builds Debug.
2. Ejecuta tu app en el Simulator, o en un dispositivo conectado al Mac con un cable.
3. Abre Cutaway. Tu app aparece en la lista en unos segundos. Elígela.

La [guía de inicio](https://nothingsh.github.io/Cutaway/guide/getting-started) tiene cada paso, el código para UIKit y SwiftUI y qué revisar cuando tu app no aparece.

<a id="documentation"></a>
## Documentación

Todo lo demás está en el [sitio web de Cutaway](https://nothingsh.github.io/Cutaway/) (por ahora solo en inglés y chino simplificado):

- [Guía](https://nothingsh.github.io/Cutaway/guide/getting-started): cómo usar Cutaway, tarea por tarea, y todos los [atajos de teclado](https://nothingsh.github.io/Cutaway/guide/shortcuts).
- [Integración](https://nothingsh.github.io/Cutaway/integrate/): añadir CutawayServer a tu app, los builds Debug y Release, y mostrar los datos propios de tu app.
- [Protocolo](https://nothingsh.github.io/Cutaway/protocol/): cómo se comunican Cutaway y CutawayServer, y qué versiones funcionan juntas.
- [Preguntas frecuentes y solución de problemas](https://nothingsh.github.io/Cutaway/resources/faq), [Privacidad y seguridad](https://nothingsh.github.io/Cutaway/resources/privacy), [Rendimiento](https://nothingsh.github.io/Cutaway/resources/performance), [Notas de la versión](https://nothingsh.github.io/Cutaway/resources/releases), [Hoja de ruta](https://nothingsh.github.io/Cutaway/resources/roadmap).

<a id="development"></a>
## Desarrollo

Cómo compilar y probar Cutaway, y cómo se revisan los cambios, está en [CONTRIBUTING.md](../../CONTRIBUTING.md).
La página [Contributing](https://nothingsh.github.io/Cutaway/resources/contributing) del sitio explica cómo encajan los tres repositorios.

## Licencia

Cutaway es software libre, publicado bajo la GNU General Public License v3.0; consulta
[LICENSE](../../LICENSE). Está construido con [FlatBuffers](https://github.com/google/flatbuffers)
(Apache License 2.0), [DeclarativeAppKit](https://github.com/nothingsh/DeclarativeAppKit) (MIT) y
[DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine) (MIT); sus licencias están en
el panel About y en [`CutawayKit/Sources/CutawayUI/Resources/Acknowledgements`](../../CutawayKit/Sources/CutawayUI/Resources/Acknowledgements). El [protocolo de Cutaway](https://github.com/nothingsh/CutawayProtocol) está bajo la
licencia MIT.
