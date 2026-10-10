/*==============================================================================
  VIDÉO 19 : ATELIER PRATIQUE, LA BOUTIQUE DE A À Z
  Script 03 : les contraintes
==============================================================================*/
USE Boutique;
GO

/*==============================================================================
  1. CLÉS PRIMAIRES
  Par défaut, une clé primaire crée un index CLUSTER : les lignes sont
  physiquement rangées dans l'ordre de la clé.
==============================================================================*/
ALTER TABLE ref.Region          ADD CONSTRAINT PK_Region        PRIMARY KEY (CodeRegion);
ALTER TABLE ref.Departement     ADD CONSTRAINT PK_Departement   PRIMARY KEY (CodeDepartement);
ALTER TABLE ventes.Categorie    ADD CONSTRAINT PK_Categorie     PRIMARY KEY (IdCategorie);
ALTER TABLE ventes.Produit      ADD CONSTRAINT PK_Produit       PRIMARY KEY (IdProduit);
ALTER TABLE ventes.Client       ADD CONSTRAINT PK_Client        PRIMARY KEY (IdClient);
ALTER TABLE ventes.Commande     ADD CONSTRAINT PK_Commande      PRIMARY KEY (IdCommande);
-- Clé composée : une ligne est identifiée par sa commande ET son numéro de ligne.
ALTER TABLE ventes.LigneCommande ADD CONSTRAINT PK_LigneCommande PRIMARY KEY (IdCommande, NumeroLigne);
GO

/*==============================================================================
  2. CLÉS ÉTRANGÈRES
  Elles garantissent qu'on ne peut pas avoir une commande sans client, une ligne
  sans produit, etc. ATTENTION : SQL Server ne crée PAS d'index sur une clé
  étrangère. On y reviendra au chapitre des plans d'exécution...
==============================================================================*/
ALTER TABLE ref.Departement ADD CONSTRAINT FK_Departement_Region
    FOREIGN KEY (CodeRegion) REFERENCES ref.Region (CodeRegion);

ALTER TABLE ventes.Produit ADD CONSTRAINT FK_Produit_Categorie
    FOREIGN KEY (IdCategorie) REFERENCES ventes.Categorie (IdCategorie);

ALTER TABLE ventes.Client ADD CONSTRAINT FK_Client_Departement
    FOREIGN KEY (CodeDepartement) REFERENCES ref.Departement (CodeDepartement);

ALTER TABLE ventes.Commande ADD CONSTRAINT FK_Commande_Client
    FOREIGN KEY (IdClient) REFERENCES ventes.Client (IdClient);

ALTER TABLE ventes.LigneCommande ADD CONSTRAINT FK_LigneCommande_Commande
    FOREIGN KEY (IdCommande) REFERENCES ventes.Commande (IdCommande);

ALTER TABLE ventes.LigneCommande ADD CONSTRAINT FK_LigneCommande_Produit
    FOREIGN KEY (IdProduit) REFERENCES ventes.Produit (IdProduit);
GO

/*==============================================================================
  3. VALEURS PAR DÉFAUT
  Ce que SQL Server met dans la colonne si l'INSERT ne la précise pas.
==============================================================================*/
ALTER TABLE ventes.Produit  ADD CONSTRAINT DF_Produit_TauxTVA      DEFAULT (20.00)          FOR TauxTVA;
ALTER TABLE ventes.Produit  ADD CONSTRAINT DF_Produit_Stock        DEFAULT (0)              FOR Stock;
ALTER TABLE ventes.Produit  ADD CONSTRAINT DF_Produit_Actif        DEFAULT (1)              FOR Actif;
ALTER TABLE ventes.Produit  ADD CONSTRAINT DF_Produit_DateCreation DEFAULT (SYSDATETIME())  FOR DateCreation;

ALTER TABLE ventes.Client   ADD CONSTRAINT DF_Client_DateCreation  DEFAULT (SYSDATETIME())  FOR DateCreation;

ALTER TABLE ventes.Commande ADD CONSTRAINT DF_Commande_Date        DEFAULT (SYSDATETIME())  FOR DateCommande;
ALTER TABLE ventes.Commande ADD CONSTRAINT DF_Commande_Statut      DEFAULT ('EN_ATTENTE')   FOR Statut;

ALTER TABLE ventes.LigneCommande ADD CONSTRAINT DF_Ligne_Quantite  DEFAULT (1)              FOR Quantite;
GO

/*==============================================================================
  4. UNICITÉ
==============================================================================*/
ALTER TABLE ventes.Categorie ADD CONSTRAINT UQ_Categorie_Libelle UNIQUE (Libelle);
ALTER TABLE ventes.Produit   ADD CONSTRAINT UQ_Produit_Reference UNIQUE (Reference);

-- Cas particulier de l'email client : avec la suppression logique, un client
-- supprimé garde sa ligne (et son email) pendant quelques mois. S'il revient
-- s'inscrire, une contrainte UNIQUE classique le bloquerait.
-- Solution : un index UNIQUE FILTRÉ, qui ne vérifie l'unicité que sur les
-- clients actifs (Suppression IS NULL).
CREATE UNIQUE INDEX UX_Client_Email_Actif
    ON ventes.Client (Email)
    WHERE Suppression IS NULL;
GO

/*==============================================================================
  5. CONTRÔLES (CHECK)
==============================================================================*/
-- Catalogue
ALTER TABLE ventes.Produit ADD CONSTRAINT CK_Produit_Prix   CHECK (PrixHT > 0);
ALTER TABLE ventes.Produit ADD CONSTRAINT CK_Produit_TVA    CHECK (TauxTVA IN (0.00, 2.10, 5.50, 10.00, 20.00));
ALTER TABLE ventes.Produit ADD CONSTRAINT CK_Produit_Stock  CHECK (Stock >= 0);

-- Clients
ALTER TABLE ventes.Client ADD CONSTRAINT CK_Client_CodePostal
    CHECK (CodePostal LIKE '[0-9][0-9][0-9][0-9][0-9]');
ALTER TABLE ventes.Client ADD CONSTRAINT CK_Client_Email
    CHECK (Email LIKE '%_@_%._%' AND Email NOT LIKE '% %');
ALTER TABLE ventes.Client ADD CONSTRAINT CK_Client_Position
    CHECK (    (Latitude IS NULL AND Longitude IS NULL)
            OR (Latitude BETWEEN -90 AND 90 AND Longitude BETWEEN -180 AND 180));
ALTER TABLE ventes.Client ADD CONSTRAINT CK_Client_Suppression
    CHECK (Suppression IS NULL OR Suppression >= DateCreation);

-- Commandes
ALTER TABLE ventes.Commande ADD CONSTRAINT CK_Commande_Statut
    CHECK (Statut IN ('EN_ATTENTE', 'PAYEE', 'EXPEDIEE', 'LIVREE', 'ANNULEE'));

-- Lignes
ALTER TABLE ventes.LigneCommande ADD CONSTRAINT CK_Ligne_Quantite CHECK (Quantite > 0);
ALTER TABLE ventes.LigneCommande ADD CONSTRAINT CK_Ligne_Prix     CHECK (PrixUnitaireHT > 0);
ALTER TABLE ventes.LigneCommande ADD CONSTRAINT CK_Ligne_TVA      CHECK (TauxTVA IN (0.00, 2.10, 5.50, 10.00, 20.00));
GO

/*==============================================================================
  6. Vérification : toutes les contraintes de la base, par table
==============================================================================*/
SELECT  OBJECT_SCHEMA_NAME(parent_object_id) + '.' + OBJECT_NAME(parent_object_id) AS Table_,
        type_desc  AS TypeContrainte,
        name       AS Contrainte
FROM    sys.objects
WHERE   type IN ('PK', 'F', 'D', 'UQ', 'C')
ORDER BY Table_, type_desc, name;
GO
