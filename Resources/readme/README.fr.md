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

**Voir comment l'interface est construite**

- L'arbre des calques de chaque fenêtre, avec les vues racines des view controllers et les variables
  membres qui détiennent chaque calque ou vue signalées, de sorte qu'un calque peut être remonté
  jusqu'au code.
- Une capture d'écran de chaque calque, à plat en 2D ou écartées en 3D. Tournez, zoomez et déplacez
  à la souris ou au trackpad ; changez l'espacement entre les calques ; affichez les calques masqués.
- Chaque position, taille, rotation et échelle telles qu'à l'écran de l'appareil, transformations 3D
  comprises.
- Mesurer : maintenez ⌥ et pointez un autre calque pour voir les distances entre celui-ci et le
  calque sélectionné, en 2D comme en 3D.

**Travailler dans le détail**

- Les attributs du calque et de la vue sélectionnés, groupés tels que l'app les rapporte. Les
  attributs modifiables ont des contrôles : texte, nombres que l'on fait glisser, interrupteurs,
  sélecteurs de couleur, menus locaux pour les énumérations. Les modifications sont appliquées
  aussitôt dans l'app en cours d'exécution, et ⌘Z les annule.
- Les contraintes Auto Layout qui font référence à la vue sélectionnée, avec celles qui ne sont pas
  en vigueur signalées, et l'autre extrémité de chaque contrainte signalée dans l'aperçu. Cliquez sur
  l'autre extrémité pour vous y rendre.
- Rechercher dans l'arbre, se concentrer sur un sous-arbre, déplier jusqu'à une profondeur donnée,
  rafraîchir un sous-arbre seul.

**Garder ce que vous avez trouvé**

- Enregistrer une inspection sous forme d'archive `.cutaway` et l'ouvrir plus tard, sur n'importe
  quel Mac, sans appareil : l'arbre, les captures d'écran, les attributs et les contraintes y sont
  tous, avec la vue que vous aviez.
- Exporter la capture d'écran d'un calque, seul ou avec ses sous-calques, en PNG.

**Conçu pour l'usage quotidien**

- Trouve les apps de lui-même : dans les simulateurs de ce Mac et sur les appareils connectés en USB.
- Affiche l'arbre d'abord et les captures d'écran à mesure qu'elles arrivent ; les grands arbres
  restent réactifs.
- Se reconnecte quand une app revient. Suit l'état de l'app : quand elle passe en arrière-plan,
  Cutaway l'indique et reprend quand elle revient.
- En anglais, chinois simplifié, chinois traditionnel, japonais et coréen.
- Ne parle qu'aux apps de ce Mac et à travers le câble USB. Aucune mesure d'audience, aucun rapport
  de plantage.

<a id="requirements"></a>
## Prérequis

- macOS 14 ou version ultérieure, sur un Mac dont le GPU prend en charge Metal (tout Mac qui exécute
  macOS 14).
- Une app qui intègre [CutawayServer](https://github.com/nothingsh/CutawayServer), exécutée dans
  l'iOS Simulator ou sur un iPhone ou un iPad connecté au Mac en USB.

Cutaway n'est pas sandboxé, parce que le socket qu'il utilise pour atteindre les appareils en USB est
hors de la sandbox. C'est aussi pourquoi il est distribué en dehors du Mac App Store.

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

**Cutaway › Check for Updates…** vous indique quand une version plus récente est sortie. Vous pouvez
aussi compiler Cutaway depuis les sources ; voir [Développement](#development).

## Démarrage rapide

1. Ajoutez [CutawayServer](https://github.com/nothingsh/CutawayServer) à votre app iOS et appelez `CutawayServer.start()` une fois au lancement.
   Le [README](https://github.com/nothingsh/CutawayServer#readme) du serveur donne les deux lignes
   pour UIKit et SwiftUI. Il n'est compilé que dans les builds Debug.
2. Lancez votre app dans le Simulator, ou sur un appareil connecté au Mac par un câble.
3. Ouvrez Cutaway. Votre app apparaît dans la liste en quelques secondes. Choisissez-la.

## Utiliser Cutaway

### La liste des calques

La barre latérale liste les calques de chaque fenêtre sous forme d'arbre. Une ligne montre la classe
du calque, la vue qu'il porte, le view controller dont il est la vue racine, et la variable membre
qui le détient, par exemple `HomeViewController.titleLabel`. Les lignes grisées sont masquées ou
entièrement transparentes.

- **Filtrez** l'arbre avec le champ en haut : les lignes dont le titre ou la classe contient le texte
  restent, avec leurs ancêtres.
- **Concentrez-vous** sur un calque (⌥⌘↓) pour n'afficher que son sous-arbre, dans la liste et dans
  l'aperçu ; le chemin au-dessus de la liste permet d'en ressortir.
- **Dépliez** jusqu'à une profondeur choisie, ou tout, depuis le menu à côté du filtre (⌥⌘→ et ⌥⌘←
  pour tout). Quand une app est inspectée pour la première fois, l'arbre s'ouvre jusqu'au view
  controller à l'écran.
- **Double-cliquez** sur une ligne pour la déplier ou la replier. Double-cliquer sur un calque dans
  l'aperçu fait de même.

### L'aperçu

L'aperçu dessine chaque calque visible à sa place sur l'écran, avec sa capture d'écran, à mesure que
l'arbre arrive, puis que chaque capture d'écran arrive.

- **2D ou 3D** (⌘1, ⌘2) depuis la barre d'outils. En 3D, les calques sont écartés selon leur
  profondeur ; replier une ligne dans la liste replie son sous-arbre en un seul.
- **Tournez** en faisant glisser en 3D ; **déplacez** en faisant défiler ou, en 2D, en faisant
  glisser ; **zoomez** en pinçant ou avec ⌘ et la molette, autour du pointeur. **Reset View**
  (réinitialiser la vue, ⌘0) revient au point de départ.
- **L'espacement des calques** en 3D est le curseur sous l'aperçu, de 0 à 200 points.
- **Show Hidden Layers** (afficher les calques masqués, ⇧⌘H) dessine aussi les calques masqués ou
  transparents, dans leur propre style. **Show Borders** (afficher les bordures, ⇧⌘B) trace le
  contour de chaque calque. Les deux interrupteurs sont aussi sous l'aperçu.
- **Mesurer** : un calque étant sélectionné, maintenez ⌥ et pointez un autre calque. Les distances
  entre les deux sont dessinées avec leurs valeurs en points, en 2D comme en 3D.
- Cliquez sur un calque pour le sélectionner ; la liste et les attributs suivent. Le calque sous le
  pointeur est mis en évidence.

### Attributs

L'inspecteur à droite montre les attributs du calque sélectionné et de sa vue, dans les groupes que
l'app rapporte, tels que `layer`, `view` et `label`. Cutaway n'a pas de liste à lui : ce qui
apparaît est ce que [CutawayServer](https://github.com/nothingsh/CutawayServer) envoie, il montre donc tout ce que connaît la version du serveur
intégrée à l'app.

- Les attributs que l'app marque modifiables ont des contrôles : un champ de texte, un champ
  numérique que l'on fait glisser, un interrupteur, un sélecteur de couleur avec opacité, un menu
  local pour les énumérations, et des champs par composante pour les points, les tailles, les
  rectangles, les marges (insets) et les transformations.
- Une modification est envoyée dès que vous la validez, ou en continu pendant que vous faites
  glisser. L'app répond avec les attributs du calque, de sorte qu'un attribut qui change avec un
  autre (comme l'opacité d'un calque avec l'alpha de sa vue) est mis à jour lui aussi.
- ⌘Z annule la dernière modification et ⇧⌘Z la rétablit, tant que dure l'inspection.
- Une modification que l'app refuse est expliquée dans la ligne, et la valeur précédente revient.

Après une modification, Cutaway rafraîchit les captures d'écran des calques qu'elle a pu affecter.

### Contraintes

Sous les attributs, les contraintes Auto Layout d'une vue sont listées telles que l'app les
rapporte : `self.leading = Safe Area of UIView.leading + 16`, avec la priorité quand elle est
inférieure à 1000 et l'identifiant quand il y en a un. Les contraintes qui ne sont pas en vigueur
sont grisées et signalées ; celles que génère UIKit sont repliées en une seule ligne. Cliquez sur
l'autre extrémité d'une contrainte pour sélectionner cette vue. Dans l'aperçu, les autres extrémités
des contraintes de la vue sélectionnée sont signalées.

### Rafraîchissement

Cutaway montre l'app telle qu'elle était au moment où il la lui a demandée. **Refresh** (rafraîchir,
⌘R) redemande tout l'arbre et chaque capture d'écran, en conservant votre sélection, le dépliage et
la caméra. **Refresh Selected Subtree** (rafraîchir le sous-arbre sélectionné, ⇧⌘R, aussi dans le
menu contextuel de la ligne) ne demande que le sous-arbre de ce calque. Si l'app passe en
arrière-plan, Cutaway attend ; si la connexion est perdue, la dernière image reste et Cutaway se
reconnecte quand la même app est trouvée à nouveau.

### Archives

**Save Archive…** (enregistrer l'archive, ⌘S) rassemble l'arbre, l'icône, et les captures d'écran,
les attributs et les contraintes de chaque calque, calques masqués compris, dans un seul fichier
`.cutaway`, avec l'aspect de la fenêtre. Le fichier s'ouvre avec **Open…** (ouvrir, ⌘O), depuis le
Finder, ou en le déposant sur l'icône de Cutaway, dans sa propre fenêtre, et tout fonctionne comme
en ligne, sauf la modification. Plusieurs archives peuvent être ouvertes à la fois, à côté d'une
inspection en direct.

**Export Layer Screenshot…** (exporter la capture d'écran du calque, ⇧⌘E) et **Export Screenshot
with Sublayers…** (exporter la capture d'écran avec les sous-calques, ⌥⇧⌘E) écrivent l'image du
calque sélectionné en PNG à l'échelle de l'appareil, avec transparence, et sans la transformation ni
l'opacité propres au calque.

### Réglages

**Settings…** (réglages, ⌘,) a deux pages. **General** (général) choisit la langue : celle du
système, ou l'une des cinq. **Preview** (aperçu) choisit comment démarre une nouvelle inspection :
2D ou 3D, l'espacement des calques, et si les calques masqués et les bordures sont affichés. Les
fenêtres déjà ouvertes gardent leur aspect.

### Raccourcis clavier

| Action | Touches |
|---|---|
| Ouvrir une archive | ⌘O |
| Enregistrer une archive | ⌘S |
| Exporter la capture d'écran du calque sélectionné, seul / avec ses sous-calques | ⇧⌘E / ⌥⇧⌘E |
| Annuler / rétablir une modification | ⌘Z / ⇧⌘Z |
| Filtrer la liste des calques | ⌘F |
| Tout rafraîchir / le sous-arbre sélectionné | ⌘R / ⇧⌘R |
| 2D / 3D | ⌘1 / ⌘2 |
| Zoom avant / zoom arrière / réinitialiser la vue | ⌘= / ⌘- / ⌘0 |
| Afficher les calques masqués / afficher les bordures | ⇧⌘H / ⇧⌘B |
| Se concentrer sur le calque sélectionné / afficher tous les calques | ⌥⌘↓ / ⌥⌘↑ |
| Tout déplier / tout replier | ⌥⌘→ / ⌥⌘← |
| Afficher ou masquer la barre latérale / l'inspecteur | ⌃⌘S / ⌥⌘I |
| Afficher la liste des apps | ⇧⌘0 |
| Réglages | ⌘, |

## Performances

Une grande interface devrait rester immédiate. Cutaway est conçu autour de ce principe, et sa suite
de tests lui impose les valeurs ci-dessous à chaque exécution. Elles sont mesurées sur un arbre
généré, à l'image d'une app, de 10 000 calques (fenêtres, conteneurs, une barre de navigation et une
longue liste de cellules, chacune avec une icône, des libellés et un séparateur), en build Debug :

| Opération | Limite |
|---|---|
| L'arbre arrive → la liste est à l'écran | 2 s |
| La mise en place de la scène | 1 s |
| Une nouvelle image après un déplacement de la caméra | 16 ms |
| Le dessin d'une image | 16 ms |
| La sélection d'une ligne → l'aperçu et l'inspecteur suivent | 100 ms |
| La recherche dans la liste | 200 ms |
| Tout déplier / tout replier | 1 s |
| L'ouverture d'une archive de l'arbre → la liste est à l'écran | 2 s |

Comment il y parvient :

- **Les captures d'écran restent compressées.** Le modèle ne conserve que les octets compressés qu'il
  a reçus. Ils sont décompressés hors du thread principal, envoyés au GPU, et les pixels sont
  libérés.
- **L'aperçu ne dessine que lors d'un changement.** Aucune image n'est soumise tant que rien ne
  bouge.
- **La lecture suit le rythme du dessin.** Quand les captures d'écran arrivent plus vite qu'elles ne
  sont utilisées, Cutaway cesse de lire sur la connexion, et TCP dit à l'app d'attendre. Rien ne
  s'entasse en mémoire.
- **Rien ne s'accumule.** La suite répète chaque opération dix fois sur 5 000 calques et vérifie
  qu'aucune capture d'écran, texture, requête ni fenêtre ne reste derrière ; une exécution
  d'endurance plus longue (`scripts/soak.sh`) imprime la courbe de mémoire sur une centaine de
  tours.
- **Des données incorrectes ne le font pas planter.** Chaque trame est vérifiée avant d'être
  décodée, et les parseurs sont soumis au fuzzing avec des trames mutées, tronquées et raboutées à
  chaque exécution.

## Comportement sur le Mac

- Toutes les deux secondes, Cutaway essaie les ports 48160 à 48167 sur `127.0.0.1`, où
  [CutawayServer](https://github.com/nothingsh/CutawayServer) écoute dans les simulateurs, et les mêmes ports sur chaque appareil connecté en USB,
  via le `usbmuxd` du système. Une app qui répond au handshake est listée.
- Une connexion par app, conservée tant que l'app est listée. Une app qui a déjà un client est
  laissée tranquille.
- Une requête qui ne reçoit aucun octet pendant 10 secondes est abandonnée ; la connexion est fermée
  quand l'app envoie quelque chose que le [protocole](https://github.com/nothingsh/CutawayProtocol) interdit.
- Cutaway n'établit aucune autre connexion réseau, sauf quand vous choisissez **Check for
  Updates…** : il demande alors à GitHub la liste des versions de ce dépôt, et n'envoie rien sur votre
  Mac.
- Les préférences sont dans `UserDefaults` ; les archives récentes sont dans la liste des documents
  récents du système.

## Feuille de route

Voici les orientations prévues après la 1.0, partagées avec [CutawayServer](https://github.com/nothingsh/CutawayServer). L'ordre et le périmètre
peuvent changer.

- **Protocole 1.0.** Figer le [protocole Cutaway](https://github.com/nothingsh/CutawayProtocol), afin que les fonctionnalités ultérieures ne fassent
  qu'y ajouter.
- **Analyse des interactions.** Afficher les gesture recognizers et les paires target–action ; activer
  et désactiver des gestes ; appeler des méthodes sur des objets.
- **API d'extension pour les apps hôtes.** Attributs personnalisés, nœuds enfants virtuels, et
  configuration telle que des classes repliées par défaut, des alias de couleurs et des vues exclues
  des images.
- **Grandes hiérarchies.** Un mode rapide qui ne capture que les calques visibles ; un transfert par
  morceaux pour les très grandes images.
- **Plus de connexions et de plateformes.** Connexions Wi-Fi, authentifiées et chiffrées ; tvOS et
  visionOS.
- **SwiftUI.** Une hiérarchie sémantique des vues SwiftUI à côté de l'arbre des calques.

## FAQ

**Mon app n'apparaît pas dans la liste.**
Vérifiez que le build intègre [CutawayServer](https://github.com/nothingsh/CutawayServer) (il n'est compilé que dans les builds Debug) et appelle
`CutawayServer.start()`, que l'app est au premier plan, et, sur un appareil, que l'appareil est
connecté par un câble et fait confiance à ce Mac. Le serveur prend le premier port libre entre 48160
et 48167 ; la liste montre une app dont Cutaway ne sait pas parler la version du protocole, avec les
deux versions.

**Cutaway a-t-il besoin du réseau ?**
Non. Il parle aux simulateurs via l'adresse de loopback et aux appareils via l'USB. Il ne contacte
jamais de serveur qui lui soit propre.

**Pourquoi une vue de flou, vidéo ou Metal est-elle vide ?**
Ce contenu est composité par le serveur de rendu du système, hors du processus de l'app ;
[CutawayServer](https://github.com/nothingsh/CutawayServer) ne peut donc pas le rendre à partir de l'arbre des calques.

**Puis-je regarder une app sans l'appareil ?**
Enregistrez une archive pendant que l'appareil est connecté et ouvrez-la n'importe où. Pour le
développement, la bibliothèque de support de test peut aussi rejouer une archive comme s'il
s'agissait d'une app dans un simulateur (`scripts/replay.sh`).

**L'inspection modifie-t-elle mon app ?**
Seules les modifications que vous faites. La capture rétablit tout ce qu'elle touche, et la lecture
des attributs ne déclenche pas de layout ; voir le README de [CutawayServer](https://github.com/nothingsh/CutawayServer).

<a id="development"></a>
## Développement

Cutaway est écrit en Swift 6 avec AppKit et Metal. Le code est un package Swift local,
`CutawayKit`, la target de l'app ne faisant rien d'autre que l'assembler :

| Target | Contenu |
|---|---|
| `CutawayWire` | Les trames, les messages du protocole sous forme de types valeur, et le format d'archive |
| `CutawayTransport` | La découverte des apps, `usbmuxd`, les sessions et les requêtes |
| `CutawayModel` | L'arbre des calques, les captures d'écran et les attributs, et l'état que partagent les fenêtres |
| `CutawayScene` | Où chaque calque est dessiné, dans quel ordre, et le hit testing ; Swift pur |
| `CutawayRender` | Le dessin de la scène avec Metal |
| `CutawayUI` | Les fenêtres, la liste, l'aperçu, l'inspecteur, les réglages |
| `CutawayTestSupport` | Un serveur simulé qui rejoue les fixtures du protocole, des arbres synthétiques, un faux `usbmuxd` |

Le format de transmission est défini dans
[CutawayProtocol](https://github.com/nothingsh/CutawayProtocol), récupéré dans `Protocol/` comme
sous-module ; le code Swift correspondant est généré à partir du schéma et versionné. Rien n'est
partagé avec [CutawayServer](https://github.com/nothingsh/CutawayServer), hormis le protocole.

Après le clonage, exécutez `./setup.sh` une fois. Il récupère le sous-module du protocole, vérifie
la présence de Xcode, XcodeGen et jq, installe les outils aux versions épinglées dans `.tools/`,
configure les hooks git et génère `Cutaway.xcodeproj` à partir de `project.yml`. Le relancer est
sans danger.

| Tâche | Commande |
|---|---|
| Compiler et tester comme le fait la CI (ne dépend que du code) | `scripts/check.sh` |
| Tester le package seul | `cd CutawayKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme CutawayKit-Package -destination 'platform=macOS' -testLanguage en` |
| Formater, puis lint | `scripts/format.sh` |
| Servir une archive comme une app dans un simulateur, pour un Cutaway en cours d'exécution | `scripts/replay.sh <file.cutaway>` |
| Répéter chaque opération pendant une centaine de tours et imprimer la courbe de mémoire | `scripts/soak.sh` |

- Rien n'est jugé à l'œil. La couche scène est couverte par des tests unitaires ; la couche de dessin
  rend hors écran et est comparée aux images de référence dans `Baselines/`.
- Les tests n'ont jamais besoin d'un appareil. Les connexions sont testées contre le serveur simulé
  qui rejoue les fixtures du protocole, sur ce Mac.

## Licence

Cutaway est un logiciel libre, publié sous la GNU General Public License v3.0 ; voir
[LICENSE](../../LICENSE). Il est construit avec [FlatBuffers](https://github.com/google/flatbuffers)
(Apache License 2.0), [DeclarativeAppKit](https://github.com/nothingsh/DeclarativeAppKit) (MIT) et
[DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine) (MIT) ; leurs licences sont
dans le panneau À propos et dans [`CutawayKit/Sources/CutawayUI/Resources/Acknowledgements`](../../CutawayKit/Sources/CutawayUI/Resources/Acknowledgements). Le [protocole Cutaway](https://github.com/nothingsh/CutawayProtocol) est
sous licence MIT.
