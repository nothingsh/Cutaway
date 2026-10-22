<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="cutaway-client-dark.svg">
    <img src="cutaway-client-light.svg" alt="Cutaway — iOS-Oberflächen untersuchen, Layer für Layer." width="850">
  </picture>
</p>

[![Swift](https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014+-blue)](#requirements)
[![License](https://img.shields.io/badge/License-GPL--3.0-lightgrey)](../../LICENSE)
[![check](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml/badge.svg)](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml)

[English](../../README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Français](README.fr.md) | **Deutsch**

*Dies ist eine Übersetzung; weicht sie vom [englischen README](../../README.md) ab, ist das englische README maßgeblich.*

Cutaway ist eine macOS-App, mit der Sie in die Oberfläche einer laufenden iOS-App hineinsehen.
Fügen Sie [CutawayServer](https://github.com/nothingsh/CutawayServer) Ihrer App hinzu, führen Sie
sie im Simulator oder auf einem per USB verbundenen Gerät aus, und Cutaway listet sie auf. Wählen
Sie sie aus, und Cutaway zeigt den Layer-Baum der App, einen Screenshot jedes Layers, flach in 2D
angeordnet oder in 3D auseinandergezogen, sowie die Attribute und Auto-Layout-Constraints des
jeweils ausgewählten Layers. Änderungen, die Sie an Attributen vornehmen, werden auf die laufende
App angewendet.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="overview-dark.png">
    <img src="overview-light.png" alt="Cutaway beim Inspizieren einer App in 3D: der Layer-Baum, die auseinandergezogenen Layer und die Attribute des ausgewählten Layers." width="850">
  </picture>
</p>

<a id="features"></a>
## Funktionen

- **Sehen, wie die Oberfläche aufgebaut ist.** Der Layer-Baum jedes Fensters, mit markierten View-Controllern und den Member-Variablen, die jede View halten. [Die Layer-Liste](https://nothingsh.github.io/Cutaway/guide/hierarchy)
- **In 3D zerlegen.** Ein Screenshot jedes Layers, flach in 2D oder in 3D auseinandergezogen; drehen, zoomen, den Abstand ändern. [Die Vorschau](https://nothingsh.github.io/Cutaway/guide/preview)
- **Messen.** Halten Sie ⌥ gedrückt und zeigen Sie auf einen anderen Layer, in der Vorschau oder in der Liste, um die Abstände in Punkten zu sehen. [Messen](https://nothingsh.github.io/Cutaway/guide/measuring)
- **Im laufenden Betrieb ändern.** Bearbeitete Attribute wirken sofort in der laufenden App; ⌘Z macht sie rückgängig. [Attribute](https://nothingsh.github.io/Cutaway/guide/attributes)
- **Den Constraints folgen.** Jeder Auto-Layout-Constraint einer View, die nicht wirksamen markiert, und ihre anderen Enden. [Constraints](https://nothingsh.github.io/Cutaway/guide/constraints)
- **Dunkelmodus und größere Schrift ausprobieren.** Erscheinungsbild, Textgröße, Layoutrichtung und Größenklassen der App überschreiben. [Umgebung](https://nothingsh.github.io/Cutaway/guide/environment)
- **Zum eigenen Code springen.** Eine Klasse in Xcode öffnen, Namen aus Asset- und String-Katalogen sehen, einen LLDB-Befehl kopieren. [Quellcode](https://nothingsh.github.io/Cutaway/guide/source)
- **Festhalten, was Sie gefunden haben.** Eine Inspektion sichern und auf jedem Mac ohne das Gerät öffnen; einen Layer als PNG exportieren. [Archive und Export](https://nothingsh.github.io/Cutaway/guide/archives)

Cutaway spricht nur mit Apps auf diesem Mac und über das USB-Kabel: keine Analysen, keine Absturzberichte.
Es ist auf Englisch, vereinfachtem Chinesisch, traditionellem Chinesisch, Japanisch und Koreanisch verfügbar.

<a id="requirements"></a>
## Voraussetzungen

- macOS 14 oder neuer, auf einem Mac mit einer GPU, die Metal unterstützt (jeder Mac, auf dem
  macOS 14 läuft).
- Eine App, die [CutawayServer](https://github.com/nothingsh/CutawayServer) enthält und im iOS
  Simulator oder auf einem per USB mit dem Mac verbundenen iPhone oder iPad läuft.

<a id="installation"></a>
## Installation

Laden Sie `Cutaway-<Version>.dmg` von der [Releases](https://github.com/nothingsh/Cutaway/releases)-Seite, öffnen Sie es
und ziehen Sie Cutaway in den Ordner „Programme“. Cutaway ist Open Source, und seine Builds sind
nicht von Apple notarisiert; beim ersten Öffnen meldet macOS daher, dass der Entwickler nicht
überprüft werden kann. Öffnen Sie **Systemeinstellungen › Datenschutz & Sicherheit** und wählen Sie
**Dennoch öffnen**, oder führen Sie aus:

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

**Cutaway › Check for Updates…** meldet, wenn eine neuere Version erschienen ist.

## Schnellstart

1. Fügen Sie [CutawayServer](https://github.com/nothingsh/CutawayServer) Ihrer iOS-App hinzu und rufen Sie `CutawayServer.start()` einmal beim
   Start auf. Es wird nur in Debug-Builds kompiliert.
2. Führen Sie Ihre App im Simulator aus oder auf einem per Kabel mit dem Mac verbundenen Gerät.
3. Öffnen Sie Cutaway. Ihre App erscheint innerhalb weniger Sekunden in der Liste. Wählen Sie sie
   aus.

Die [Anleitung für den Einstieg](https://nothingsh.github.io/Cutaway/guide/getting-started) enthält jeden Schritt, den Code für UIKit und SwiftUI und was zu prüfen ist, wenn Ihre App nicht erscheint.

<a id="documentation"></a>
## Dokumentation

Alles Weitere steht auf der [Cutaway-Website](https://nothingsh.github.io/Cutaway/) (vorerst nur auf Englisch und in vereinfachtem Chinesisch):

- [Anleitung](https://nothingsh.github.io/Cutaway/guide/getting-started): Cutaway Aufgabe für Aufgabe, und alle [Tastaturkurzbefehle](https://nothingsh.github.io/Cutaway/guide/shortcuts).
- [Integration](https://nothingsh.github.io/Cutaway/integrate/): CutawayServer zur App hinzufügen, Debug- und Release-Builds, und die eigenen Angaben Ihrer App anzeigen.
- [Protokoll](https://nothingsh.github.io/Cutaway/protocol/): wie Cutaway und CutawayServer miteinander sprechen, und welche Versionen zusammenpassen.
- [FAQ und Fehlerbehebung](https://nothingsh.github.io/Cutaway/resources/faq), [Datenschutz und Sicherheit](https://nothingsh.github.io/Cutaway/resources/privacy), [Performance](https://nothingsh.github.io/Cutaway/resources/performance), [Versionshinweise](https://nothingsh.github.io/Cutaway/resources/releases), [Roadmap](https://nothingsh.github.io/Cutaway/resources/roadmap).

<a id="development"></a>
## Entwicklung

Wie Sie Cutaway bauen und testen und wie Änderungen geprüft werden, steht in [CONTRIBUTING.md](../../CONTRIBUTING.md).
Die Seite [Contributing](https://nothingsh.github.io/Cutaway/resources/contributing) der Website erklärt, wie die drei Repositories zusammenhängen.

## Lizenz

Cutaway ist freie Software, veröffentlicht unter der GNU General Public License v3.0; siehe
[LICENSE](../../LICENSE). Es ist mit [FlatBuffers](https://github.com/google/flatbuffers) (Apache
License 2.0), [DeclarativeAppKit](https://github.com/nothingsh/DeclarativeAppKit) (MIT) und
[DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine) (MIT) gebaut; deren Lizenzen
stehen im Info-Fenster und in [`CutawayKit/Sources/CutawayUI/Resources/Acknowledgements`](../../CutawayKit/Sources/CutawayUI/Resources/Acknowledgements). Das [Cutaway-Protokoll](https://github.com/nothingsh/CutawayProtocol)
steht unter der MIT-Lizenz.
