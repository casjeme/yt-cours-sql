/*==============================================================================
  VIDÉO 19 : ATELIER PRATIQUE, LA BOUTIQUE DE A À Z
  Script 02 : schémas et tables (SANS contraintes)
==============================================================================*/
USE Boutique;
GO

/*------------------------------------------------------------------------------
  Les schémas : on range les objets par thème, comme des dossiers.
    ref    : référentiels (régions, départements)
    ventes : le cœur métier (catalogue, clients, commandes)
    admin  : nos outils d'administration (sauvegarde, maintenance)
------------------------------------------------------------------------------*/
CREATE SCHEMA ref    AUTHORIZATION dbo;
GO
CREATE SCHEMA ventes AUTHORIZATION dbo;
GO
CREATE SCHEMA admin  AUTHORIZATION dbo;
GO

/*------------------------------------------------------------------------------
  Référentiels géographiques
------------------------------------------------------------------------------*/
CREATE TABLE ref.Region
(
    CodeRegion        CHAR(2)        NOT NULL,
    Nom               NVARCHAR(60)   NOT NULL
);

CREATE TABLE ref.Departement
(
    CodeDepartement   VARCHAR(3)     NOT NULL,   -- '79', '2A', '971'...
    Nom               NVARCHAR(60)   NOT NULL,
    CodeRegion        CHAR(2)        NOT NULL
);
GO

/*------------------------------------------------------------------------------
  Catalogue
------------------------------------------------------------------------------*/
CREATE TABLE ventes.Categorie
(
    IdCategorie       INT            IDENTITY(1,1) NOT NULL,
    Libelle           NVARCHAR(60)   NOT NULL
);

CREATE TABLE ventes.Produit
(
    IdProduit         INT            IDENTITY(1,1) NOT NULL,
    Reference         VARCHAR(20)    NOT NULL,
    Nom               NVARCHAR(150)  NOT NULL,
    IdCategorie       INT            NOT NULL,
    PrixHT            DECIMAL(10,2)  NOT NULL,
    TauxTVA           DECIMAL(4,2)   NOT NULL,
    Stock             INT            NOT NULL,
    Actif             BIT            NOT NULL,
    DateCreation      DATETIME2(0)   NOT NULL
);
GO

/*------------------------------------------------------------------------------
  Clients
  - Latitude / Longitude : position du client (affichage sur une carte).
  - Suppression : NULL = client actif ; une date = client supprimé LOGIQUEMENT
    (on ne détruit pas la ligne tout de suite, voir le chapitre des triggers).
------------------------------------------------------------------------------*/
CREATE TABLE ventes.Client
(
    IdClient          INT            IDENTITY(1,1) NOT NULL,
    Nom               NVARCHAR(80)   NOT NULL,
    Prenom            NVARCHAR(80)   NOT NULL,
    Email             NVARCHAR(160)  NOT NULL,
    Telephone         VARCHAR(20)    NULL,
    Adresse           NVARCHAR(200)  NOT NULL,
    CodePostal        CHAR(5)        NOT NULL,
    Ville             NVARCHAR(100)  NOT NULL,
    CodeDepartement   VARCHAR(3)     NOT NULL,
    Latitude          DECIMAL(9,6)   NULL,
    Longitude         DECIMAL(9,6)   NULL,
    DateCreation      DATETIME2(0)   NOT NULL,
    Suppression       DATETIME2(0)   NULL
);
GO

/*------------------------------------------------------------------------------
  Commandes et lignes de commande
  - La ligne de commande recopie le prix et la TVA AU MOMENT de la commande :
    si le prix du produit change demain, la facture d'hier ne bouge pas.
------------------------------------------------------------------------------*/
CREATE TABLE ventes.Commande
(
    IdCommande        INT            IDENTITY(1,1) NOT NULL,
    IdClient          INT            NOT NULL,
    DateCommande      DATETIME2(0)   NOT NULL,
    Statut            VARCHAR(12)    NOT NULL,
    Suppression       DATETIME2(0)   NULL
);

CREATE TABLE ventes.LigneCommande
(
    IdCommande        INT            NOT NULL,
    NumeroLigne       SMALLINT       NOT NULL,
    IdProduit         INT            NOT NULL,
    Quantite          INT            NOT NULL,
    PrixUnitaireHT    DECIMAL(10,2)  NOT NULL,
    TauxTVA           DECIMAL(4,2)   NOT NULL
);
GO

-- Vérification : nos tables, rangées par schéma.
SELECT  s.name AS Schema_, t.name AS Table_
FROM        sys.tables  t
INNER JOIN  sys.schemas s ON s.schema_id = t.schema_id
ORDER BY s.name, t.name;
GO
