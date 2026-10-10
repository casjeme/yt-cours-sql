/*==============================================================================
  VIDÉO 19 : ATELIER PRATIQUE, LA BOUTIQUE DE A À Z
  Script 99 : remise à zéro complète (pour refaire la démo depuis le début)
  ------------------------------------------------------------------------------
  Supprime : les jobs de l'Agent créés par la démo, les bases Boutique et Geo,
  les logins créés par la démo. NE SUPPRIME PAS les fichiers de sauvegarde.
==============================================================================*/
USE msdb;
GO
DECLARE @job SYSNAME;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE N'Boutique - %' OR name LIKE N'Geo - %';
OPEN c;
FETCH NEXT FROM c INTO @job;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @job, @delete_unused_schedule = 1;
    FETCH NEXT FROM c INTO @job;
END
CLOSE c; DEALLOCATE c;
GO

USE master;
GO
IF DB_ID(N'Boutique') IS NOT NULL
BEGIN
    ALTER DATABASE Boutique SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Boutique;
END
IF DB_ID(N'Geo') IS NOT NULL
BEGIN
    ALTER DATABASE Geo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Geo;
END
GO

IF SUSER_ID(N'api_boutique') IS NOT NULL DROP LOGIN api_boutique;
GO

-- Historique des sauvegardes de la base dans msdb (facultatif).
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'Boutique';
GO
