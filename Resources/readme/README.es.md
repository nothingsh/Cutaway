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

**Ver cómo está construida la interfaz**

- El árbol de capas de cada ventana, con marcas en las vistas raíz de los view controllers y en las
  variables miembro que contienen cada capa o vista, de modo que una capa se puede rastrear hasta el
  código.
- Una captura de pantalla de cada capa, en plano en 2D o separadas en 3D. Gira, haz zoom y desplázate
  con el ratón o el trackpad; cambia la separación entre capas; muestra las capas ocultas.
- Cada posición, tamaño, rotación y escala tal como en la pantalla del dispositivo, incluidas las
  transformaciones 3D.
- Medir: mantén pulsada ⌥ y apunta a otra capa para ver las distancias entre esta y la seleccionada,
  en 2D y en 3D.

**Trabajar con los detalles**

- Los atributos de la capa y la vista seleccionadas, agrupados tal como los reporta la app. Los
  atributos editables tienen controles: texto, números que puedes arrastrar, interruptores,
  selectores de color, menús desplegables para enumeraciones. Los cambios se aplican en la app en
  ejecución al instante, y ⌘Z los deshace.
- Las restricciones de Auto Layout que hacen referencia a la vista seleccionada, con marcas en las que
  no se cumplen, y con el otro extremo de cada restricción marcado en la vista previa. Haz clic en el
  otro extremo para ir a él.
- Busca en el árbol, enfoca un subárbol, expande hasta una profundidad dada, actualiza solo un
  subárbol.

**Conservar lo que encontraste**

- Guarda una inspección como un archivo `.cutaway` y ábrelo más tarde, en cualquier Mac, sin el
  dispositivo: el árbol, las capturas, los atributos y las restricciones están todos ahí, con la
  vista que tenías.
- Exporta la captura de pantalla de una capa, sola o con sus subcapas, como PNG.

**Hecho para el uso diario**

- Encuentra las apps por sí sola: en los simuladores de este Mac y en los dispositivos conectados por
  USB.
- Muestra primero el árbol y las capturas a medida que llegan; los árboles grandes siguen
  respondiendo.
- Se reconecta cuando una app vuelve. Sigue el estado de la app: cuando pasa a segundo plano, Cutaway
  lo indica y continúa cuando regresa.
- En inglés, chino simplificado, chino tradicional, japonés y coreano.
- Habla solo con las apps de este Mac y a través del cable USB. Sin analíticas, sin informes de
  fallos.

<a id="requirements"></a>
## Requisitos

- macOS 14 o posterior, en un Mac con una GPU compatible con Metal (todos los Mac que ejecutan
  macOS 14).
- Una app que incluya [CutawayServer](https://github.com/nothingsh/CutawayServer), ejecutándose en el
  iOS Simulator o en un iPhone o iPad conectado al Mac por USB.

Cutaway no está en el sandbox, porque el socket que usa para llegar a los dispositivos por USB está
fuera del sandbox. Por eso también se distribuye fuera del Mac App Store.

<a id="installation"></a>
## Instalación

Descarga `Cutaway-<versión>.dmg` de la página de [Releases](https://github.com/nothingsh/Cutaway/releases), ábrelo y arrastra
Cutaway a Aplicaciones. Cutaway es de código abierto y sus builds no están notarizados por Apple, así
que la primera vez que lo abras macOS dirá que no puede verificar al desarrollador. Abre **Ajustes
del Sistema › Privacidad y seguridad** y elige **Abrir igualmente**, o ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

**Cutaway › Check for Updates…** te avisa cuando hay una versión más reciente. También puedes
compilar Cutaway desde el código fuente; consulta [Desarrollo](#development).

## Inicio rápido

1. Añade [CutawayServer](https://github.com/nothingsh/CutawayServer) a tu app de iOS y llama a `CutawayServer.start()` una vez al iniciarse. El
   [README](https://github.com/nothingsh/CutawayServer#readme) del servidor tiene las dos líneas para
   UIKit y SwiftUI. Solo se compila en los builds Debug.
2. Ejecuta tu app en el Simulator, o en un dispositivo conectado al Mac con un cable.
3. Abre Cutaway. Tu app aparece en la lista en unos segundos. Elígela.

## Uso de Cutaway

### La lista de capas

La barra lateral muestra las capas de cada ventana como un árbol. Una fila muestra la clase de la
capa, la vista a la que respalda, el view controller cuya vista raíz es, y la variable miembro que la
contiene, como `HomeViewController.titleLabel`. Las filas atenuadas están ocultas o son totalmente
transparentes.

- **Filtra** el árbol con el campo de la parte superior: se quedan las filas cuyo título o clase
  contiene el texto, con sus ancestros.
- **Enfoca** una capa (⌥⌘↓) para mostrar solo su subárbol, en la lista y en la vista previa; la ruta
  sobre la lista lleva de vuelta.
- **Expande** hasta una profundidad elegida, o todo, desde el menú junto al filtro (⌥⌘→ y ⌥⌘← para
  todo). Cuando se inspecciona una app por primera vez, el árbol se abre hasta el view controller en
  pantalla.
- **Haz doble clic** en una fila para expandirla o contraerla. Hacer doble clic en una capa de la vista
  previa hace lo mismo.

### La vista previa

La vista previa dibuja cada capa visible en su lugar en la pantalla, con su captura, a medida que
llega el árbol y luego a medida que llega cada captura.

- **2D o 3D** (⌘1, ⌘2) desde la barra de herramientas. En 3D las capas se separan a lo largo de su
  profundidad; contraer una fila de la lista vuelve a plegar su subárbol en uno solo.
- **Gira** arrastrando en 3D; **desplaza** con el scroll o, en 2D, arrastrando; **haz zoom**
  pellizcando o con ⌘ y la rueda del ratón, alrededor del puntero. **Reset View** (restablecer la
  vista, ⌘0) vuelve al inicio.
- **La separación entre capas** en 3D es el control deslizante bajo la vista previa, de 0 a 200
  puntos.
- **Show Hidden Layers** (mostrar capas ocultas, ⇧⌘H) dibuja también las capas ocultas o
  transparentes, con su propio estilo. **Show Borders** (mostrar bordes, ⇧⌘B) perfila cada capa. Ambos
  interruptores están también bajo la vista previa.
- **Medir**: con una capa seleccionada, mantén pulsada ⌥ y apunta a otra capa. Las distancias entre
  las dos se dibujan con sus valores en puntos, en 2D y en 3D.
- Haz clic en una capa para seleccionarla; la lista y los atributos la siguen. La capa bajo el puntero
  se resalta.

### Atributos

El inspector de la derecha muestra los atributos de la capa seleccionada y de su vista en los grupos
que reporta la app, como `layer`, `view` y `label`. Cutaway no tiene una lista propia: lo que aparece
es lo que envía [CutawayServer](https://github.com/nothingsh/CutawayServer), de modo que muestra lo que conozca la versión del servidor que lleva la
app.

- Los atributos que la app marca como editables tienen controles: un campo de texto, un campo
  numérico que puedes arrastrar, un interruptor, un selector de color con opacidad, un menú
  desplegable para enumeraciones, y campos por componente para puntos, tamaños, rectángulos, insets y
  transformaciones.
- Un cambio se envía en cuanto lo confirmas, o de forma continua mientras arrastras. La app responde
  con los atributos de la capa, de modo que un atributo que cambia junto con otro (como la opacidad
  de una capa con el alpha de su vista) también se actualiza.
- ⌘Z deshace el último cambio y ⇧⌘Z lo rehace, mientras dure la inspección.
- Un cambio que la app rechaza se explica en la fila, y vuelve el valor anterior.

Después de un cambio, Cutaway actualiza las capturas de las capas a las que podría haber afectado.

### Restricciones

Debajo de los atributos, las restricciones de Auto Layout de una vista se listan tal como las reporta
la app: `self.leading = Safe Area of UIView.leading + 16`, con la prioridad cuando es inferior a 1000
y el identificador cuando lo hay. Las restricciones que no se cumplen aparecen atenuadas y marcadas;
las que genera UIKit se pliegan en una sola fila. Haz clic en el otro extremo de una restricción para
seleccionar esa vista. En la vista previa, los otros extremos de las restricciones de la vista
seleccionada están marcados.

### Actualizar

Cutaway muestra el aspecto que tenía la app cuando se lo pidió. **Refresh** (actualizar, ⌘R) vuelve a
pedir todo el árbol y todas las capturas, conservando tu selección, la expansión y la cámara.
**Refresh Selected Subtree** (actualizar el subárbol seleccionado; ⇧⌘R, también en el menú contextual
de la fila) pide solo el subárbol de esa capa. Si la app pasa a segundo plano, Cutaway espera; si se
pierde la conexión, la última imagen se queda y Cutaway se reconecta cuando vuelve a encontrar la
misma app.

### Archivos

**Save Archive…** (guardar archivo, ⌘S) reúne el árbol, el icono, y las capturas, los atributos y las
restricciones de cada capa, incluidas las ocultas, en un único archivo `.cutaway`, junto con el
aspecto que tenía la ventana. El archivo se abre con **Open…** (abrir, ⌘O), desde el Finder, o
soltándolo sobre el icono de Cutaway, en su propia ventana, y todo funciona como en línea salvo la
edición. Pueden estar abiertos varios archivos a la vez, junto a una inspección en directo.

**Export Layer Screenshot…** (exportar la captura de la capa, ⇧⌘E) y **Export Screenshot with
Sublayers…** (exportar la captura con subcapas, ⌥⇧⌘E) escriben la imagen de la capa seleccionada como
PNG a la escala del dispositivo, con transparencia, y sin la transformación ni la opacidad propias de
la capa.

### Ajustes

**Settings…** (ajustes, ⌘,) tiene dos páginas. **General** elige el idioma: el del sistema, o uno de
los cinco. **Preview** (vista previa) elige cómo empieza una nueva inspección: 2D o 3D, la separación
entre capas, y si se muestran las capas ocultas y los bordes. Las ventanas ya abiertas conservan su
aspecto.

### Atajos de teclado

| Acción | Teclas |
|---|---|
| Abrir un archivo | ⌘O |
| Guardar un archivo | ⌘S |
| Exportar la captura de la capa seleccionada, sola / con subcapas | ⇧⌘E / ⌥⇧⌘E |
| Deshacer / rehacer un cambio | ⌘Z / ⇧⌘Z |
| Filtrar la lista de capas | ⌘F |
| Actualizar todo / el subárbol seleccionado | ⌘R / ⇧⌘R |
| 2D / 3D | ⌘1 / ⌘2 |
| Acercar / alejar / restablecer la vista | ⌘= / ⌘- / ⌘0 |
| Mostrar capas ocultas / mostrar bordes | ⇧⌘H / ⇧⌘B |
| Enfocar la capa seleccionada / mostrar todas las capas | ⌥⌘↓ / ⌥⌘↑ |
| Expandir todo / contraer todo | ⌥⌘→ / ⌥⌘← |
| Mostrar u ocultar la barra lateral / el inspector | ⌃⌘S / ⌥⌘I |
| Mostrar la lista de apps | ⇧⌘0 |
| Ajustes | ⌘, |

## Rendimiento

Una interfaz grande debería seguir sintiéndose inmediata. Cutaway está diseñado en torno a esa idea,
y su batería de pruebas lo mantiene dentro de los valores siguientes en cada ejecución. Se miden
contra un árbol generado con forma de app de 10.000 capas (ventanas, contenedores, una barra de
navegación y una larga lista de celdas, cada una con un icono, etiquetas y un separador), en un build
Debug:

| Operación | Límite |
|---|---|
| Llega el árbol → la lista está en pantalla | 2 s |
| Disponer la escena | 1 s |
| Un nuevo fotograma después de mover la cámara | 16 ms |
| Dibujar un fotograma | 16 ms |
| Seleccionar una fila → la vista previa y el inspector la siguen | 100 ms |
| Buscar en la lista | 200 ms |
| Expandir todo / contraer todo | 1 s |
| Abrir un archivo del árbol → la lista está en pantalla | 2 s |

Cómo lo consigue:

- **Las capturas se mantienen comprimidas.** El modelo conserva solo los bytes comprimidos que
  recibió. Se descomprimen fuera del hilo principal, se suben a la GPU, y los píxeles se liberan.
- **La vista previa solo dibuja cuando hay cambios.** No se envía ningún fotograma mientras nada se
  mueve.
- **La lectura va al ritmo del dibujado.** Cuando las capturas llegan más deprisa de lo que se usan,
  Cutaway deja de leer de la conexión, y TCP le dice a la app que espere. Nada se acumula en memoria.
- **Nada se acumula.** La batería repite cada operación diez veces sobre 5.000 capas y comprueba que
  no quede atrás ninguna captura, textura, solicitud ni ventana; una ejecución prolongada más larga
  (`scripts/soak.sh`) imprime la curva de memoria a lo largo de cien rondas.
- **Los datos incorrectos no lo hacen fallar.** Cada trama se valida antes de decodificarla, y los
  parsers se someten a fuzzing con tramas mutadas, truncadas y empalmadas en cada ejecución.

## Comportamiento en el Mac

- Cada dos segundos, Cutaway prueba los puertos 48160 a 48167 en `127.0.0.1`, donde [CutawayServer](https://github.com/nothingsh/CutawayServer)
  escucha en los simuladores, y los mismos puertos en cada dispositivo conectado por USB, a través del
  `usbmuxd` del sistema. Una app que responde al handshake aparece en la lista.
- Una conexión por app, mantenida mientras la app esté en la lista. Una app que ya tiene un cliente
  se deja en paz.
- Una solicitud que no recibe ningún byte durante 10 segundos se abandona; la conexión se cierra
  cuando la app envía algo que el [protocolo](https://github.com/nothingsh/CutawayProtocol) prohíbe.
- Cutaway no hace ninguna otra conexión de red, salvo cuando eliges **Check for Updates…**: entonces
  pide a GitHub la lista de releases de este repositorio, y no envía nada sobre tu Mac.
- Las preferencias están en `UserDefaults`; los archivos recientes están en la lista de documentos
  recientes del sistema.

## Hoja de ruta

Estas son las direcciones previstas después de la 1.0, compartidas con [CutawayServer](https://github.com/nothingsh/CutawayServer). El orden y el
alcance pueden cambiar.

- **Protocolo 1.0.** Congelar el [protocolo de Cutaway](https://github.com/nothingsh/CutawayProtocol), de modo que las funciones posteriores solo le
  añadan cosas.
- **Análisis de interacción.** Mostrar los gesture recognizers y los pares target–action; activar y
  desactivar gestos; llamar a métodos de objetos.
- **API de extensión para apps anfitrionas.** Atributos personalizados, nodos hijos virtuales y
  configuración como clases contraídas por defecto, alias de colores y vistas excluidas de las
  imágenes.
- **Jerarquías grandes.** Un modo rápido que captura solo las capas visibles; transferencia por
  fragmentos para imágenes muy grandes.
- **Más conexiones y plataformas.** Conexiones por Wi-Fi, autenticadas y cifradas; tvOS y visionOS.
- **SwiftUI.** Una jerarquía semántica de las vistas de SwiftUI junto al árbol de capas.

## Preguntas frecuentes

**Mi app no aparece en la lista.**
Comprueba que el build incluye [CutawayServer](https://github.com/nothingsh/CutawayServer) (solo se compila en los builds Debug) y llama a
`CutawayServer.start()`, que la app está en primer plano y, en un dispositivo, que el dispositivo está
conectado con un cable y confía en este Mac. El servidor toma el primer puerto libre entre 48160 y
48167; la lista muestra una app cuya versión del protocolo Cutaway no puede hablar, con ambas
versiones.

**¿Cutaway necesita la red?**
No. Habla con los simuladores a través de la dirección de loopback y con los dispositivos por USB.
Nunca contacta con un servidor propio.

**¿Por qué una vista de desenfoque, de vídeo o de Metal aparece vacía?**
Ese contenido lo compone el render server del sistema, fuera del proceso de la app, así que
[CutawayServer](https://github.com/nothingsh/CutawayServer) no puede renderizarlo a partir del árbol de capas.

**¿Puedo mirar una app sin el dispositivo?**
Guarda un archivo mientras el dispositivo está conectado y ábrelo en cualquier sitio. Para el
desarrollo, la biblioteca de soporte de pruebas también puede reproducir un archivo como si fuera una
app en un simulador (`scripts/replay.sh`).

**¿La inspección cambia mi app?**
Solo las ediciones que haces. La captura restaura todo lo que toca, y leer atributos no desencadena
layout; consulta el README de [CutawayServer](https://github.com/nothingsh/CutawayServer).

<a id="development"></a>
## Desarrollo

Cutaway está escrito en Swift 6 con AppKit y Metal. El código es un paquete Swift local,
`CutawayKit`, y el target de la app no hace más que ensamblarlo:

| Target | Contenido |
|---|---|
| `CutawayWire` | Las tramas, los mensajes del protocolo como tipos por valor, y el formato de archivo |
| `CutawayTransport` | Encontrar apps, `usbmuxd`, sesiones y solicitudes |
| `CutawayModel` | El árbol de capas, las capturas y los atributos, y el estado que comparten las ventanas |
| `CutawayScene` | Dónde se dibuja cada capa, en qué orden, y el hit testing; Swift puro |
| `CutawayRender` | Dibujar la escena con Metal |
| `CutawayUI` | Las ventanas, la lista, la vista previa, el inspector, los ajustes |
| `CutawayTestSupport` | Un servidor simulado que reproduce los fixtures del protocolo, árboles sintéticos, un `usbmuxd` falso |

El formato de transmisión está definido en
[CutawayProtocol](https://github.com/nothingsh/CutawayProtocol), descargado en `Protocol/` como
submódulo; el código Swift correspondiente se genera a partir del esquema y está en el repositorio.
No se comparte nada con [CutawayServer](https://github.com/nothingsh/CutawayServer) salvo el protocolo.

Después de clonar, ejecuta `./setup.sh` una vez. Descarga el submódulo del protocolo, comprueba que
Xcode, XcodeGen y jq estén instalados, instala las herramientas con versión fijada en `.tools/`,
configura los git hooks y genera `Cutaway.xcodeproj` a partir de `project.yml`. Volver a ejecutarlo
no causa ningún daño.

| Tarea | Comando |
|---|---|
| Compilar y probar como lo hace la CI (solo necesita el código) | `scripts/check.sh` |
| Probar el paquete solo | `cd CutawayKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme CutawayKit-Package -destination 'platform=macOS' -testLanguage en` |
| Formatear y luego pasar el linter | `scripts/format.sh` |
| Servir un archivo como una app en un simulador, para un Cutaway en ejecución | `scripts/replay.sh <file.cutaway>` |
| Repetir cada operación durante cien rondas e imprimir la curva de memoria | `scripts/soak.sh` |

- Nada se juzga a ojo. La capa de escena está cubierta por pruebas unitarias; la capa de dibujado
  renderiza fuera de pantalla y se compara con las imágenes de referencia de `Baselines/`.
- Las pruebas nunca necesitan un dispositivo. Las conexiones se prueban contra el servidor simulado
  que reproduce los fixtures del protocolo, en este Mac.

## Licencia

Cutaway es software libre, publicado bajo la GNU General Public License v3.0; consulta
[LICENSE](../../LICENSE). Está construido con [FlatBuffers](https://github.com/google/flatbuffers)
(Apache License 2.0), [DeclarativeAppKit](https://github.com/nothingsh/DeclarativeAppKit) (MIT) y
[DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine) (MIT); sus licencias están en
el panel About y en [`CutawayKit/Sources/CutawayUI/Resources/Acknowledgements`](../../CutawayKit/Sources/CutawayUI/Resources/Acknowledgements). El [protocolo de Cutaway](https://github.com/nothingsh/CutawayProtocol) está bajo la
licencia MIT.
