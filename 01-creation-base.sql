/*==============================================================================
  VIDÉO 19 : ATELIER PRATIQUE, LA BOUTIQUE DE A À Z
  Script 01 : création de la base de données « Boutique »
  ------------------------------------------------------------------------------
  AVANT DE LANCER : adapter les chemins à votre machine.
    D:\SQL_SERVER\SQLDATA\   -> fichiers de données (.mdf / .ndf)
    D:\SQL_SERVER\SQLLOG\    -> journal de transactions (.ldf), idéalement sur un autre disque
  Les dossiers doivent exister et être accessibles au compte de service SQL Server.
==============================================================================*/
USE master;
GO

/*------------------------------------------------------------------------------
  1. La base et ses fichiers
  - PRIMARY ne contient que les objets système (petit fichier).
  - FG_DONNEES reçoit nos tables : on le déclare filegroup PAR DÉFAUT juste après.
    Deux fichiers dans ce filegroup : SQL Server répartit les écritures entre eux.
  - Le journal est à part, sur son propre disque.
  - Tailles initiales confortables et croissance en Mo (jamais en %) pour éviter
    des dizaines de petites extensions pendant le chargement des données.
  - Collation française, insensible à la casse et sensible aux accents.
------------------------------------------------------------------------------*/
CREATE DATABASE Boutique
ON PRIMARY
(
    NAME       = N'Boutique_primary',
    FILENAME   = N'D:\SQL_SERVER\SQLDATA\Boutique_primary.mdf',
    SIZE       = 64MB,
    FILEGROWTH = 64MB
),
FILEGROUP FG_DONNEES
(
    NAME       = N'Boutique_donnees_1',
    FILENAME   = N'D:\SQL_SERVER\SQLDATA\Boutique_donnees_1.ndf',
    SIZE       = 1GB,
    FILEGROWTH = 256MB
),
(
    NAME       = N'Boutique_donnees_2',
    FILENAME   = N'D:\SQL_SERVER\SQLDATA\Boutique_donnees_2.ndf',
    SIZE       = 1GB,
    FILEGROWTH = 256MB
)
LOG ON
(
    NAME       = N'Boutique_log',
    FILENAME   = N'D:\SQL_SERVER\SQLLOG\Boutique_log.ldf',
    SIZE       = 1GB,
    FILEGROWTH = 512MB
)
COLLATE French_100_CI_AS;
GO

/*------------------------------------------------------------------------------
  2. Le filegroup par défaut : toute table créée sans préciser « ON ... »
     ira dans FG_DONNEES, et pas dans PRIMARY.
------------------------------------------------------------------------------*/
ALTER DATABASE Boutique MODIFY FILEGROUP FG_DONNEES DEFAULT;
GO

/*------------------------------------------------------------------------------
  3. Les options importantes
------------------------------------------------------------------------------*/
-- Récupération COMPLÈTE : indispensable pour sauvegarder le journal (chapitre sauvegardes).
ALTER DATABASE Boutique SET RECOVERY FULL;

-- Jamais d'arrêt automatique ni de réduction automatique des fichiers.
ALTER DATABASE Boutique SET AUTO_CLOSE OFF;
ALTER DATABASE Boutique SET AUTO_SHRINK OFF;

-- Statistiques automatiques (mises à jour en arrière-plan pour ne pas bloquer les requêtes).
ALTER DATABASE Boutique SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE Boutique SET AUTO_UPDATE_STATISTICS ON;
ALTER DATABASE Boutique SET AUTO_UPDATE_STATISTICS_ASYNC ON;

-- Détection des pages corrompues.
ALTER DATABASE Boutique SET PAGE_VERIFY CHECKSUM;

-- Les lecteurs ne bloquent plus les écrivains (versionnement des lignes) :
-- confortable pour une base qui sera attaquée par une API.
ALTER DATABASE Boutique SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;

-- Query Store : l'historique des plans d'exécution (utile au chapitre performances).
ALTER DATABASE Boutique SET QUERY_STORE = ON;

-- Le propriétaire de la base : sa (et pas le compte Windows de celui qui l'a créée).
ALTER AUTHORIZATION ON DATABASE::Boutique TO sa;
GO

/*------------------------------------------------------------------------------
  4. Vérification
------------------------------------------------------------------------------*/
SELECT  name, recovery_model_desc, collation_name,
        is_read_committed_snapshot_on, compatibility_level
FROM    sys.databases
WHERE   name = N'Boutique';

SELECT  f.name AS Fichier, f.physical_name, fg.name AS Filegroup,
        f.size * 8 / 1024 AS TailleMo, fg.is_default
FROM        Boutique.sys.database_files f
LEFT JOIN   Boutique.sys.filegroups     fg ON fg.data_space_id = f.data_space_id;
GO
