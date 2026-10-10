/*==============================================================================
  VIDÉO 19 : ATELIER PRATIQUE, LA BOUTIQUE DE A À Z
  Script 12 : la maintenance automatique des index
  ------------------------------------------------------------------------------
  Avec les insertions, les mises à jour et les purges RGPD, les index se
  fragmentent : les pages ne sont plus dans l'ordre et se vident en partie.
  Règle usuelle (vidéo 14) :
    - fragmentation < 5 %          : on ne touche à rien
    - entre 5 et 30 %              : REORGANIZE (léger, toujours en ligne)
    - au-delà de 30 %              : REBUILD    (reconstruction complète)
    - index de moins de 1000 pages : on ignore, ça ne vaut pas le coup
  Rappels : vidéo 14 (fragmentation), vidéo 18 (plans de maintenance, jobs).
  Pour aller plus loin en production : la solution libre d'Ola Hallengren.
==============================================================================*/
USE Boutique;
GO

/*------------------------------------------------------------------------------
  1. Où en est-on ? La fragmentation de nos index
------------------------------------------------------------------------------*/
SELECT  OBJECT_SCHEMA_NAME(ps.object_id) + '.' + OBJECT_NAME(ps.object_id) AS Table_,
        i.name                                                AS Index_,
        CAST(ps.avg_fragmentation_in_percent AS DECIMAL(5,1)) AS FragmentationPourcent,
        ps.page_count                                         AS NbPages
FROM        sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
INNER JOIN  sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE   ps.index_id > 0                        -- 0 = tas (table sans index cluster)
  AND   ps.page_count >= 100
ORDER BY ps.avg_fragmentation_in_percent DESC;
GO

/*------------------------------------------------------------------------------
  2. Un journal pour garder la trace de chaque opération
------------------------------------------------------------------------------*/
CREATE TABLE admin.JournalMaintenance
(
    IdJournal       INT            IDENTITY(1,1) NOT NULL,
    DateOperation   DATETIME2(0)   NOT NULL CONSTRAINT DF_JournalMaintenance_Date DEFAULT (SYSDATETIME()),
    Objet           NVARCHAR(260)  NOT NULL,
    Index_          NVARCHAR(128)  NOT NULL,
    Fragmentation   DECIMAL(5,1)   NOT NULL,
    NbPages         BIGINT         NOT NULL,
    Action_         VARCHAR(12)    NOT NULL,
    DureeMs         INT            NULL,
    CONSTRAINT PK_JournalMaintenance PRIMARY KEY (IdJournal)
);
GO

/*------------------------------------------------------------------------------
  3. La procédure de maintenance
  @Executer = 0 : on affiche seulement ce qui serait fait (mode « à blanc »).
------------------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE admin.usp_MaintenanceIndex
    @SeuilReorganize DECIMAL(5,1) = 5.0,
    @SeuilRebuild    DECIMAL(5,1) = 30.0,
    @PagesMin        INT          = 1000,
    @Executer        BIT          = 1
AS
BEGIN
    SET NOCOUNT ON;

    -- La reconstruction EN LIGNE (sans bloquer les utilisateurs) n'existe
    -- qu'en édition Enterprise / Developer (EngineEdition = 3).
    DECLARE @OptionEnLigne NVARCHAR(20) =
        CASE WHEN CAST(SERVERPROPERTY('EngineEdition') AS INT) = 3 THEN N'ON' ELSE N'OFF' END;

    DROP TABLE IF EXISTS #ATraiter;
    SELECT  QUOTENAME(OBJECT_SCHEMA_NAME(ps.object_id)) + N'.' + QUOTENAME(OBJECT_NAME(ps.object_id)) AS Objet,
            i.name                                                AS NomIndex,
            CAST(ps.avg_fragmentation_in_percent AS DECIMAL(5,1)) AS Fragmentation,
            ps.page_count                                         AS NbPages,
            CASE WHEN ps.avg_fragmentation_in_percent >= @SeuilRebuild THEN 'REBUILD'
                 ELSE 'REORGANIZE' END                            AS Action_
    INTO    #ATraiter
    FROM        sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
    INNER JOIN  sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
    WHERE   ps.index_id > 0
      AND   ps.alloc_unit_type_desc = N'IN_ROW_DATA'
      AND   ps.page_count >= @PagesMin
      AND   ps.avg_fragmentation_in_percent >= @SeuilReorganize;

    IF @Executer = 0
    BEGIN
        SELECT * FROM #ATraiter ORDER BY Fragmentation DESC;
        RETURN;
    END

    DECLARE @Objet NVARCHAR(260), @NomIndex SYSNAME, @Frag DECIMAL(5,1),
            @Pages BIGINT, @Action VARCHAR(12), @Sql NVARCHAR(MAX), @Debut DATETIME2(3);

    DECLARE curIndex CURSOR LOCAL FAST_FORWARD FOR
        SELECT Objet, NomIndex, Fragmentation, NbPages, Action_ FROM #ATraiter;
    OPEN curIndex;
    FETCH NEXT FROM curIndex INTO @Objet, @NomIndex, @Frag, @Pages, @Action;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N'ALTER INDEX ' + QUOTENAME(@NomIndex) + N' ON ' + @Objet
                 + CASE @Action
                       WHEN 'REBUILD' THEN N' REBUILD WITH (ONLINE = ' + @OptionEnLigne + N', SORT_IN_TEMPDB = ON);'
                       -- REORGANIZE ne met pas à jour les statistiques : on le fait juste après.
                       ELSE N' REORGANIZE; UPDATE STATISTICS ' + @Objet + N' ' + QUOTENAME(@NomIndex) + N';'
                   END;

        SET @Debut = SYSDATETIME();
        EXEC sys.sp_executesql @Sql;

        INSERT INTO admin.JournalMaintenance (Objet, Index_, Fragmentation, NbPages, Action_, DureeMs)
        VALUES (@Objet, @NomIndex, @Frag, @Pages, @Action, DATEDIFF(MILLISECOND, @Debut, SYSDATETIME()));

        FETCH NEXT FROM curIndex INTO @Objet, @NomIndex, @Frag, @Pages, @Action;
    END

    CLOSE curIndex;
    DEALLOCATE curIndex;

    -- Enfin, les statistiques qui ont bougé depuis leur dernière mise à jour.
    EXEC sys.sp_updatestats @resample = 'RESAMPLE';
END;
GO

/*------------------------------------------------------------------------------
  4. Démonstration : d'abord « à blanc », puis pour de vrai
------------------------------------------------------------------------------*/
EXEC admin.usp_MaintenanceIndex @Executer = 0;
GO
EXEC admin.usp_MaintenanceIndex;
GO
SELECT * FROM admin.JournalMaintenance ORDER BY IdJournal DESC;
GO

/*------------------------------------------------------------------------------
  5. On planifie : chaque dimanche à 00:30, juste AVANT la sauvegarde complète
     de 01:00 (la sauvegarde contiendra ainsi des index tout propres).
------------------------------------------------------------------------------*/
USE msdb;
GO
EXEC dbo.sp_add_job         @job_name = N'Boutique - Maintenance des index', @owner_login_name = N'sa',
                            @description = N'Réorganise ou reconstruit les index fragmentés, met à jour les statistiques.';
EXEC dbo.sp_add_jobstep     @job_name = N'Boutique - Maintenance des index', @step_name = N'Index et statistiques',
                            @subsystem = N'TSQL', @database_name = N'Boutique',
                            @command = N'EXEC admin.usp_MaintenanceIndex;';
EXEC dbo.sp_add_jobschedule @job_name = N'Boutique - Maintenance des index', @name = N'Dimanche 00:30',
                            @freq_type = 8, @freq_interval = 1, @freq_recurrence_factor = 1,
                            @active_start_time = 003000;
EXEC dbo.sp_add_jobserver   @job_name = N'Boutique - Maintenance des index';
GO

-- Tous les jobs de la boutique
SELECT name AS Job, enabled, date_created FROM msdb.dbo.sysjobs WHERE name LIKE N'Boutique - %' ORDER BY name;
GO
