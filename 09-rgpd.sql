/*==============================================================================
  VIDÉO 19 : ATELIER PRATIQUE, LA BOUTIQUE DE A À Z
  Script 09 : l'épuration RGPD
  ------------------------------------------------------------------------------
  Règles métier :
    1. Un client sans commande depuis plus de 3 ans (ou inscrit depuis plus de
       3 ans sans jamais avoir commandé) est ARCHIVÉ : on le déplace, avec ses
       commandes, dans un schéma « rgpd » à part, invisible pour l'API.
    2. Trois mois après son archivage, il est SUPPRIMÉ DÉFINITIVEMENT.
    3. Un client supprimé logiquement depuis plus de 3 mois est lui aussi
       supprimé définitivement, avec ses commandes.
  Rappels : vidéo 10 (procédures, TRY/CATCH), vidéo 05 (transactions),
            vidéo 18 (jobs planifiés).
==============================================================================*/
USE Boutique;
GO

/*==============================================================================
  1. LE SCHÉMA D'ARCHIVAGE ET SES TABLES
  Mêmes colonnes que les tables d'origine + la date d'archivage.
  Ici, pas de trigger : on peut utiliser ON DELETE CASCADE, supprimer un client
  archivé supprimera automatiquement ses commandes et ses lignes.
==============================================================================*/
CREATE SCHEMA rgpd AUTHORIZATION dbo;
GO

CREATE TABLE rgpd.Client
(
    IdClient          INT            NOT NULL,
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
    DateArchivage     DATETIME2(0)   NOT NULL,
    CONSTRAINT PK_rgpd_Client PRIMARY KEY (IdClient)
);

CREATE TABLE rgpd.Commande
(
    IdCommande        INT            NOT NULL,
    IdClient          INT            NOT NULL,
    DateCommande      DATETIME2(0)   NOT NULL,
    Statut            VARCHAR(12)    NOT NULL,
    CONSTRAINT PK_rgpd_Commande PRIMARY KEY (IdCommande),
    CONSTRAINT FK_rgpd_Commande_Client FOREIGN KEY (IdClient)
        REFERENCES rgpd.Client (IdClient) ON DELETE CASCADE
);

CREATE TABLE rgpd.LigneCommande
(
    IdCommande        INT            NOT NULL,
    NumeroLigne       SMALLINT       NOT NULL,
    IdProduit         INT            NOT NULL,
    Quantite          INT            NOT NULL,
    PrixUnitaireHT    DECIMAL(10,2)  NOT NULL,
    TauxTVA           DECIMAL(4,2)   NOT NULL,
    CONSTRAINT PK_rgpd_LigneCommande PRIMARY KEY (IdCommande, NumeroLigne),
    CONSTRAINT FK_rgpd_Ligne_Commande FOREIGN KEY (IdCommande)
        REFERENCES rgpd.Commande (IdCommande) ON DELETE CASCADE
);

CREATE INDEX IX_rgpd_Commande_Client ON rgpd.Commande (IdClient);
GO

/*==============================================================================
  2. LE PROBLÈME : nos triggers interceptent TOUS les DELETE...
  Pour déplacer un client, il faut bien le supprimer de ventes.Client. Mais le
  trigger INSTEAD OF va transformer ce DELETE en simple date de suppression !
==============================================================================*/
BEGIN TRANSACTION;
    DELETE FROM ventes.Client WHERE IdClient = 3;
    SELECT IdClient, Nom, Suppression FROM ventes.Client WHERE IdClient = 3;  -- toujours là !
ROLLBACK TRANSACTION;
GO

/*==============================================================================
  3. LA SOLUTION : un « mode purge » dans les triggers, grâce à SESSION_CONTEXT
  SESSION_CONTEXT est un petit dictionnaire clé / valeur attaché à la connexion.
  Nos procédures RGPD y posent PurgePhysique = 1 ; les triggers le lisent et,
  dans ce cas, font un vrai DELETE.
  Sécurité : le mode purge n'est accepté que pour un membre de db_owner (les
  jobs de l'Agent). L'API pourrait poser la clé, elle ne serait pas écoutée.
==============================================================================*/
CREATE OR ALTER TRIGGER ventes.trg_Commande_SuppressionLogique
ON ventes.Commande
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF CAST(SESSION_CONTEXT(N'PurgePhysique') AS INT) = 1
       AND IS_ROLEMEMBER(N'db_owner') = 1
    BEGIN
        -- Mode purge : suppression PHYSIQUE, des lignes puis des commandes.
        DELETE l
        FROM        ventes.LigneCommande l
        INNER JOIN  deleted              d ON d.IdCommande = l.IdCommande;

        DELETE cm
        FROM        ventes.Commande cm
        INNER JOIN  deleted         d ON d.IdCommande = cm.IdCommande;
        RETURN;
    END

    -- Mode normal : suppression LOGIQUE.
    UPDATE cm
    SET    cm.Suppression = SYSDATETIME()
    FROM        ventes.Commande cm
    INNER JOIN  deleted         d ON d.IdCommande = cm.IdCommande
    WHERE   cm.Suppression IS NULL;
END;
GO

CREATE OR ALTER TRIGGER ventes.trg_Client_SuppressionLogique
ON ventes.Client
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF CAST(SESSION_CONTEXT(N'PurgePhysique') AS INT) = 1
       AND IS_ROLEMEMBER(N'db_owner') = 1
    BEGIN
        -- Mode purge : on supprime les commandes (le trigger des commandes,
        -- lui aussi en mode purge, supprimera leurs lignes), puis le client.
        DELETE cm
        FROM        ventes.Commande cm
        INNER JOIN  deleted         d ON d.IdClient = cm.IdClient;

        DELETE c
        FROM        ventes.Client c
        INNER JOIN  deleted       d ON d.IdClient = c.IdClient;
        RETURN;
    END

    -- Mode normal : suppression LOGIQUE du client et de ses commandes.
    DECLARE @Maintenant DATETIME2(0) = SYSDATETIME();

    UPDATE cm
    SET    cm.Suppression = @Maintenant
    FROM        ventes.Commande cm
    INNER JOIN  deleted         d ON d.IdClient = cm.IdClient
    WHERE   cm.Suppression IS NULL;

    UPDATE c
    SET    c.Suppression = @Maintenant
    FROM        ventes.Client c
    INNER JOIN  deleted       d ON d.IdClient = c.IdClient
    WHERE   c.Suppression IS NULL;
END;
GO

/*==============================================================================
  4. UN INDEX INDISPENSABLE AVANT D'ALLER PLUS LOIN
  Supprimer un client, c'est vérifier qu'aucune commande ne le référence plus
  (clé étrangère FK_Commande_Client). Souvenez-vous : SQL Server n'indexe pas
  les clés étrangères. Sans index sur Commande.IdClient, il relit 1,3 million
  de commandes... POUR CHAQUE client supprimé. Avec des dizaines de milliers de
  clients à archiver, la procédure tournerait pendant des heures.
  Bonus : la recherche « pas de commande depuis 3 ans » utilise aussi cet index.
==============================================================================*/
CREATE INDEX IX_Commande_Client_Date
    ON ventes.Commande (IdClient, DateCommande);
GO

/*==============================================================================
  5. PROCÉDURE N°1 : ARCHIVER LES CLIENTS INACTIFS
  @DateReference permet de simuler une autre date (utile pour les tests).
==============================================================================*/
CREATE OR ALTER PROCEDURE rgpd.usp_ArchiverClientsInactifs
    @DateReference  DATETIME2(0) = NULL,     -- par défaut : maintenant
    @MoisInactivite INT          = 36
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @DateReference = ISNULL(@DateReference, SYSDATETIME());
    DECLARE @Limite DATETIME2(0) = DATEADD(MONTH, -@MoisInactivite, @DateReference);

    -- 1. Les candidats : actifs, inscrits avant la limite, aucune commande depuis.
    DROP TABLE IF EXISTS #Candidat;
    SELECT  c.IdClient
    INTO    #Candidat
    FROM    ventes.Client c
    WHERE   c.Suppression IS NULL
      AND   c.DateCreation < @Limite
      AND   NOT EXISTS (SELECT 1
                        FROM   ventes.Commande cm
                        WHERE  cm.IdClient = c.IdClient
                          AND  cm.DateCommande >= @Limite);

    ALTER TABLE #Candidat ADD PRIMARY KEY (IdClient);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 2. Copie dans le schéma rgpd : client, commandes, lignes.
        INSERT INTO rgpd.Client (IdClient, Nom, Prenom, Email, Telephone, Adresse, CodePostal, Ville,
                                 CodeDepartement, Latitude, Longitude, DateCreation, DateArchivage)
        SELECT  c.IdClient, c.Nom, c.Prenom, c.Email, c.Telephone, c.Adresse, c.CodePostal, c.Ville,
                c.CodeDepartement, c.Latitude, c.Longitude, c.DateCreation, @DateReference
        FROM        ventes.Client c
        INNER JOIN  #Candidat     k ON k.IdClient = c.IdClient;

        INSERT INTO rgpd.Commande (IdCommande, IdClient, DateCommande, Statut)
        SELECT  cm.IdCommande, cm.IdClient, cm.DateCommande, cm.Statut
        FROM        ventes.Commande cm
        INNER JOIN  #Candidat       k ON k.IdClient = cm.IdClient;

        INSERT INTO rgpd.LigneCommande (IdCommande, NumeroLigne, IdProduit, Quantite, PrixUnitaireHT, TauxTVA)
        SELECT  l.IdCommande, l.NumeroLigne, l.IdProduit, l.Quantite, l.PrixUnitaireHT, l.TauxTVA
        FROM        ventes.LigneCommande l
        INNER JOIN  ventes.Commande      cm ON cm.IdCommande = l.IdCommande
        INNER JOIN  #Candidat            k  ON k.IdClient    = cm.IdClient;

        -- 3. Suppression PHYSIQUE dans ventes : on active le mode purge.
        EXEC sys.sp_set_session_context @key = N'PurgePhysique', @value = 1;

        DELETE c
        FROM        ventes.Client c
        INNER JOIN  #Candidat     k ON k.IdClient = c.IdClient;

        EXEC sys.sp_set_session_context @key = N'PurgePhysique', @value = NULL;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'PurgePhysique', @value = NULL;
        THROW;
    END CATCH

    SELECT (SELECT COUNT(*) FROM #Candidat) AS ClientsArchives, @DateReference AS DateArchivage;
END;
GO

/*==============================================================================
  6. PROCÉDURE N°2 : SUPPRESSION DÉFINITIVE (3 mois plus tard)
==============================================================================*/
CREATE OR ALTER PROCEDURE rgpd.usp_PurgerDefinitivement
    @DateReference DATETIME2(0) = NULL,      -- par défaut : maintenant
    @MoisDelai     INT          = 3
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @DateReference = ISNULL(@DateReference, SYSDATETIME());
    DECLARE @Limite DATETIME2(0) = DATEADD(MONTH, -@MoisDelai, @DateReference);
    DECLARE @NbArchives INT, @NbSupprimes INT, @NbCommandes INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Les clients archivés depuis plus de 3 mois (le CASCADE emporte commandes et lignes).
        DELETE FROM rgpd.Client WHERE DateArchivage < @Limite;
        SET @NbArchives = @@ROWCOUNT;

        -- 2. Les clients supprimés logiquement depuis plus de 3 mois, et leurs commandes.
        EXEC sys.sp_set_session_context @key = N'PurgePhysique', @value = 1;

        DELETE FROM ventes.Client WHERE Suppression < @Limite;
        SET @NbSupprimes = @@ROWCOUNT;

        -- 3. Au passage : les commandes supprimées seules (client toujours actif).
        DELETE FROM ventes.Commande WHERE Suppression < @Limite;
        SET @NbCommandes = @@ROWCOUNT;

        EXEC sys.sp_set_session_context @key = N'PurgePhysique', @value = NULL;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'PurgePhysique', @value = NULL;
        THROW;
    END CATCH

    SELECT  @NbArchives  AS ArchivesPurges,
            @NbSupprimes AS SupprimesPurges,
            @NbCommandes AS CommandesSeulesPurgees,
            @DateReference AS DateReference;
END;
GO

/*==============================================================================
  7. DÉMONSTRATION
==============================================================================*/
-- 7.1 Nos témoins avant : Paul (3, dormant), Chloé (4, jamais commandé),
--     Nathan (5, supprimé il y a 6 mois), Emma (6, supprimée il y a 15 jours).
SELECT IdClient, Prenom, Nom, DateCreation, Suppression FROM ventes.Client WHERE IdClient BETWEEN 3 AND 6;

-- 7.2 Archivage
EXEC rgpd.usp_ArchiverClientsInactifs;

SELECT IdClient, Prenom, Nom, DateArchivage FROM rgpd.Client WHERE IdClient IN (3, 4);
SELECT COUNT(*) AS ClientsArchives FROM rgpd.Client;
SELECT COUNT(*) AS CommandesArchivees FROM rgpd.Commande;

-- 7.3 Purge aujourd'hui : Nathan (supprimé il y a 6 mois) disparaît, Emma reste,
--     et les archives d'aujourd'hui sont conservées.
EXEC rgpd.usp_PurgerDefinitivement;
SELECT IdClient, Prenom, Nom, Suppression FROM ventes.Client WHERE IdClient IN (5, 6);

-- 7.4 On simule la purge « dans 4 mois » : les archives d'aujourd'hui partent à leur tour.
--     (On le fait dans une transaction annulée, pour garder nos données de démo.)
BEGIN TRANSACTION;
    DECLARE @Dans4Mois DATETIME2(0) = DATEADD(MONTH, 4, SYSDATETIME());
    EXEC rgpd.usp_PurgerDefinitivement @DateReference = @Dans4Mois;
    SELECT COUNT(*) AS ClientsArchivesRestants FROM rgpd.Client;
ROLLBACK TRANSACTION;
GO

/*==============================================================================
  8. ON PLANIFIE : le 1er de chaque mois, archivage à 02:00 puis purge à 02:30
==============================================================================*/
USE msdb;
GO
EXEC dbo.sp_add_job         @job_name = N'Boutique - RGPD archivage', @owner_login_name = N'sa',
                            @description = N'Archive les clients sans commande depuis 3 ans.';
EXEC dbo.sp_add_jobstep     @job_name = N'Boutique - RGPD archivage', @step_name = N'Archivage',
                            @subsystem = N'TSQL', @database_name = N'Boutique',
                            @command = N'EXEC rgpd.usp_ArchiverClientsInactifs;';
EXEC dbo.sp_add_jobschedule @job_name = N'Boutique - RGPD archivage', @name = N'Le 1er du mois 02:00',
                            @freq_type = 16,               -- mensuel
                            @freq_interval = 1,            -- le 1er du mois
                            @freq_recurrence_factor = 1,   -- tous les mois
                            @active_start_time = 020000;
EXEC dbo.sp_add_jobserver   @job_name = N'Boutique - RGPD archivage';
GO

EXEC dbo.sp_add_job         @job_name = N'Boutique - RGPD purge', @owner_login_name = N'sa',
                            @description = N'Supprime définitivement les archives et suppressions de plus de 3 mois.';
EXEC dbo.sp_add_jobstep     @job_name = N'Boutique - RGPD purge', @step_name = N'Purge',
                            @subsystem = N'TSQL', @database_name = N'Boutique',
                            @command = N'EXEC rgpd.usp_PurgerDefinitivement;';
EXEC dbo.sp_add_jobschedule @job_name = N'Boutique - RGPD purge', @name = N'Le 1er du mois 02:30',
                            @freq_type = 16, @freq_interval = 1, @freq_recurrence_factor = 1,
                            @active_start_time = 023000;
EXEC dbo.sp_add_jobserver   @job_name = N'Boutique - RGPD purge';
GO
