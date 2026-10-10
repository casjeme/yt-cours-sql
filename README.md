# yt-cours-sql

Fichiers en lien avec la série YouTube **« SQL avec SQL Server : de débutant à expert »**.

- 📋 La série complète : [playlist YouTube](https://www.youtube.com/playlist?list=PLznEpxSFntoAPkhgNkEWfcI7x5H16v81n)
- 🎬 Vidéo 19, l'atelier pratique : [Atelier SQL Server : une vraie base de A à Z](https://www.youtube.com/watch?v=gyqqnpTlVFY)

---

## Vidéo 19 : atelier pratique, la boutique de A à Z

Pas de slides dans cette vidéo : on ouvre SSMS et on construit une vraie base de données, du début à la fin, en réutilisant tout ce qu'on a vu dans la série.

Le fil rouge, c'est une **boutique en ligne** : des produits, des clients partout en France, des commandes. Avec un cahier des charges réaliste :

- une future **API** doit se brancher sur la base, avec juste les droits nécessaires ;
- un client supprimé n'est pas détruit tout de suite : on garde une trace pendant trois mois ;
- **RGPD** : les clients inactifs depuis plus de trois ans sont archivés, puis supprimés définitivement ;
- les clients doivent pouvoir s'afficher sur une **carte** ;
- un **référentiel d'adresses** (les 26 millions d'adresses françaises) sert à vérifier ce que l'API enverra ;
- chaque **commercial** ne voit que les clients de ses départements ;
- et tout ça doit être sauvegardé, performant et maintenu automatiquement.

Les scripts de ce dépôt sont exactement ceux de la vidéo. Le mieux, c'est de regarder la vidéo et de refaire l'atelier de votre côté, clavier sous les doigts.

### Prérequis

- **SQL Server 2022 ou plus récent** (l'atelier a été tourné sur SQL Server 2025). Le jeu d'essai utilise `GENERATE_SERIES` et `GREATEST`.
- Une édition **Developer**, Standard ou Enterprise : **SQL Server Agent n'existe pas dans l'édition Express**, et plusieurs chapitres créent des jobs. L'édition Developer est gratuite et complète.
- **SSMS** (SQL Server Management Studio).
- Pour le chapitre SSIS : **Visual Studio** avec l'extension *SQL Server Integration Services Projects*, et le catalogue **SSISDB** créé sur l'instance.
- De la place disque : la base Geo avec les 26 millions d'adresses pèse plusieurs Go, et le fichier de la BAN fait environ 1 Go compressé.

### Avant de lancer quoi que ce soit

Plusieurs scripts contiennent des **chemins à adapter à votre machine**. Les dossiers doivent exister et être accessibles au compte de service SQL Server :

| Script | Chemin à adapter | Rôle |
| --- | --- | --- |
| `01-creation-base.sql` | `D:\SQL_SERVER\SQLDATA\` et `D:\SQL_SERVER\SQLLOG\` | Fichiers de données et journal de transactions |
| `06-sauvegardes.sql` | `D:\SQLBACKUP\` | Dossier des sauvegardes |
| `10-geo-import-ban.sql` | `D:\SQL_SERVER\SQLDATA\` et `D:\SQL_SERVER\SQLLOG\` | Fichiers de la base Geo (les adresses) |

Les mots de passe présents dans les scripts sont des **exemples** (ils se terminent par `ChangezMoi`) : changez-les si vous utilisez autre chose qu'une machine de test.

### Les scripts, dans l'ordre

On exécute toujours **section par section** (on surligne, puis F5), comme dans la vidéo, jamais un script entier d'un coup. Seule exception : le jeu d'essai.

| # | Script | Chapitre de la vidéo | Ce qu'on fait |
| --- | --- | --- | --- |
| 01 | `01-creation-base.sql` | La base de données et ses fichiers | Création de la base `Boutique` : fichiers, groupes de fichiers, options |
| 02 | `02-tables.sql` | Les tables | Schémas et tables, sans contraintes |
| 03 | `03-contraintes.sql` | Les contraintes | Clés primaires, clés étrangères, CHECK, DEFAULT, unicité |
| 04 | `04-securite-api.sql` | Un compte pour la future API | Login, utilisateur et rôle avec juste les droits nécessaires |
| 05 | `05-jeu-essai.sql` | Le jeu d'essai : 300 000 clients | Génération des données côté serveur (voir ci-dessous) |
| 06 | `06-sauvegardes.sql` | Le plan de sauvegarde | Complète, différentielle et journal, planifiées avec SQL Server Agent |
| 07 | `07-suppression-logique.sql` | La suppression logique par trigger | Triggers `INSTEAD OF DELETE` : on marque au lieu de supprimer |
| 08 | `08-vue-recap-clients.sql` | La vue récapitulative et la carte des clients | Vue avec le chiffre d'affaires et la position `geography` de chaque client |
| 09 | `09-rgpd.sql` | L'épuration RGPD | Archivage puis purge définitive, en procédures et en jobs |
| 10 | `10-geo-import-ban.sql` | Importer 26 millions d'adresses | Base `Geo`, table de travail et intégration de la Base Adresse Nationale |
| 11 | `11-plans-execution-index.sql` | Plans d'exécution : avant et après les index | Scan, Seek, Key Lookup, index couvrant, pièges qui cassent un index |
| 12 | `12-maintenance-index.sql` | La maintenance des index | Procédure de réorganisation / reconstruction selon la fragmentation, avec journal |
| 13 | `13-ssis-integration-ban.sql` | Industrialiser l'import avec SSIS | Job SQL Server Agent qui lance le package déployé dans SSISDB |
| 14 | `14-droits-commerciaux.sql` | Chaque commercial ne voit que ses départements | Row-Level Security : fonction de filtre et stratégie de sécurité |
| 99 | `99-remise-a-zero.sql` | | Remise à zéro complète pour refaire l'atelier |

### Le jeu d'essai (script 05)

Le script ne contient pas des millions d'`INSERT` : il **génère** les données côté serveur à partir de vraies listes embarquées (régions, départements, environ 10 000 communes avec leur code postal, leurs coordonnées GPS et leur population). Les clients sont répartis au prorata de la population.

| Données | Volume par défaut |
| --- | --- |
| Produits | environ 2 000 |
| Clients | environ 300 000 |
| Commandes | environ 1,3 million |
| Lignes de commande | environ 2,7 millions |

Les volumes se règlent dans la section 0 du script. Comptez **1 à 3 minutes** selon la machine. À lancer **une seule fois**, juste après les scripts 01 à 04 (le script refuse de tourner si la base contient déjà des données).

Des profils de clients sont générés volontairement pour les démos : clients actifs, clients « dormants » sans commande depuis plus de trois ans, clients qui n'ont jamais commandé, clients déjà supprimés logiquement. Plus 6 clients « témoins » aux identifiants fixes (1 à 6), utilisés tout au long de la vidéo.

### L'import des adresses (scripts 10 et 13)

La **Base Adresse Nationale** est un fichier ouvert et gratuit qui contient toutes les adresses de France avec leurs coordonnées GPS :

- Téléchargement : <https://adresse.data.gouv.fr/data/ban/adresses/latest/csv/>, fichier `adresses-france.csv.gz`, à décompresser avant l'import.
- Format : séparateur `;`, noms de colonnes sur la première ligne, encodage UTF-8.

L'import se fait en deux temps : l'**assistant Import/Export** de SSMS charge le fichier brut dans la table de travail `dbo.BAN_Import`, puis la procédure `dbo.usp_IntegrerBAN` convertit et alimente la table propre `dbo.Adresse`.

Dans l'assistant, quelques réglages évitent les erreurs de troncature et de conversion :

- source « Fichier plat », qualificateur de texte `"`, largeur des colonnes à 1000 ;
- colonne `cad_parcelles` en type `DT_TEXT` ;
- destination avec le **Driver** OLE DB pour SQL Server (pas l'ancien Provider) ;
- enregistrer le package sous le nom `Import_BAN.dtsx` : il sert au chapitre SSIS.

Pour le chapitre SSIS, les étapes dans Visual Studio sont détaillées en tête du script `13-ssis-integration-ban.sql` : projet `IntegrationBAN`, paramètre de projet `CheminFichierBAN`, déploiement dans `/SSISDB/Geo`, puis le script crée le job qui l'exécute chaque mois.

### Ce que l'atelier crée sur votre instance

- Les bases **`Boutique`** et **`Geo`**.
- Le login **`api_boutique`**.
- Des jobs SQL Server Agent, tous préfixés par `Boutique -` ou `Geo -` : sauvegardes complète, différentielle et du journal, archivage et purge RGPD, maintenance des index, intégration de la BAN.

Le script **`99-remise-a-zero.sql`** supprime tout ça pour repartir de zéro. Il **ne supprime pas** les fichiers de sauvegarde, à effacer à la main si besoin.

### Si vous exécutez les scripts avec sqlcmd

SSMS active `QUOTED_IDENTIFIER` par défaut, mais pas `sqlcmd`. Or les index filtrés, les vues et la sécurité au niveau des lignes l'exigent. Ajoutez l'option **`-I`** :

```bash
sqlcmd -S localhost -E -I -i 01-creation-base.sql
```

---

## Pour aller plus loin

- [Base Adresse Nationale](https://adresse.data.gouv.fr/)
- [Documentation Row-Level Security](https://learn.microsoft.com/fr-fr/sql/relational-databases/security/row-level-security)
- [Documentation SESSION_CONTEXT](https://learn.microsoft.com/fr-fr/sql/t-sql/functions/session-context-transact-sql)
- [Solution de maintenance d'Ola Hallengren](https://ola.hallengren.com/), la référence en production pour les sauvegardes et la maintenance des index

Des questions ? Posez-les en commentaire sous la [vidéo](https://www.youtube.com/watch?v=gyqqnpTlVFY).
