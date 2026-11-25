<!-- Created by Sébastien DAGUIN -->

# Contribuer à Fullmoon

Les contributions doivent préserver l'expérience native SwiftUI et le fonctionnement
local du moteur Noctis.

## Préparer l'environnement

Utiliser un Mac Apple Silicon, Xcode avec Swift 6.4 ou ultérieur et le composant Metal.
Les minima de plateforme sont ceux du projet Xcode et du package Noctis.
La cible macOS est limitée à `arm64` en Debug et Release, en cohérence avec Noctis et le
runtime Python embarqué. Le réglage `ARCHS[sdk=macosx*]` s’applique aussi aux archives
Xcode Cloud ; il ne modifie pas les architectures iOS.

Noctis est une dépendance Swift distante, résolue par Xcode depuis son dépôt GitHub.
Les scripts SearXNG utilisent encore les outils de préparation du dépôt voisin :

```text
NoctisAI/
├── NoctisAi/
└── fullmoon-ios/
```

Depuis `fullmoon-ios`, préparer une fois le runtime macOS avec Python 3.10+, Git et `uv` :

```sh
python3 ../NoctisAi/infrastructure/searxng/setup_runtime.py \
  --standalone --destination build/SearXNG
```

Pour compiler l'application iOS, préparer aussi les variantes iPhone et simulateur :

```sh
build/SearXNG/python/bin/python3 ../NoctisAi/infrastructure/searxng/setup_ios_runtime.py \
  --mac-runtime build/SearXNG --destination build/SearXNG-iOS
```

Ne pas relancer la préparation macOS sur une destination déjà présente : le script
refuse de l'écraser. Les runtimes sont locaux et ne doivent pas être commités.
Voir [README.md](README.md) pour les détails de préparation et de packaging.

## Branche et pull request

Créer une branche dédiée depuis `main` à jour, avec un nom décrivant le changement,
par exemple `feat/nom-court`, `fix/nom-court` ou `docs/nom-court`.

Toute modification passe par une pull request vers `main`. Les pushes directs,
force-pushes et suppressions de `main` sont interdits. La fusion est réservée à
**Sébastien DAGUIN (`Sebastien972-collab`)**.

## Conventions

Respecter le style et l'architecture existants. Garder les changements localisés,
préserver les modifications sans rapport avec la contribution et vérifier les usages
avant de supprimer du code. Expliquer toute évolution d'architecture, de dépendances,
de SDK ou de configuration de build dans le périmètre de la pull request.

Pour le chat, préserver l'annulation, le contenu sauvegardé et le rendu Markdown.
Ne pas forcer un défilement à chaque fragment de texte ni rejouer une animation sur
l'ensemble de la réponse. Respecter Dynamic Type et les préférences de réduction
du mouvement et de la transparence.

Préserver les attributions du projet d'origine et des dépendances. Ne pas remplacer
les headers des auteurs tiers et ne pas signer des fichiers avec le nom d'un outil IA.

## SwiftLint

```sh
./scripts/lint.sh
```

SwiftLint 0.65.1 s'exécute également avant la compilation dans Xcode. Le script
télécharge la version portable dans un cache temporaire et vérifie son SHA-256.
Une installation locale de la même version peut être fournie avec `SWIFTLINT_BIN`.

La baseline conserve les écarts existants ; les nouvelles violations sont bloquantes.
Ne pas régénérer `.swiftlint-baseline.json` pour masquer une régression.

## Vérifier les builds et l'interface

Une fois les runtimes préparés, depuis la racine du dépôt :

```sh
xcodebuild -project fullmoon.xcodeproj -scheme fullmoon -configuration Debug \
  -destination 'generic/platform=macOS' -skipPackageUpdates -skipMacroValidation \
  -skipPackagePluginValidation \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build

xcodebuild -project fullmoon.xcodeproj -scheme fullmoon -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -skipPackageUpdates -skipMacroValidation \
  -skipPackagePluginValidation \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
```

Ces commandes vérifient la compilation, pas la signature de distribution ni le
comportement sur un iPhone physique. Pour un changement d'interface, contrôler les
thèmes clair/sombre, le texte long, la génération, l'arrêt et le défilement manuel.
Ajouter des captures pertinentes à la pull request et distinguer ce qui a été
compilé de ce qui a été réellement testé dans l'application.

### Vérifier la recherche Web sur iPhone

Sur un iPhone physique, relever le moteur affiché dans les réglages, puis demander
les actualités IA du jour et relancer avec « Tu peux utiliser web search ? » dans
la même conversation. Vérifier une recherche réelle, des sources consultables et
une réponse fondée sur les résultats. Contrôler aussi l'absence de sources inventées
en cas d'échec réseau, puis l'arrêt et la reprise d'une génération.

Dans Console sur le Mac, sélectionner l'iPhone connecté, activer les messages
d'information et filtrer sur le sous-système `com.sebastiendaguin.NoctisAi` et la
catégorie `WebSearch`. `search_requested` confirme que le service a été appelé ;
`python_ready` et `script_ready` confirment le chargement de l'interpréteur et du
script, pas encore celui de SearXNG. `search_started` précède l'appel Python et
`search_completed` confirme une réponse décodée, éventuellement sans résultat.
Un échec indique uniquement son étape et une catégorie fermée, par exemple
`stage=execute_search category=ImportError` ; aucune requête, URL, donnée utilisateur,
message d'exception ou chemin n'est journalisé. Un appel Python déjà lancé peut
terminer après une annulation, sans que sa réponse soit affichée.

Une compilation iOS réussie ne remplace pas cet essai sur appareil. Mentionner
explicitement dans la pull request lorsqu'il reste à effectuer.

## Dépendances verrouillées et Xcode Cloud

Versionner `fullmoon.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
Ce fichier doit être généré par Xcode et rester cohérent avec les références du projet :

```sh
xcodebuild -resolvePackageDependencies -project fullmoon.xcodeproj -scheme fullmoon \
  -skipMacroValidation -skipPackagePluginValidation
```

Lors d'une modification de dépendance, vérifier puis commiter le projet et le lockfile
ensemble. La CI vérifie la résolution et refuse un fichier absent ou modifié par Xcode.
Les autres fichiers locaux du workspace restent ignorés.

Xcode Cloud exécute `ci_scripts/ci_post_clone.sh` avant le build. Ce script vérifie la
révision Noctis du lockfile, prépare le checkout voisin attendu par le packaging, installe
les outils nécessaires et prépare SearXNG. L'action iOS prépare aussi le runtime Mac,
utilisé comme hôte de compilation des dépendances Python. Les validations de plugins et
macros utilisent les mêmes réglages que GitHub Actions dans le runner éphémère.

Le script exige un environnement Xcode Cloud Apple Silicon. Il conserve les protections
contre l'écrasement d'un runtime ou d'un checkout différent, et ne modifie ni le lockfile
ni la configuration de signature. Les runtimes générés restent exclus de Git.

## Contenu de la pull request

Décrire le problème, le résultat et les vérifications effectuées. Mentionner les
plateformes non vérifiées et les limites restantes. Éviter les refontes et le
formatage sans rapport avec le sujet.

Ne pas commiter de secrets, `.env`, profils de signature, trousseaux, poids de modèles,
runtimes ou artefacts de build. Respecter la [licence MIT du projet d'origine](LICENSE)
et conserver les licences et notices des dépendances distribuées.

## Tests de l'état du modèle

Les tests de présentation de l'état Noctis s'exécutent sans télécharger de poids :

```sh
swiftc fullmoon/Domain/ModelStatus.swift tests/ModelStatusTests.swift -o /tmp/noctis-model-status-tests
/tmp/noctis-model-status-tests
```

Ils vérifient les états initial, téléchargement, chargement, prêt, erreur et reprise,
ainsi que la priorité du modèle connecté sur les erreurs de conversation.
L'API Noctis actuelle expose les phases sans pourcentage ni inspection publique du
cache. L'état initial est donc « Non chargé » et la progression reste indéterminée.
Ces tests ne remplacent pas une compilation iOS ni un essai d'inférence sur appareil.
