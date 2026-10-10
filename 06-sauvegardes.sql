/*==============================================================================
  VIDÉO 19 : ATELIER PRATIQUE, LA BOUTIQUE DE A À Z
  Script 06 : le plan de sauvegarde (complète, différentielle, journal)
  ------------------------------------------------------------------------------
  Stratégie retenue pour la boutique :
    - complète       : chaque dimanche à 01:00
    - différentielle : du lundi au samedi à 01:00
    - journal        : toutes les 15 minutes
  => en cas de crise, on perd au maximum 15 minutes de données.

  AVANT DE LANCER : adapter le dossier D:\SQLBACKUP\ (idéalement un autre disque,
  voire un partage réseau), accessible au compte de service SQL Server.
==============================================================================*/
USE Boutique;
GO

/*------------------------------------------------------------------------------
  1. Une procédure qui fait UNE sauvegarde, avec un nom de fichier horodaté
     (Boutique_FULL_20261003_0100.bak) pour ne jamais écraser la précédente.
------------------------------------------------------------------------------*/
CREATE OR ALTER PROCEDURE admin.usp_Sauvegarder
    @Type    VARCHAR(4),                                   -- FULL, DIFF ou LOG
    @Dossier NVARCHAR(200) = N'D:\SQL_SERVER\SQLBACKUP\Boutique\'
AS
BEGIN
    SET NOCOUNT ON;

    IF @Type NOT IN ('FULL', 'DIFF', 'LOG')
        THROW 50000, N'Type de sauvegarde inconnu : FULL, DIFF ou LOG.', 1;

    -- Le dossier est créé s'il n'existe pas.
    EXEC master.dbo.xp_create_subdir @Dossier;

    DECLARE @Fichier NVARCHAR(400) =
          @Dossier + N'Boutique_' + @Type + N'_'
        + FORMAT(SYSDATETIME(), 'yyyyMMdd_HHmmss')
        + CASE @Type WHEN 'LOG' THEN N'.trn' ELSE N'.bak' END;

    IF @Type = 'FULL'
        BACKUP DATABASE Boutique TO DISK = @Fichier
        WITH COMPRESSION, CHECKSUM, INIT, NAME = N'Boutique - complète';

    IF @Type = 'DIFF'
        BACKUP DATABASE Boutique TO DISK = @Fichier
        WITH DIFFERENTIAL, COMPRESSION, CHECKSUM, INIT, NAME = N'Boutique - différentielle';

    IF @Type = 'LOG'
        BACKUP LOG Boutique TO DISK = @Fichier
        WITH COMPRESSION, CHECKSUM, INIT, NAME = N'Boutique - journal';

    PRINT N'Sauvegarde ' + @Type + N' terminée : ' + @Fichier;
END;
GO

/*------------------------------------------------------------------------------
  2. On déroule la chaîne à la main, une fois, pour comprendre
------------------------------------------------------------------------------*/
-- 2.1 La complète : c'est le point de départ de toute la chaîne.
EXEC admin.usp_Sauvegarder @Type = 'FULL';
GO

-- 2.2 Il se passe des choses dans la journée...
UPDATE ventes.Produit SET Stock = Stock + 10 WHERE IdProduit <= 100;
GO

-- 2.3 La différentielle : tout ce qui a changé DEPUIS LA DERNIÈRE COMPLÈTE.
EXEC admin.usp_Sauvegarder @Type = 'DIFF';
GO

-- 2.4 Le journal : toutes les transactions depuis la dernière sauvegarde du journal.
EXEC admin.usp_Sauvegarder @Type = 'LOG';
GO

-- 2.5 L'historique, tel que SQL Server le garde dans msdb.
SELECT  bs.backup_start_date,
        CASE bs.type WHEN 'D' THEN 'Complète' WHEN 'I' THEN 'Différentielle' WHEN 'L' THEN 'Journal' END AS TypeSauvegarde,
        CAST(bs.backup_size / 1048576.0            AS DECIMAL(10,1)) AS TailleMo,
        CAST(bs.compressed_backup_size / 1048576.0 AS DECIMAL(10,1)) AS TailleCompresseeMo,
        bmf.physical_device_name                                      AS Fichier
FROM        msdb.dbo.backupset         bs
INNER JOIN  msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id
WHERE   bs.database_name = N'Boutique'
ORDER BY bs.backup_start_date DESC;
GO

-- 2.6 Une sauvegarde qu'on n'a jamais testée n'est pas une sauvegarde :
--     on vérifie au minimum qu'elle est lisible et complète.
DECLARE @DerniereComplete NVARCHAR(400) =
(
    SELECT TOP (1) bmf.physical_device_name
    FROM        msdb.dbo.backupset         bs
    INNER JOIN  msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id
    WHERE   bs.database_name = N'Boutique' AND bs.type = 'D'
    ORDER BY bs.backup_start_date DESC
);
RESTORE VERIFYONLY FROM DISK = @DerniereComplete WITH CHECKSUM;
GO

/*------------------------------------------------------------------------------
  3. On automatise avec SQL Server Agent : trois jobs, trois planifications.
     (On pourrait les créer à la souris comme dans la vidéo 18 ; en script,
      c'est reproductible sur n'importe quel serveur.)
------------------------------------------------------------------------------*/
USE msdb;
GO

/*--- 3.1 Sauvegarde complète : le dimanche à 01:00 ---*/
EXEC dbo.sp_add_job        @job_name = N'Boutique - Sauvegarde complète',
                           @owner_login_name = N'sa',
                           @description = N'Sauvegarde complète hebdomadaire de la base Boutique.';
EXEC dbo.sp_add_jobstep    @job_name = N'Boutique - Sauvegarde complète',
                           @step_name = N'Sauvegarde FULL',
                           @subsystem = N'TSQL', @database_name = N'Boutique',
                           @command = N'EXEC admin.usp_Sauvegarder @Type = ''FULL'';';
EXEC dbo.sp_add_jobschedule @job_name = N'Boutique - Sauvegarde complète',
                           @name = N'Dimanche 01:00',
                           @freq_type = 8,                 -- hebdomadaire
                           @freq_interval = 1,             -- 1 = dimanche
                           @freq_recurrence_factor = 1,    -- toutes les semaines
                           @active_start_time = 010000;    -- HHMMSS
EXEC dbo.sp_add_jobserver  @job_name = N'Boutique - Sauvegarde complète';
GO

/*--- 3.2 Sauvegarde différentielle : du lundi au samedi à 01:00 ---*/
EXEC dbo.sp_add_job        @job_name = N'Boutique - Sauvegarde différentielle',
                           @owner_login_name = N'sa',
                           @description = N'Sauvegarde différentielle quotidienne de la base Boutique.';
EXEC dbo.sp_add_jobstep    @job_name = N'Boutique - Sauvegarde différentielle',
                           @step_name = N'Sauvegarde DIFF',
                           @subsystem = N'TSQL', @database_name = N'Boutique',
                           @command = N'EXEC admin.usp_Sauvegarder @Type = ''DIFF'';';
EXEC dbo.sp_add_jobschedule @job_name = N'Boutique - Sauvegarde différentielle',
                           @name = N'Lundi au samedi 01:00',
                           @freq_type = 8,
                           @freq_interval = 126,           -- 2+4+8+16+32+64 = lundi..samedi
                           @freq_recurrence_factor = 1,
                           @active_start_time = 010000;
EXEC dbo.sp_add_jobserver  @job_name = N'Boutique - Sauvegarde différentielle';
GO

/*--- 3.3 Sauvegarde du journal : toutes les 15 minutes ---*/
EXEC dbo.sp_add_job        @job_name = N'Boutique - Sauvegarde journal',
                           @owner_login_name = N'sa',
                           @description = N'Sauvegarde du journal de transactions toutes les 15 minutes.';
EXEC dbo.sp_add_jobstep    @job_name = N'Boutique - Sauvegarde journal',
                           @step_name = N'Sauvegarde LOG',
                           @subsystem = N'TSQL', @database_name = N'Boutique',
                           @command = N'EXEC admin.usp_Sauvegarder @Type = ''LOG'';';
EXEC dbo.sp_add_jobschedule @job_name = N'Boutique - Sauvegarde journal',
                           @name = N'Toutes les 15 minutes',
                           @freq_type = 4,                 -- quotidien
                           @freq_interval = 1,             -- tous les jours
                           @freq_subday_type = 4,          -- unité : minutes
                           @freq_subday_interval = 15,     -- toutes les 15 minutes
                           @active_start_time = 000000;
EXEC dbo.sp_add_jobserver  @job_name = N'Boutique - Sauvegarde journal';
GO

/*------------------------------------------------------------------------------
  4. Vérification : nos jobs et leur prochaine exécution
------------------------------------------------------------------------------*/
SELECT  j.name AS Job, s.name AS Planification, j.enabled,
        msdb.dbo.agent_datetime(NULLIF(js.next_run_date, 0), js.next_run_time) AS ProchaineExecution
FROM        msdb.dbo.sysjobs          j
INNER JOIN  msdb.dbo.sysjobschedules  js ON js.job_id = j.job_id
INNER JOIN  msdb.dbo.sysschedules     s  ON s.schedule_id = js.schedule_id
WHERE   j.name LIKE N'Boutique - Sauvegarde%'
ORDER BY j.name;
GO
-- Note : next_run_date est rafraîchi par l'Agent toutes les 20 minutes environ ;
-- juste après la création, la colonne peut encore être vide.
