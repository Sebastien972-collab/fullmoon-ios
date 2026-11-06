<!-- Created by Sébastien DAGUIN -->

# Identité, protection locale et iCloud

## Audit et choix d’architecture

La fondation de `feat/user-identity-icloud-foundation` contenait un profil SwiftData, un formulaire, un sélecteur Contacts et un verrouillage natif. Le profil n’était pas transmis au moteur. L’option iCloud ne réalisait pas de synchronisation. Les transitions d’inactivité pouvaient provoquer plusieurs demandes d’authentification. Les entitlements CloudKit et la description Face ID manquaient.

Les conversations existantes restent la source de vérité locale. `Thread` et `Message` conservent leurs identifiants, relations et champs. Leurs contraintes d’unicité et le besoin d’activation dynamique motivent une synchronisation CloudKit explicite, plutôt qu’un conteneur SwiftData CloudKit permanent. `NoctisPersistence` ouvre le même emplacement SwiftData par défaut avec `cloudKitDatabase: .none`, même quand les entitlements CloudKit sont présents. Une erreur d’ouverture affiche une erreur sans supprimer ou recréer la base.

`NoctisUserIdentity` sérialise les accès au profil dans le contexte principal partagé du conteneur de l’installation, sans suspension entre recherche et création. Les anciens profils éventuellement dupliqués ne sont pas détruits : le plus récemment modifié est utilisé, avec un départage stable par identifiant. Aucun identifiant Apple ou contact n’est déduit pour remplir le profil.

## Identité et consentement

Le profil contient les noms, surnom, langue, profession, instructions et informations personnelles. La personnalisation et les cinq autorisations sont désactivées par défaut. Les réglages modifient un brouillon ; le bouton Enregistrer applique les champs et les autorisations. L’import Contacts iOS utilise le sélecteur système sans demander l’accès complet au carnet. Seuls prénom, nom et surnom sont proposés, chacun décoché initialement, puis confirmés et enregistrés. Aucun téléphone, courriel, adresse, anniversaire ou identifiant de contact n’est conservé. macOS utilise le formulaire manuel.

`NoctisIdentitySession` transmet réellement les champs autorisés au contrat `AIModelService.resetConversation(history:)` de Noctis. Le contexte personnel est un message système distinct, ajouté seulement en mémoire ; il ne crée pas de message SwiftData visible. Le moteur existant conserve son instruction fondamentale et le streaming existant. Le contexte est reconstruit lorsque le fil ou les données autorisées changent. Désactiver la personnalisation ne supprime pas les anciens messages ni une réponse déjà commencée.

Les valeurs sont bornées et encodées en JSON, avec une instruction explicite les traitant comme des données utilisateur non fiables, incapables de remplacer les règles de Noctis ou les autorisations d’outils. Cela réduit l’ambiguïté du prompt sans constituer une garantie mathématique contre toute injection de prompt.

## Verrouillage et stockage

`NoctisLockController` est partagé entre les fenêtres. `.deviceOwnerAuthentication` demande Face ID, Touch ID ou le mécanisme de secours du système. Activation et désactivation nécessitent une authentification. Une annulation n’entraîne pas de nouvelle demande automatique dans le même cycle. Le passage en arrière-plan verrouille et invalide les résultats d’authentification antérieurs. L’inactivité affiche un écran opaque sans traiter la fenêtre Face ID comme un nouveau verrouillage.

Le contenu de conversation et ses tâches de chargement ne sont montés qu’après déverrouillage. Le conteneur SwiftData reste local. iOS applique la protection complète aux fichiers SQLite, WAL/SHM présents et au dossier parent, et exclut ce dossier de la sauvegarde système. Les permissions des fichiers sont limitées à l’utilisateur. Sur Mac, le chiffrement du volume relève de FileVault. L’authentification de l’interface ne constitue pas un chiffrement applicatif de la base. Aucun secret, code de déverrouillage ou donnée biométrique n’est ajouté au Keychain.

## Synchronisation explicite

- Aucun échange automatique quand l’option est désactivée ; vérifier la disponibilité depuis les réglages consulte le compte sans activer la synchronisation.
- Confirmation avant activation, base privée `iCloud.com.sebastiendaguin.NoctisAi`, aucun serveur Noctis.
- Conversations et messages synchronisés ; inclusion du profil via un consentement séparé. Ce consentement inclut tous les champs enregistrés et les versions conservées après conflit, même les champs exclus de la personnalisation.
- Aucun poids MLX, cache de modèle, verrouillage de l’appareil ou brouillon de saisie synchronisé. Le projet n’a pas de modèle de mémoire personnelle séparé à synchroniser.
- Échanges au premier plan, après déverrouillage, toutes les 30 secondes ou sur demande. Pas de push ni de synchronisation permanente en arrière-plan. Les imports sont suspendus pendant une génération.
- `NoctisSyncRecord` conserve le journal local et l’empreinte du dernier acquittement. Le transport est un acteur ; les données transférées sont des valeurs `Sendable`, jamais les entités SwiftData. Réseau et lecture/écriture des assets ne s’exécutent pas sur le contexte principal.
- Zone de données `NoctisIdentity-v1`, enregistrements `NoctisDocument` contenant un asset JSON `document`. Lecture paginée des changements de zone, écritures par lots de 50 avec contrôle de version serveur, trois tentatives maximum par échange en cas de conflit.
- Identifiants stables pour les conversations/messages, fusion des messages distincts et marqueurs de suppression pour empêcher une résurrection depuis un appareil hors ligne. Des copies de conversations préfixées `↯` conservent les modifications concurrentes incompatibles ; leurs identifiants sont déterministes.
- Conflits de profil départagés par date/auteur, avec archivage des versions différentes. Les révocations concurrentes dominent les autorisations. Restaurer une version garde la personnalisation désactivée. Les horloges d’appareils peuvent influencer le choix de la version active ; les versions archivées restent récupérables.
- Échecs réseau conservant les changements en attente. « Synchronisé » n’est affiché qu’après lecture, application, envoi et acquittement réussis, sans modification locale encore en attente. La date affichée est celle du dernier échange réussi.
- Désactiver invalide la session et bloque les opérations suivantes, sans supprimer local ou distant. Une requête déjà soumise à CloudKit peut terminer ; les octets déjà envoyés ne peuvent pas être rappelés.
- Le compte est lié à une empreinte locale. Un autre compte bloque la synchronisation sans fusion ni réassociation automatique. Cette version ne propose pas de transfert vers un autre compte.
- Supprimer dans iCloud désactive la synchronisation, conserve la base locale et supprime seulement la zone de données Noctis. La zone `NoctisControl-v1` garde un marqueur aléatoire `reset`, de type `NoctisControl`, champ `generation`, sans profil ni conversation. Il empêche les autres appareils de recréer silencieusement les données supprimées ; une réactivation explicite est nécessaire.

Les marqueurs de suppression et les archives peuvent croître. Les échanges relisent actuellement la zone entière ; volumes importants, temps de préparation des instantanés SwiftData sur le contexte principal, quotas et performances doivent être mesurés avant un déploiement large. Les suppressions distantes ne suppriment pas les copies locales des autres appareils ; un appareil réactivé explicitement peut renvoyer ses données conservées. Le stockage CloudKit privé n’est pas présenté comme un chiffrement applicatif de bout en bout.

## Migration et tests

Migration additive : champs du profil avec valeurs par défaut, ajout du journal `NoctisSyncRecord`, conservation des types `Thread`, `Message`, `Role`, UUID et relations existants. `Role` a simplement été déplacé dans le fichier du modèle Message. Le `Sendable` incorrect de l’entité SwiftData `Thread` a été retiré. Aucune version de dépendance ou de SDK n’a été modifiée.

`scripts/test-identity.sh` compile en Swift 6 avec concurrence stricte, crée une véritable ancienne base SQLite puis la rouvre avec le nouveau schéma. Il teste les accès concurrents au profil, les champs autorisés et l’import avec confirmation, le contexte remis au contrat Noctis, les succès/annulations/indisponibilités d’authentification, les résultats tardifs après verrouillage, le consentement iCloud, la conservation locale, les conflits, les suppressions, les reprises réseau, les changements de compte, les copies sans duplication et une modification locale pendant un envoi.

Les tests utilisent les protocoles réels du package Noctis et des doubles de transport et d’authentification. Ils ne téléchargent pas de modèle, n’ouvrent pas de session CloudKit et ne déclenchent pas de biométrie. Définir `NOCTIS_SOURCE_ROOT` vers le checkout du package NoctisAi si celui-ci n’est pas dans `../NoctisAi`. Les réglages `SWIFTC` et `NOCTIS_TEST_SDK` permettent de sélectionner la chaîne Xcode déjà installée. Le script actuel cible un Mac Apple Silicon.

Les validations de livraison et les limites de compilation sont précisées dans la PR. Une compilation sans signature ne valide ni l’accès iCloud réel ni Face ID matériel.

## Configuration et validation Apple restantes

1. Dans l’équipe Apple Developer propriétaire de l’app, enregistrer/associer le conteneur `iCloud.com.sebastiendaguin.NoctisAi` aux identifiants d’application iOS et macOS. Vérifier que cet identifiant est disponible ; si l’équipe en possède un autre, mettre à jour ensemble l’entitlement et la constante du transport.
2. Activer iCloud/CloudKit dans Signing & Capabilities pour les cibles concernées, conserver les autres capacités, puis régénérer les profils de provisionnement. Les entitlements et la description Face ID localisée FR/EN sont préparés dans le dépôt ; l’association serveur ne peut pas être faite par un changement de code.
3. Exécuter une app signée avec un compte de test dans l’environnement CloudKit Development. Vérifier les zones et le schéma privé : `NoctisDocument.document` (Asset) et `NoctisControl.generation` (String). Le transport n’utilise pas de requête par prédicat nécessitant un index métier. Déployer le schéma en Production dans CloudKit Console avant TestFlight/distribution.
4. Tester sur iPhone physique Face ID, Touch ID si disponible, secours par code, annulation, retour arrière-plan, sélecteur d’applications et lancement verrouillé sans chargement du modèle. Tester également Touch ID/mot de passe sur Mac et les fenêtres multiples.
5. Avec deux appareils du même compte : activation/désactivation, mode avion puis reprise, changements simultanés de profil et messages, suppression d’un fil, suppression distante pendant que l’autre appareil est hors ligne, réactivation explicite et interruption d’un envoi. Vérifier aussi compte absent, quota plein, compte différent et absence de fusion automatique.
6. Vérifier une mise à jour signée par-dessus une installation réelle contenant des conversations, avec sauvegarde préalable, ainsi que les protections de fichiers sur appareil. Contrôler les écrans et leurs libellés en français et en anglais.
