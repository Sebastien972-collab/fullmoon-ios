<!-- Created by Sébastien DAGUIN -->

# Interface Noctis — base Fullmoon

Interface SwiftUI avec conversations locales SwiftData et moteur Noctis exécuté sur Mac ou iOS.

## Interface iPhone et iPad

L’interface adapte les composants de
[ChatGPT iOS UI](https://github.com/bryanrg22/chatgpt-ios-ui) à Noctis : compositeur
natif, contrôles Liquid Glass, historique recherchable et présentation sobre des messages.
La navigation suit la size class : tiroir en compact, barre latérale en régulier.
Les vues macOS et visionOS conservent leur parcours existant.

Le package local `Packages/NoctisChatUI` expose uniquement la présentation. Les conversations,
leurs identifiants SwiftData, le streaming, les erreurs, l'annulation et le contexte personnel
restent gérés par le ViewModel Noctis existant. Les contenus et services de démonstration
de l'amont ne sont pas intégrés. La recherche Web continue de passer par Noctis.
Le rendu Markdown existant est conservé, sans nouvelle dépendance distante.

La provenance et la licence MIT sont conservées dans le package ; la licence est également
consultable dans Réglages → Crédits sur iOS. Cette adaptation est indépendante d'OpenAI.

Pour essayer cette version depuis le dépôt Fullmoon :

```sh
git fetch origin
git switch test/gpt-oss-macos
```

Ouvrir `fullmoon.xcodeproj`. Cette branche de test part de `main` et utilise GPT uniquement
sur Mac. L’interface et le modèle iPhone restent ceux de la base. Les instructions de
préparation du moteur et de SearXNG ci-dessous s’appliquent toujours.

Vérifier sur appareil : envoi d'un seul échange, streaming et arrêt, changement de
conversation pendant une génération, recherche/suppression dans l'historique, erreur
et nouvelle tentative, restitution des conversations après relancement. Contrôler
les apparences claire/sombre, Dynamic Type, le clavier et les dispositions compactes/régulières.

## Développement

La branche `test/gpt-oss-macos` sélectionne le modèle selon la plateforme :

| Plateforme | Modèle local | Moteur |
| --- | --- | --- |
| macOS | [`mlx-community/gpt-oss-20b-MXFP4-Q8`](https://huggingface.co/mlx-community/gpt-oss-20b-MXFP4-Q8) | MLX |
| iPhone et iPad | [`prism-ml/Ternary-Bonsai-2-4B-mlx-2bit`](https://huggingface.co/prism-ml/Ternary-Bonsai-2-4B-mlx-2bit), identique à la base | MLX |

Le projet Xcode référence la branche NoctisAi `test/gpt-oss-macos` ; le commit
utilisé est verrouillé dans `Package.resolved`. Cette base conserve les corrections iOS
et Web déjà intégrées dans `main`.
Les scripts de préparation
et de packaging SearXNG utilisent encore `../NoctisAi` ; conserver les deux dépôts côte à côte :

```text
NoctisAI/
├── NoctisAi/
└── fullmoon-ios/
```

Ouvrir `fullmoon.xcodeproj`, sélectionner la cible Mac ou iPhone et lancer l’application.
Sur Mac, le modèle GPT reçoit et génère du texte ; cet essai n’ajoute pas de traitement
d’images ou d’audio.

### Essayer gpt-oss-20b sur Mac

Depuis chaque dépôt, récupérer la branche de test :

```sh
git fetch origin
git switch test/gpt-oss-macos
git pull --ff-only
```

La dépendance distante du projet suffit pour obtenir le moteur Noctis. Le checkout voisin
sert aux scripts SearXNG décrits ci-dessous. Préparer ces runtimes s’ils ne le sont pas déjà,
puis compiler l’application depuis Xcode sur l’appareil souhaité.

Sur iOS, Fullmoon crée `IOSModelService(preference: .mlx)` avec le service Web embarqué.
Il conserve exactement le modèle Bonsai et ses réglages. Sur macOS, Fullmoon crée
`MLXModelService` avec SearXNG embarqué et le modèle GPT fixé par la branche Noctis.
L’essai ne sélectionne pas automatiquement
Foundation Models : une erreur de chargement ou de génération reste visible.

Au premier lancement, choisir « Préparer Noctis ». Si l’accueil a déjà été validé,
ouvrir les réglages et charger le modèle. Vérifier **gpt-oss-20b · MLX** dans
« Modèle IA » sur Mac, puis attendre l’état **Prêt**. Sur iPhone, le titre reste
**Ternary Bonsai 2 (4B) · MLX**.

La conversion GPT publiée représente environ **12,1 Go de poids**. Cette taille ne
comprend pas la mémoire nécessaire au cache de conversation et aux allocations du moteur.
Sur un Mac de 18 Go, commencer avec une seule fenêtre et une conversation courte pour
mesurer la pression mémoire. Les poids Bonsai déjà en cache sont conservés. Le cache de
Locally est distinct de celui de Fullmoon ; les poids GPT peuvent donc être téléchargés à nouveau.

Pour vérifier le parcours, ouvrir une nouvelle conversation, demander une réponse courte
en français, poursuivre le même échange, puis arrêter et relancer une génération.
Vérifier que la réponse affichée ne contient pas de balises du protocole Harmony, puis
changer de conversation et reprendre un échange sauvegardé. Essayer ensuite une recherche
Web explicite et contrôler les sources ainsi que l’absence d’erreur `invalid tool call`.
L’inférence est locale ;
la recherche Web nécessite Internet. Le guide
[de contribution](CONTRIBUTING.md#vérifier-la-recherche-web-sur-iphone) décrit les traces
locales permettant de confirmer l’appel du service Web.

Après les essais Mac, lancer la cible iPhone et vérifier que le modèle indiqué reste Bonsai,
que son cache existant est réutilisé et qu’aucun téléchargement GPT n’est déclenché.

Pour revenir à la configuration habituelle, quitter l’application et revenir sur `main`
dans les deux dépôts, puis laisser Xcode résoudre la dépendance correspondante.

### Recherche Web sur Mac, sans Docker

Préparer une seule fois le runtime autonome depuis ce dépôt (Python 3.10+, Git et `uv` requis) :

```sh
python3 ../NoctisAi/infrastructure/searxng/setup_runtime.py --standalone --destination build/SearXNG
```

Cette préparation télécharge Python 3.13.13 pour l’architecture du Mac et installe la révision
SearXNG épinglée par Noctis. Les fichiers restent dans `build/`, ignoré par Git.
La phase Xcode `Embed SearXNG` copie le runtime dans les ressources de l’app et signe ses
bibliothèques et son interpréteur avec l’identité de Fullmoon, avant la signature finale.
Le script de build a besoin de l’accès au trousseau ; son sandbox de build est désactivé.
Le sandbox de l’application reste actif, avec les droits réseau client et serveur.

Fullmoon démarre SearXNG à la première recherche, sur un port local attribué automatiquement,
puis l’arrête après 120 secondes d’inactivité ou à la fermeture du canal parent.
L’app ne dépend ni de Docker, ni du Python installé sur le Mac de l’utilisateur.
Si le runtime manque, une erreur est affichée au lieu de se connecter au port Docker 8888.
Un accès Internet reste nécessaire pour interroger les moteurs de recherche.

La distribution macOS cible les Mac Apple Silicon (`arm64`), en Debug comme en Release.
La cible Xcode applique cette architecture au SDK macOS pour correspondre au moteur Noctis
et au runtime Python embarqué, y compris lors des archives Xcode Cloud.
La notarisation et la validation App Store restent des étapes de distribution distinctes.

### Recherche Web embarquée sur iOS

Après la préparation du runtime Mac ci-dessus, préparer les variantes iPhone et simulateur :

```sh
build/SearXNG/python/bin/python3 ../NoctisAi/infrastructure/searxng/setup_ios_runtime.py \
  --mac-runtime build/SearXNG --destination build/SearXNG-iOS
```

Cette étape nécessite Xcode complet et un accès Internet. Elle conserve les versions de
SearXNG et de ses dépendances, prépare Python iOS 3.13 via BeeWare `3.13-b14`, et compile
`lxml`, `msgspec` et le pont de `curl_cffi` pour **arm64 iPhone et simulateur Apple Silicon**.
Les binaires de `cffi` et `MarkupSafe` viennent de leurs distributions iOS sur PyPI ;
libcurl-impersonate vient de sa distribution iOS officielle `2.3.1`.
La préparation réutilise les fichiers Python du runtime de build Mac, sans le modifier.

Sélectionner ensuite la destination iPhone ou simulateur dans Xcode. La phase existante
`Embed SearXNG` choisit le packaging iOS et signe les modules natifs comme frameworks.
Les ressources et binaires préparés restent dans `build/`, ignoré par Git.

`IOSWebSearchService` conserve un interpréteur pour le processus de l’app et exécute les
recherches sur une file série de fond. Il appelle le pipeline WSGI de SearXNG directement :
aucun sous-processus, port HTTP local, Docker ou serveur distant n’est utilisé.
Les requêtes restent des arguments Python, jamais du code à exécuter. Les résultats sont
limités à 2 Mio puis passent par les contrôles habituels de Noctis.
Une annulation libère immédiatement l’appelant ; une recherche Python déjà commencée
termine en arrière-plan avec les délais réseau SearXNG, avant la prochaine recherche.
L’interpréteur n’est pas déchargé pendant la vie du processus iOS.

Deux adaptations sont appliquées uniquement à la copie iOS de SearXNG : métadonnées de version
figées pour éviter un appel Git à l’exécution, et retrait de `pwd` dans le diagnostic
d’erreur Valkey, iOS n’exposant pas de base d’utilisateurs Unix. Le runtime macOS et son
cycle de processus restent inchangés.

La validation sur un iPhone physique et la distribution App Store restent à effectuer.

## Chargement et conversations

- Les fichiers des modèles MLX sont conservés dans le cache Hugging Face utilisé par l’application.
- Une installation complète est recherchée localement avant tout accès réseau. Une installation
  MLX absente ou incomplète passe par le téléchargement Hugging Face, qui réutilise les fichiers présents.
- L’interface distingue « Téléchargement… », « Chargement du modèle… » et « Prêt ».
- Chaque fenêtre conserve son moteur pendant sa durée de vie. Changer de chat ou interrompre
  une réponse réinitialise uniquement la conversation, après le nettoyage de la génération.
- L’historique SwiftData et le contexte d’identité sont transmis au service MLX avec leurs rôles.
  Les conversations sauvegardées restent complètes.
- Après fermeture complète, les poids MLX doivent être rechargés du disque en mémoire. Un cache
  supprimé par l’utilisateur ou le système nécessite une nouvelle installation.

## Interaction

Sur Mac, **Retour** envoie le message, **Maj+Retour** conserve la saisie multiligne et
**Commande+Retour** reste disponible. L’envoi est bloqué pendant une réponse ; le bouton Arrêt
attend le nettoyage du moteur avant d’autoriser le message suivant.

Le premier fragment s’affiche immédiatement. Les fragments suivants sont regroupés par fenêtres
de 50 ms pour limiter les recalculs du Markdown. Le texte en attente est affiché à la fin, lors
d’un arrêt ou d’une erreur. Les anciens messages utilisent une liste paresseuse ; remonter dans
la conversation suspend le défilement automatique, qui reprend près du bas ou au nouvel envoi.

## Mesures

Les journaux macOS, catégorie `Inference`, enregistrent les durées de téléchargement et de
chargement séparément, le délai avant le premier texte et le débit en **caractères par seconde**.
Ils ne contiennent pas le contenu des messages. Ces mesures ne sont pas des tokens par seconde.

Pour comparer deux versions, utiliser le même Mac, le même modèle, les mêmes prompts et une
compilation identique ; séparer démarrage du processus, messages successifs et changement de
conversation. Mesurer la mémoire GPU MLX en plus de la mémoire du processus : la seule mémoire
résidente du processus ne représente pas les poids alloués par Metal.

Mesure ponctuelle du moteur le 4 novembre 2026, avant/après sur le même Mac, en Debug,
avec le modèle déjà installé et le réseau bloqué. Le même prompt demande les nombres de
1 à 20 ; chaque réponse comporte 69 caractères. Le second échange simule un changement
de conversation. Les autres compilations en cours rendent les durées et débits indicatifs.

Ces mesures historiques concernent le modèle Ministral 14B précédemment utilisé ; elles
ne mesurent pas les performances de GPT sur Mac ni celles de Bonsai sur iPhone.

| Second échange | Avant | Après |
| --- | ---: | ---: |
| Préparation de la conversation, chargement inclus | 6,467 s | 0,004 s |
| Premier texte après préparation | 20,873 s | 13,951 s |
| Débit du texte généré | 11,76 caractères/s | 10,10 caractères/s |
| Mémoire MLX active | 8,11 Gio | 8,11 Gio |
| Pic mémoire MLX du processus | 8,57 Gio | 8,84 Gio |

Ce test confirme la suppression du rechargement des poids et le fonctionnement hors ligne.
Il ne démontre pas de gain de débit d’inférence ; le pic mémoire augmente légèrement avec
la réutilisation du cache de session. La taille du modèle et le contexte restent inchangés.

## Origine et licence

Projet d’origine : [Fullmoon](https://github.com/mainframecomputer/fullmoon-ios),
par Mainframe Computer, Inc. Licence MIT : voir `LICENSE`.
Le moteur utilise [MLX Swift](https://github.com/ml-explore/mlx-swift).

## SwiftLint et contributions

Le build Xcode exécute SwiftLint avant la compilation. Le contrôle peut aussi être lancé seul :

```sh
./scripts/lint.sh
```

Le script télécharge SwiftLint **0.65.1** dans un cache temporaire et vérifie son SHA-256.
`SWIFTLINT_BIN=/chemin/vers/swiftlint ./scripts/lint.sh` permet d'utiliser une installation
locale de la même version. La baseline conserve les écarts existants ; les nouvelles
violations sont bloquantes. Ne pas la régénérer pour masquer une régression.

Les règles de contribution et les commandes de validation sont décrites dans
[CONTRIBUTING.md](CONTRIBUTING.md).

### Xcode Cloud

Le fichier `Package.resolved` généré par Xcode est versionné avec le projet. La CI vérifie
que les dépendances se résolvent à partir de ce verrou avant de compiler l'application.
Le script `ci_scripts/ci_post_clone.sh` prépare Metal, les outils Python, le dépôt Noctis
voisin à la révision verrouillée et les runtimes SearXNG requis par chaque action Cloud.
Cette préparation permet aux builds Cloud d'utiliser les mêmes dépendances que les builds
GitHub Actions, sans modifier les versions pendant le build.

## Premier démarrage

Le parcours d’accueil reprend la présentation et la préparation du modèle du projet
Fullmoon d’origine, adaptées au moteur Noctis et aux réglages actuels. Il s’affiche
jusqu’à la première préparation réussie, puis à la validation « Commencer la conversation ».
Le téléchargement éventuel ne commence qu’après « Préparer Noctis ». Un modèle en cache
est réutilisé et le moteur chargé est conservé lors de l’ouverture du chat.
Sur macOS, les textes présentent gpt-oss-20b, les conversations texte et la taille du
téléchargement. Sur iOS, ils présentent toujours Ternary Bonsai 2 (4B).
La préparation vérifie la disponibilité de Metal avant de charger le modèle MLX.
Les erreurs restent visibles avec la possibilité de réessayer. L’apparence peut être
personnalisée depuis l’accueil, sans charger le modèle.
