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
    <img src="overview-light.png" alt="Cutaway beim Inspizieren einer App in 3D: der Layer-Baum, die auseinandergezogenen Layer mit Messungen und die Attribute des ausgewählten Layers." width="850">
  </picture>
</p>

<a id="features"></a>
## Funktionen

**Sehen, wie die Oberfläche aufgebaut ist**

- Der Layer-Baum jedes Fensters, mit Markierung der Root-Views von View-Controllern und der
  Member-Variablen, die den jeweiligen Layer oder die jeweilige View halten, sodass sich ein Layer
  bis zum Code zurückverfolgen lässt.
- Ein Screenshot jedes Layers, flach in 2D oder in 3D auseinandergezogen. Drehen, zoomen und
  verschieben Sie mit Maus oder Trackpad; ändern Sie den Abstand zwischen den Layern; blenden Sie
  die ausgeblendeten Layer ein.
- Jede Position, Größe, Drehung und Skalierung wie auf dem Bildschirm des Geräts, einschließlich
  3D-Transformationen.
- Messen: Halten Sie ⌥ gedrückt und zeigen Sie auf einen anderen Layer, um die Abstände zwischen
  ihm und dem ausgewählten zu sehen, in 2D und in 3D.

**Mit den Details arbeiten**

- Die Attribute des ausgewählten Layers und der View, gruppiert, wie die App sie meldet.
  Bearbeitbare Attribute haben Bedienelemente: Text, Zahlen, die Sie ziehen können, Schalter,
  Farbwähler, Pop-ups für Aufzählungen. Änderungen werden sofort in der laufenden App angewendet,
  und ⌘Z macht sie rückgängig.
- Die Auto-Layout-Constraints, die sich auf die ausgewählte View beziehen, mit Markierung
  derjenigen, die nicht wirksam sind, und mit Markierung des anderen Endes jedes Constraints in der
  Vorschau. Klicken Sie auf das andere Ende, um dorthin zu springen.
- Den Baum durchsuchen, auf einen Teilbaum fokussieren, bis zu einer bestimmten Tiefe aufklappen,
  einen Teilbaum allein aktualisieren.

**Behalten, was Sie gefunden haben**

- Sichern Sie eine Inspektion als `.cutaway`-Archiv und öffnen Sie sie später, auf jedem Mac, ohne
  Gerät: Baum, Screenshots, Attribute und Constraints sind alle enthalten, zusammen mit der Ansicht,
  die Sie hatten.
- Exportieren Sie den Screenshot eines Layers, allein oder mit seinen Sublayern, als PNG.

**Für den Alltag gebaut**

- Findet Apps von selbst: in Simulatoren auf diesem Mac und auf per USB verbundenen Geräten.
- Zeigt zuerst den Baum und dann die Screenshots, sobald sie eintreffen; große Bäume bleiben
  reaktionsfähig.
- Verbindet sich erneut, wenn eine App zurückkommt. Folgt dem Zustand der App: Geht sie in den
  Hintergrund, sagt Cutaway das und macht weiter, wenn sie zurückkehrt.
- Auf Englisch, vereinfachtem Chinesisch, traditionellem Chinesisch, Japanisch und Koreanisch.
- Spricht nur mit Apps auf diesem Mac und über das USB-Kabel. Keine Analysen, keine
  Absturzberichte.

<a id="requirements"></a>
## Voraussetzungen

- macOS 14 oder neuer, auf einem Mac mit einer GPU, die Metal unterstützt (jeder Mac, auf dem
  macOS 14 läuft).
- Eine App, die [CutawayServer](https://github.com/nothingsh/CutawayServer) enthält und im iOS
  Simulator oder auf einem per USB mit dem Mac verbundenen iPhone oder iPad läuft.

Cutaway läuft nicht in der Sandbox, weil der Socket, über den es Geräte per USB erreicht, außerhalb
der Sandbox liegt. Aus demselben Grund wird es außerhalb des Mac App Store vertrieben.

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

**Cutaway › Check for Updates…** meldet, wenn eine neuere Version erschienen ist. Sie können
Cutaway auch aus dem Quellcode bauen; siehe [Entwicklung](#development).

## Schnellstart

1. Fügen Sie [CutawayServer](https://github.com/nothingsh/CutawayServer) Ihrer iOS-App hinzu und rufen Sie `CutawayServer.start()` einmal beim
   Start auf. Das [README](https://github.com/nothingsh/CutawayServer#readme) des Servers enthält
   die zwei Zeilen für UIKit und SwiftUI. Es wird nur in Debug-Builds kompiliert.
2. Führen Sie Ihre App im Simulator aus oder auf einem per Kabel mit dem Mac verbundenen Gerät.
3. Öffnen Sie Cutaway. Ihre App erscheint innerhalb weniger Sekunden in der Liste. Wählen Sie sie
   aus.

## Cutaway verwenden

### Die Layer-Liste

Die Seitenleiste listet die Layer jedes Fensters als Baum auf. Eine Zeile zeigt die Klasse des
Layers, die View, die er trägt, den View-Controller, dessen Root-View er ist, und die
Member-Variable, die ihn hält, etwa `HomeViewController.titleLabel`. Abgeblendete Zeilen sind
ausgeblendet oder vollständig transparent.

- **Filtern** Sie den Baum mit dem Feld oben: Zeilen, deren Titel oder Klasse den Text enthält,
  bleiben, zusammen mit ihren Vorfahren.
- **Fokussieren** Sie auf einen Layer (⌥⌘↓), um nur seinen Teilbaum zu zeigen, in der Liste und in
  der Vorschau; der Pfad über der Liste führt wieder hinaus.
- **Aufklappen** bis zu einer gewählten Tiefe oder vollständig, über das Menü neben dem Filter
  (⌥⌘→ und ⌥⌘← für alles). Wird eine App zum ersten Mal untersucht, öffnet sich der Baum bis zum
  View-Controller auf dem Bildschirm.
- **Doppelklicken** Sie auf eine Zeile, um sie auf- oder zuzuklappen. Ein Doppelklick auf einen
  Layer in der Vorschau tut dasselbe.

### Die Vorschau

Die Vorschau zeichnet jeden sichtbaren Layer an seiner Stelle auf dem Bildschirm, mit seinem
Screenshot, sobald der Baum eintrifft und dann, sobald jeder einzelne Screenshot eintrifft.

- **2D oder 3D** (⌘1, ⌘2) über die Symbolleiste. In 3D werden die Layer entlang ihrer Tiefe
  auseinandergezogen; das Zuklappen einer Zeile in der Liste faltet ihren Teilbaum wieder zu einem
  zusammen.
- **Drehen** durch Ziehen in 3D; **verschieben** durch Scrollen oder, in 2D, durch Ziehen;
  **zoomen** durch Auf- und Zuziehen oder mit ⌘ und dem Scrollrad, um den Zeiger herum.
  **Reset View** (Ansicht zurücksetzen, ⌘0) kehrt zum Ausgangszustand zurück.
- **Layer-Abstand** in 3D ist der Schieberegler unter der Vorschau, von 0 bis 200 Punkten.
- **Show Hidden Layers** (ausgeblendete Layer einblenden, ⇧⌘H) zeichnet auch die Layer, die
  ausgeblendet oder transparent sind, in einem eigenen Stil. **Show Borders** (Rahmen anzeigen,
  ⇧⌘B) umrandet jeden Layer. Beide Schalter finden sich auch unter der Vorschau.
- **Messen**: Halten Sie bei ausgewähltem Layer ⌥ gedrückt und zeigen Sie auf einen anderen Layer.
  Die Abstände zwischen den beiden werden mit ihren Werten in Punkten gezeichnet, in 2D und in 3D.
- Klicken Sie auf einen Layer, um ihn auszuwählen; Liste und Attribute folgen. Der Layer unter dem
  Zeiger wird hervorgehoben.

### Attribute

Der Inspektor rechts zeigt die Attribute des ausgewählten Layers und seiner View in den Gruppen,
die die App meldet, etwa `layer`, `view` und `label`. Cutaway hat keine eigene Liste: Was
erscheint, ist das, was [CutawayServer](https://github.com/nothingsh/CutawayServer) sendet; es zeigt also, was die Server-Version der App kennt.

- Attribute, die die App als bearbeitbar markiert, haben Bedienelemente: ein Textfeld, ein
  Zahlenfeld, das Sie ziehen können, einen Schalter, einen Farbwähler mit Deckkraft, ein Pop-up
  für Aufzählungen und Felder pro Komponente für Punkte, Größen, Rechtecke, Insets und
  Transformationen.
- Eine Änderung wird gesendet, sobald Sie sie bestätigen, oder fortlaufend, während Sie ziehen.
  Die App antwortet mit den Attributen des Layers, sodass ein Attribut, das sich mit einem anderen
  ändert (etwa die Opacity eines Layers mit dem Alpha seiner View), ebenfalls aktualisiert wird.
- ⌘Z macht die letzte Änderung rückgängig und ⇧⌘Z stellt sie wieder her, solange die Inspektion
  dauert.
- Eine Änderung, die die App ablehnt, wird in der Zeile erklärt, und der vorherige Wert kehrt
  zurück.

Nach einer Änderung aktualisiert Cutaway die Screenshots der Layer, die davon betroffen sein
könnten.

### Constraints

Unter den Attributen werden die Auto-Layout-Constraints einer View so aufgeführt, wie die App sie
meldet: `self.leading = Safe Area of UIView.leading + 16`, mit der Priorität, wenn sie unter 1000
liegt, und dem Identifier, wenn es einen gibt. Constraints, die nicht wirksam sind, sind
abgeblendet und markiert; die von UIKit erzeugten sind zu einer Zeile zusammengefaltet. Klicken
Sie auf das andere Ende eines Constraints, um diese View auszuwählen. In der Vorschau sind die
anderen Enden der Constraints der ausgewählten View markiert.

### Aktualisieren

Cutaway zeigt, wie die App aussah, als sie gefragt wurde. **Refresh** (Aktualisieren, ⌘R) fragt
erneut nach dem ganzen Baum und jedem Screenshot und behält dabei Ihre Auswahl, die aufgeklappten
Zeilen und die Kamera. **Refresh Selected Subtree** (ausgewählten Teilbaum aktualisieren, ⇧⌘R,
auch im Kontextmenü der Zeile) fragt nur nach dem Teilbaum dieses Layers. Geht die App in den
Hintergrund, wartet Cutaway; geht die Verbindung verloren, bleibt das letzte Bild stehen, und
Cutaway verbindet sich erneut, sobald dieselbe App wieder gefunden wird.

### Archive

**Save Archive…** (Archiv sichern, ⌘S) sammelt den Baum, das Icon sowie die Screenshots,
Attribute und Constraints jedes Layers, ausgeblendete eingeschlossen, in einer einzigen
`.cutaway`-Datei, zusammen mit dem Aussehen des Fensters. Die Datei öffnet sich mit **Open…**
(Öffnen, ⌘O), aus dem Finder oder durch Ablegen auf dem Icon von Cutaway, in einem eigenen
Fenster, und alles funktioniert wie online, außer dem Bearbeiten. Mehrere Archive können
gleichzeitig geöffnet sein, neben einer Live-Inspektion.

**Export Layer Screenshot…** (Layer-Screenshot exportieren, ⇧⌘E) und **Export Screenshot with
Sublayers…** (Screenshot mit Sublayern exportieren, ⌥⇧⌘E) schreiben das Bild des ausgewählten
Layers als PNG im Maßstab des Geräts, mit Transparenz und ohne die eigene Transformation oder
Opacity des Layers.

### Einstellungen

**Settings…** (Einstellungen, ⌘,) hat zwei Seiten. **General** (Allgemein) wählt die Sprache: die
des Systems oder eine der fünf. **Preview** (Vorschau) legt fest, wie eine neue Inspektion
beginnt: 2D oder 3D, der Layer-Abstand und ob ausgeblendete Layer und Rahmen angezeigt werden.
Bereits geöffnete Fenster behalten ihr Aussehen.

### Tastaturkurzbefehle

| Aktion | Tasten |
|---|---|
| Ein Archiv öffnen | ⌘O |
| Ein Archiv sichern | ⌘S |
| Den Screenshot des ausgewählten Layers exportieren, allein / mit Sublayern | ⇧⌘E / ⌥⇧⌘E |
| Eine Änderung rückgängig machen / wiederherstellen | ⌘Z / ⇧⌘Z |
| Die Layer-Liste filtern | ⌘F |
| Alles / den ausgewählten Teilbaum aktualisieren | ⌘R / ⇧⌘R |
| 2D / 3D | ⌘1 / ⌘2 |
| Vergrößern / verkleinern / Ansicht zurücksetzen | ⌘= / ⌘- / ⌘0 |
| Ausgeblendete Layer einblenden / Rahmen anzeigen | ⇧⌘H / ⇧⌘B |
| Auf den ausgewählten Layer fokussieren / alle Layer zeigen | ⌥⌘↓ / ⌥⌘↑ |
| Alles aufklappen / alles zuklappen | ⌥⌘→ / ⌥⌘← |
| Seitenleiste / Inspektor ein- oder ausblenden | ⌃⌘S / ⌥⌘I |
| Die App-Liste anzeigen | ⇧⌘0 |
| Einstellungen | ⌘, |

## Performance

Eine große Oberfläche sollte sich weiterhin unmittelbar anfühlen. Cutaway ist darauf ausgelegt,
und seine Testsuite hält es bei jedem Lauf an die folgenden Werte. Sie werden an einem
generierten, app-förmigen Baum mit 10.000 Layern gemessen (Fenster, Container, eine
Navigationsleiste und eine lange Liste von Zellen, jede mit Icon, Labels und Trennlinie), in
einem Debug-Build:

| Vorgang | Grenze |
|---|---|
| Der Baum trifft ein → die Liste ist auf dem Bildschirm | 2 s |
| Die Szene anordnen | 1 s |
| Ein neues Frame, nachdem sich die Kamera bewegt hat | 16 ms |
| Ein Frame zeichnen | 16 ms |
| Eine Zeile auswählen → Vorschau und Inspektor folgen | 100 ms |
| Die Liste durchsuchen | 200 ms |
| Alles aufklappen / alles zuklappen | 1 s |
| Ein Archiv des Baums öffnen → die Liste ist auf dem Bildschirm | 2 s |

Wie es das erreicht:

- **Screenshots bleiben komprimiert.** Das Modell behält nur die komprimierten Bytes, die es
  empfangen hat. Sie werden abseits des Main-Threads dekomprimiert, auf die GPU geladen, und die
  Pixel werden freigegeben.
- **Die Vorschau zeichnet nur bei Änderungen.** Solange sich nichts bewegt, wird kein Frame
  eingereicht.
- **Das Lesen hält Schritt mit dem Zeichnen.** Treffen Screenshots schneller ein, als sie
  verwendet werden, hört Cutaway auf, von der Verbindung zu lesen, und TCP weist die App an zu
  warten. Nichts staut sich im Speicher.
- **Nichts sammelt sich an.** Die Suite wiederholt jeden Vorgang zehnmal über 5.000 Layer und
  prüft, dass kein Screenshot, keine Textur, keine Anfrage und kein Fenster zurückbleibt; ein
  längerer Dauerlauf (`scripts/soak.sh`) gibt die Speicherkurve über hundert Runden aus.
- **Ungültige Daten bringen es nicht zum Absturz.** Jeder Frame wird geprüft, bevor er dekodiert
  wird, und die Parser werden bei jedem Lauf mit mutierten, gekürzten und zusammengefügten Frames
  gefuzzt.

## Verhalten auf dem Mac

- Alle zwei Sekunden probiert Cutaway die Ports 48160 bis 48167 auf `127.0.0.1`, wo [CutawayServer](https://github.com/nothingsh/CutawayServer)
  in Simulatoren lauscht, sowie dieselben Ports auf jedem per USB verbundenen Gerät, über das
  `usbmuxd` des Systems. Eine App, die den Handshake beantwortet, wird aufgelistet.
- Eine Verbindung pro App, gehalten, solange die App aufgelistet ist. Eine App, die bereits einen
  Client hat, wird in Ruhe gelassen.
- Eine Anfrage, die 10 Sekunden lang kein Byte erhält, wird aufgegeben; die Verbindung wird
  geschlossen, wenn die App etwas sendet, das das [Protokoll](https://github.com/nothingsh/CutawayProtocol) verbietet.
- Cutaway stellt keine weitere Netzwerkverbindung her, außer wenn Sie **Check for Updates…**
  wählen: Dann fragt es GitHub nach der Liste der Releases dieses Repositorys und sendet nichts über
  Ihren Mac.
- Einstellungen liegen in `UserDefaults`; zuletzt verwendete Archive stehen in der Liste der
  zuletzt benutzten Dokumente des Systems.

## Roadmap

Dies sind die für die Zeit nach 1.0 geplanten Richtungen, gemeinsam mit [CutawayServer](https://github.com/nothingsh/CutawayServer).
Reihenfolge und Umfang können sich ändern.

- **Protokoll 1.0.** Das [Cutaway-Protokoll](https://github.com/nothingsh/CutawayProtocol) einfrieren, sodass spätere Funktionen es nur noch
  erweitern.
- **Interaktionsanalyse.** Gesture-Recognizer und Target-Action-Paare anzeigen; Gesten aktivieren
  und deaktivieren; Methoden auf Objekten aufrufen.
- **Erweiterungs-API für Host-Apps.** Benutzerdefinierte Attribute, virtuelle Kindknoten und
  Konfiguration wie standardmäßig eingeklappte Klassen, Farbaliasse und von Bildern ausgeschlossene
  Views.
- **Große Hierarchien.** Ein schneller Modus, der nur sichtbare Layer erfasst; aufgeteilte
  Übertragung für sehr große Bilder.
- **Mehr Verbindungen und Plattformen.** WLAN-Verbindungen, authentifiziert und verschlüsselt;
  tvOS und visionOS.
- **SwiftUI.** Eine semantische Hierarchie der SwiftUI-Views neben dem Layer-Baum.

## FAQ

**Meine App erscheint nicht in der Liste.**
Prüfen Sie, ob der Build [CutawayServer](https://github.com/nothingsh/CutawayServer) enthält (es wird nur in Debug-Builds kompiliert) und
`CutawayServer.start()` aufruft, ob die App im Vordergrund ist und, auf einem Gerät, ob das Gerät
per Kabel verbunden ist und diesem Mac vertraut. Der Server nimmt den ersten freien Port von 48160
bis 48167; eine App, deren Protokollversion Cutaway nicht spricht, zeigt die Liste mit beiden
Versionen an.

**Braucht Cutaway das Netzwerk?**
Nein. Es spricht mit Simulatoren über die Loopback-Adresse und mit Geräten über USB. Es
kontaktiert nie einen eigenen Server.

**Warum ist eine Blur-, Video- oder Metal-View leer?**
Diese Inhalte werden vom Render-Server des Systems außerhalb des App-Prozesses zusammengesetzt,
sodass [CutawayServer](https://github.com/nothingsh/CutawayServer) sie nicht aus dem Layer-Baum rendern kann.

**Kann ich mir eine App ohne das Gerät ansehen?**
Sichern Sie ein Archiv, während das Gerät verbunden ist, und öffnen Sie es überall. Für die
Entwicklung kann die Testunterstützungsbibliothek ein Archiv auch so abspielen, als wäre es eine
App in einem Simulator (`scripts/replay.sh`).

**Verändert die Inspektion meine App?**
Nur die Bearbeitungen, die Sie vornehmen. Die Erfassung stellt alles, was sie berührt, wieder
her, und das Lesen von Attributen löst kein Layout aus; siehe das README von [CutawayServer](https://github.com/nothingsh/CutawayServer).

<a id="development"></a>
## Entwicklung

Cutaway ist in Swift 6 mit AppKit und Metal geschrieben. Der Code ist ein lokales Swift-Paket,
`CutawayKit`; das App-Target tut nichts weiter, als es zusammenzusetzen:

| Target | Inhalt |
|---|---|
| `CutawayWire` | Frames, die Nachrichten des Protokolls als Werttypen und das Archivformat |
| `CutawayTransport` | Apps finden, `usbmuxd`, Sitzungen und Anfragen |
| `CutawayModel` | Der Layer-Baum, Screenshots und Attribute sowie der Zustand, den die Fenster teilen |
| `CutawayScene` | Wo jeder Layer gezeichnet wird, in welcher Reihenfolge, und Hit-Testing; reines Swift |
| `CutawayRender` | Das Zeichnen der Szene mit Metal |
| `CutawayUI` | Fenster, die Liste, die Vorschau, der Inspektor, Einstellungen |
| `CutawayTestSupport` | Ein Mock-Server, der die Fixtures des Protokolls abspielt, synthetische Bäume, ein nachgebildetes `usbmuxd` |

Das Wire-Format ist in [CutawayProtocol](https://github.com/nothingsh/CutawayProtocol) definiert,
als Submodul unter `Protocol/` ausgecheckt; der Swift-Code dafür wird aus dem Schema generiert und
ist eingecheckt. Mit [CutawayServer](https://github.com/nothingsh/CutawayServer) wird nichts geteilt außer dem Protokoll.

Führen Sie nach dem Klonen einmal `./setup.sh` aus. Es checkt das Protokoll-Submodul aus, prüft,
ob Xcode, XcodeGen und jq vorhanden sind, installiert die versionsfixierten Werkzeuge in `.tools/`,
richtet die Git-Hooks ein und generiert `Cutaway.xcodeproj` aus `project.yml`. Ein erneutes
Ausführen schadet nicht.

| Aufgabe | Befehl |
|---|---|
| Wie die CI bauen und testen (braucht nur den Code) | `scripts/check.sh` |
| Nur das Paket testen | `cd CutawayKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme CutawayKit-Package -destination 'platform=macOS' -testLanguage en` |
| Formatieren, dann linten | `scripts/format.sh` |
| Ein Archiv als App in einem Simulator bereitstellen, für ein laufendes Cutaway | `scripts/replay.sh <file.cutaway>` |
| Jeden Vorgang hundert Runden lang wiederholen und die Speicherkurve ausgeben | `scripts/soak.sh` |

- Nichts wird nach Augenmaß beurteilt. Die Szenenschicht ist durch Unit-Tests abgedeckt; die
  Zeichenschicht rendert abseits des Bildschirms und wird mit den Referenzbildern in `Baselines/`
  verglichen.
- Tests brauchen nie ein Gerät. Verbindungen werden gegen den Mock-Server getestet, der die
  Fixtures des Protokolls abspielt, auf diesem Mac.

## Lizenz

Cutaway ist freie Software, veröffentlicht unter der GNU General Public License v3.0; siehe
[LICENSE](../../LICENSE). Es ist mit [FlatBuffers](https://github.com/google/flatbuffers) (Apache
License 2.0), [DeclarativeAppKit](https://github.com/nothingsh/DeclarativeAppKit) (MIT) und
[DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine) (MIT) gebaut; deren Lizenzen
stehen im Info-Fenster und in [`CutawayKit/Sources/CutawayUI/Resources/Acknowledgements`](../../CutawayKit/Sources/CutawayUI/Resources/Acknowledgements). Das [Cutaway-Protokoll](https://github.com/nothingsh/CutawayProtocol)
steht unter der MIT-Lizenz.
