<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="cutaway-client-dark.svg">
    <img src="cutaway-client-light.svg" alt="Cutaway — Inspectez les interfaces iOS, calque par calque." width="850">
  </picture>
</p>

[![Swift](https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014+-blue)](#requirements)
[![License](https://img.shields.io/badge/License-GPL--3.0-lightgrey)](../../LICENSE)
[![check](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml/badge.svg)](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml)

[English](../../README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Español](README.es.md) | **Français** | [Deutsch](README.de.md)

*Ceci est une traduction ; en cas de divergence avec le [README anglais](../../README.md), le README anglais fait foi.*

Cutaway est une app macOS qui permet de regarder à l'intérieur de l'interface d'une app iOS en cours
d'exécution. Ajoutez [CutawayServer](https://github.com/nothingsh/CutawayServer) à votre app,
lancez-la dans le Simulator ou sur un appareil connecté en USB, et Cutaway l'affiche dans sa liste.
Choisissez-la, et Cutaway montre l'arbre des calques de l'app, une capture d'écran de chaque calque,
à plat en 2D ou écartées en 3D, ainsi que les attributs et les contraintes Auto Layout du calque que
vous sélectionnez. Les modifications que vous faites aux attributs sont appliquées à l'app en cours
d'exécution.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="overview-dark.png">
    <img src="overview-light.png" alt="Cutaway inspectant une app en 3D : l'arbre des calques, les calques écartés avec des mesures et les attributs du calque sélectionné." width="850">
  </picture>
</p>

<a id="features"></a>
## Fonctionnalités

- **Voyez comment l'interface est construite.** L'arbre des calques de chaque fenêtre, avec les contrôleurs de vue et les variables membres qui détiennent chaque vue signalés. [La liste des calques](https://nothingsh.github.io/Cutaway/guide/hierarchy)
- **Démontez-la en 3D.** Une capture de chaque calque, à plat en 2D ou écartés en 3D ; faites pivoter, zoomez, changez l'espacement. [L'aperçu](https://nothingsh.github.io/Cutaway/guide/preview)
- **Mesurez.** Maintenez ⌥ et pointez un autre calque, dans l'aperçu ou dans la liste, pour voir les distances en points. [Mesurer](https://nothingsh.github.io/Cutaway/guide/measuring)
- **Modifiez-la pendant qu'elle tourne.** Modifiez des attributs : ils s'appliquent aussitôt à l'app en cours d'exécution, et ⌘Z les annule. [Attributs](https://nothingsh.github.io/Cutaway/guide/attributes)
- **Suivez les contraintes.** Chaque contrainte Auto Layout d'une vue, celles qui ne s'appliquent pas signalées, et leurs autres extrémités. [Contraintes](https://nothingsh.github.io/Cutaway/guide/constraints)
- **Essayez le mode sombre et un texte plus grand.** Remplacez l'apparence, la taille du texte, le sens de mise en page et les classes de taille de l'app. [Environnement](https://nothingsh.github.io/Cutaway/guide/environment)
- **Allez à votre code.** Ouvrez une classe dans Xcode, voyez les noms des catalogues de ressources et de chaînes, copiez une commande LLDB. [Code source](https://nothingsh.github.io/Cutaway/guide/source)
- **Gardez ce que vous avez trouvé.** Enregistrez une inspection et ouvrez-la sur n'importe quel Mac sans l'appareil ; exportez un calque en PNG. [Archives et export](https://nothingsh.github.io/Cutaway/guide/archives)

Cutaway ne communique qu'avec les apps de ce Mac et par le câble USB : aucune analyse, aucun rapport de plantage.
Il existe en anglais, chinois simplifié, chinois traditionnel, japonais et coréen.

<a id="requirements"></a>
## Prérequis

- macOS 14 ou version ultérieure, sur un Mac dont le GPU prend en charge Metal (tout Mac qui exécute
  macOS 14).
- Une app qui intègre [CutawayServer](https://github.com/nothingsh/CutawayServer), exécutée dans
  l'iOS Simulator ou sur un iPhone ou un iPad connecté au Mac en USB.

<a id="installation"></a>
## Installation

Téléchargez `Cutaway-<version>.dmg` depuis la page [Releases](https://github.com/nothingsh/Cutaway/releases), ouvrez-le et
glissez Cutaway dans Applications. Cutaway est open source et ses builds ne sont pas notarisés par
Apple : la première fois que vous l'ouvrez, macOS indique qu'il ne peut pas vérifier le développeur.
Ouvrez **Réglages Système › Confidentialité et sécurité** et choisissez **Ouvrir quand même**, ou
exécutez :

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

**Cutaway › Check for Updates…** vous indique quand une version plus récente est sortie.

## Démarrage rapide

1. Ajoutez [CutawayServer](https://github.com/nothingsh/CutawayServer) à votre app iOS et appelez `CutawayServer.start()` une fois au lancement.
   Il n'est compilé que dans les builds Debug.
2. Lancez votre app dans le Simulator, ou sur un appareil connecté au Mac par un câble.
3. Ouvrez Cutaway. Votre app apparaît dans la liste en quelques secondes. Choisissez-la.

Le [guide de démarrage](https://nothingsh.github.io/Cutaway/guide/getting-started) donne chaque étape, le code pour UIKit et SwiftUI, et ce qu'il faut vérifier quand votre app n'apparaît pas.

<a id="documentation"></a>
## Documentation

Tout le reste est sur le [site de Cutaway](https://nothingsh.github.io/Cutaway/) (pour l’instant en anglais et en chinois simplifié seulement) :

- [Guide](https://nothingsh.github.io/Cutaway/guide/getting-started) : utiliser Cutaway, tâche par tâche, et tous les [raccourcis clavier](https://nothingsh.github.io/Cutaway/guide/shortcuts).
- [Intégration](https://nothingsh.github.io/Cutaway/integrate/) : ajouter CutawayServer à votre app, les builds Debug et Release, et afficher les informations propres à votre app.
- [Protocole](https://nothingsh.github.io/Cutaway/protocol/) : comment Cutaway et CutawayServer communiquent, et quelles versions fonctionnent ensemble.
- [FAQ et dépannage](https://nothingsh.github.io/Cutaway/resources/faq), [Confidentialité et sécurité](https://nothingsh.github.io/Cutaway/resources/privacy), [Performances](https://nothingsh.github.io/Cutaway/resources/performance), [Notes de version](https://nothingsh.github.io/Cutaway/resources/releases), [Feuille de route](https://nothingsh.github.io/Cutaway/resources/roadmap).

<a id="development"></a>
## Développement

Comment compiler et tester Cutaway, et comment les modifications sont relues : voir [CONTRIBUTING.md](../../CONTRIBUTING.md).
La page [Contributing](https://nothingsh.github.io/Cutaway/resources/contributing) du site explique comment les trois dépôts s’articulent.

## Licence

Cutaway est un logiciel libre, publié sous la GNU General Public License v3.0 ; voir
[LICENSE](../../LICENSE). Il est construit avec [FlatBuffers](https://github.com/google/flatbuffers)
(Apache License 2.0), [DeclarativeAppKit](https://github.com/nothingsh/DeclarativeAppKit) (MIT) et
[DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine) (MIT) ; leurs licences sont
dans le panneau À propos et dans [`CutawayKit/Sources/CutawayUI/Resources/Acknowledgements`](../../CutawayKit/Sources/CutawayUI/Resources/Acknowledgements). Le [protocole Cutaway](https://github.com/nothingsh/CutawayProtocol) est
sous licence MIT.
