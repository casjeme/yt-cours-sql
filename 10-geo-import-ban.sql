/*==============================================================================
  VIDÉO 19 : ATELIER PRATIQUE, LA BOUTIQUE DE A À Z
  Script 10 : la base Geo et l'import du fichier des adresses françaises (BAN)
  ------------------------------------------------------------------------------
  La Base Adresse Nationale (BAN) est un fichier ouvert et gratuit qui contient
  TOUTES les adresses de France avec leurs coordonnées GPS : environ 26 millions
  de lignes. Il servira de référentiel pour vérifier et géolocaliser les
  adresses saisies par la future API.

  Fichier : https://adresse.data.gouv.fr/data/ban/adresses/latest/csv/
            adresses-france.csv.gz (~1 Go compressé, à décompresser avant l'import)
  Format  : séparateur « ; », première ligne = noms de colonnes, encodage UTF-8.

  Démarche en deux temps (on la retrouvera à l'identique avec SSIS) :
    1. on charge le fichier BRUT dans une table de travail (tout en texte),
    2. une procédure convertit et alimente la table propre dbo.Adresse.
  Rappels : vidéo 16 (assistant Import/Export), vidéo 03 (création de base).
==============================================================================*/
USE master;
GO

/*------------------------------------------------------------------------------
  1. La base Geo
  C'est un référentiel qu'on recharge entièrement depuis le fichier : inutile de
  sauvegarder le journal, on passe en récupération SIMPLE.
------------------------------------------------------------------------------*/
CREATE DATABASE Geo
ON PRIMARY
(
    NAME = N'Geo_data', FILENAME = N'D:\SQL_SERVER\SQLDATA\Geo_data.mdf',
    SIZE = 8GB, FILEGROWTH = 1GB
)
LOG ON
(
    NAME = N'Geo_log',  FILENAME = N'D:\SQL_SERVER\SQLLOG\Geo_log.ldf',
    SIZE = 2GB, FILEGROWTH = 1GB
)
COLLATE French_100_CI_AS;
GO
ALTER DATABASE Geo SET RECOVERY SIMPLE;
ALTER AUTHORIZATION ON DATABASE::Geo TO sa;
GO

USE Geo;
GO

/*------------------------------------------------------------------------------
  2. La table de travail : le fichier tel quel
  Les colonnes portent EXACTEMENT les noms de l'en-tête du fichier : l'assistant
  fera la correspondance tout seul. Tout est en texte, et LARGE (1000 caractères,
  MAX pour les parcelles) : la même largeur que dans l'assistant, pour qu'aucune
  conversion ne puisse échouer pendant l'import. On typera proprement ensuite.
------------------------------------------------------------------------------*/
CREATE TABLE dbo.BAN_Import
(
    id                          NVARCHAR(100) NULL,
    id_fantoir                  NVARCHAR(50) NULL,
    numero                      NVARCHAR(20) NULL,
    rep                         NVARCHAR(20) NULL,
    nom_voie                    NVARCHAR(200) NULL,
    code_postal                 NVARCHAR(50) NULL,
    code_insee                  NVARCHAR(5) NULL,
    nom_commune                 NVARCHAR(200) NULL,
    code_insee_ancienne_commune NVARCHAR(5) NULL,
    nom_ancienne_commune        NVARCHAR(200) NULL,
    x                           NVARCHAR(15) NULL,
    y                           NVARCHAR(15) NULL,
    lon                         NVARCHAR(15) NULL,
    lat                         NVARCHAR(15) NULL,
    type_position               NVARCHAR(30) NULL,
    alias                       NVARCHAR(100) NULL,
    nom_ld                      NVARCHAR(1000) NULL,
    libelle_acheminement        NVARCHAR(50) NULL,
    nom_afnor                   NVARCHAR(50) NULL,
    source_position             NVARCHAR(50) NULL,
    source_nom_voie             NVARCHAR(50) NULL
);
GO

/*------------------------------------------------------------------------------
  3. La table propre : ce qui nous intéresse, correctement typé.
  Volontairement SANS AUCUN INDEX pour l'instant (pas même de clé primaire) :
  c'est ce qui rendra la démo des plans d'exécution parlante.
------------------------------------------------------------------------------*/
CREATE TABLE dbo.Adresse
(
    IdBAN        VARCHAR(60)    NOT NULL,
    Numero       INT            NULL,
    Repetition   NVARCHAR(20)   NULL,       -- bis, ter...
    NomVoie      NVARCHAR(200)  NOT NULL,
    CodePostal   CHAR(5)        NOT NULL,
    CodeInsee    CHAR(5)        NOT NULL,
    NomCommune   NVARCHAR(100)  NOT NULL,
    Latitude     DECIMAL(9,6)   NOT NULL,
    Longitude    DECIMAL(9,6)   NOT NULL
);
GO

/*------------------------------------------------------------------------------
  4. La procédure d'intégration : du brut vers le propre
  - TRY_CAST : si une valeur n'est pas convertible, on obtient NULL au lieu
    d'une erreur qui ferait échouer les 26 millions de lignes.
  - Les coordonnées du fichier utilisent le point décimal : CAST les lit
    correctement quelle que soit la langue du serveur.
  - Le fichier BAN est un export COMPLET : on recharge tout à chaque fois.
------------------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE dbo.usp_IntegrerBAN
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NbBrut BIGINT = (SELECT COUNT_BIG(*) FROM dbo.BAN_Import);
    IF @NbBrut = 0
        THROW 50000, N'La table BAN_Import est vide : importez d''abord le fichier.', 1;

    BEGIN TRANSACTION;

        TRUNCATE TABLE dbo.Adresse;

        -- Charger 26 millions de lignes dans une table déjà indexée est lent :
        -- on désactive les index (s'il y en a), on les reconstruira d'un coup à la fin.
        IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Adresse') AND index_id > 1)
            ALTER INDEX ALL ON dbo.Adresse DISABLE;

        INSERT INTO dbo.Adresse WITH (TABLOCK)
               (IdBAN, Numero, Repetition, NomVoie, CodePostal, CodeInsee, NomCommune, Latitude, Longitude)
        SELECT  id,
                TRY_CAST(numero AS INT),
                NULLIF(rep, N''),
                nom_voie,
                code_postal,
                code_insee,
                nom_commune,
                TRY_CAST(lat AS DECIMAL(9,6)),
                TRY_CAST(lon AS DECIMAL(9,6))
        FROM    dbo.BAN_Import
        WHERE   id IS NOT NULL
          AND   nom_voie IS NOT NULL
          AND   LEN(code_postal) = 5
          AND   TRY_CAST(lat AS DECIMAL(9,6)) IS NOT NULL
          AND   TRY_CAST(lon AS DECIMAL(9,6)) IS NOT NULL;

        IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Adresse') AND index_id > 1)
            ALTER INDEX ALL ON dbo.Adresse REBUILD;

    COMMIT TRANSACTION;

    SELECT  @NbBrut                                   AS LignesFichier,
            (SELECT COUNT_BIG(*) FROM dbo.Adresse)    AS AdressesIntegrees;
END;
GO

/*==============================================================================
  5. L'IMPORT DU FICHIER : DÉMO À LA SOURIS (assistant Import/Export)
  ------------------------------------------------------------------------------
  Clic droit sur la base Geo > Tâches > Importer des données...
    Source       : « Source de fichier plat »
                   Fichier : adresses-france.csv
                   Page de codes : 65001 (UTF-8)
                   Délimiteur de colonne : point-virgule
                   Qualificateur de texte : "  (guillemet droit : quelques
                   valeurs contiennent un point-virgule entre guillemets)
                   « Noms de colonnes dans la première ligne de données » : coché
                   Onglet Avancé : par défaut, chaque colonne fait 50 caractères,
                   beaucoup trop peu pour un vrai fichier. Mesures sur la BAN
                   complète (26 millions de lignes) :
                     nom_voie 90, nom_ld 569 (!), cad_parcelles 9 449 (!)
                   => sélectionner toutes les colonnes : OutputColumnWidth = 1000
                   => cad_parcelles seule : DataType = flux de texte [DT_TEXT]
                      (au-delà de 8 000 caractères, une chaîne classique ne suffit plus)
    Destination  : « Microsoft OLE DB Driver for SQL Server », base Geo
                   ATTENTION : « Driver », pas « Provider » (l'ancien pilote ne
                   sait pas se connecter à SQL Server 2025). Si erreur de certificat :
                   Propriétés > « Faire confiance au certificat du serveur ».
    Table        : [dbo].[BAN_Import]  (les colonnes se mappent toutes seules)
    Page « Vérifier le mappage des types de données » : par sécurité,
                   « En cas d'erreur » et « En cas de troncation » = Ignorer
                   (la procédure d'intégration écarte de toute façon les lignes
                   inexploitables).
    Dernière page: cocher « Exécuter immédiatement » ET « Enregistrer le package
                   SSIS » (système de fichiers) -> Import_BAN.dtsx
                   On le réutilisera dans Visual Studio au chapitre SSIS.
  Durée : de 10 à 30 minutes pour la France entière selon la machine.
==============================================================================*/

/*------------------------------------------------------------------------------
  6. Après l'import : contrôle puis intégration
------------------------------------------------------------------------------*/
SELECT COUNT_BIG(*) AS LignesImportees FROM dbo.BAN_Import;
SELECT TOP (5) * FROM dbo.BAN_Import;

EXEC dbo.usp_IntegrerBAN;

-- Combien d'adresses par département (les 10 plus gros) ?
SELECT TOP (10) LEFT(CodeInsee, 2) AS Departement, COUNT_BIG(*) AS NbAdresses
FROM   dbo.Adresse
GROUP BY LEFT(CodeInsee, 2)
ORDER BY NbAdresses DESC;
GO

-- La table de travail a joué son rôle : on la vide pour récupérer la place.
TRUNCATE TABLE dbo.BAN_Import;
GO
