/*==============================================================================
  VIDÉO 19 : ATELIER PRATIQUE, LA BOUTIQUE DE A À Z
  Script 13 : industrialiser l'import des adresses avec SSIS
  ------------------------------------------------------------------------------
  La BAN est mise à jour en permanence. Plutôt que de refaire l'import à la
  souris, on transforme le package enregistré par l'assistant (Import_BAN.dtsx)
  en un vrai traitement automatique, déployé sur le serveur et planifié.
  Rappels : vidéo 17 (SSIS : flux de contrôle, flux de données, paramètres,
            déploiement dans le catalogue SSISDB), vidéo 18 (jobs).

  ÉTAPES DANS VISUAL STUDIO (détaillées dans le script de la vidéo) :
    1. Nouveau projet « Integration Services Project » : IntegrationBAN
    2. Clic droit sur « Packages SSIS » > Ajouter un package existant
       > Import_BAN.dtsx (enregistré par l'assistant au chapitre précédent)
    3. Flux de contrôle, dans l'ordre, reliés par des contraintes « Succès » :
         a. Tâche d'exécution SQL « Vider la table de travail »
              TRUNCATE TABLE dbo.BAN_Import;
         b. Le flux de données de l'assistant (fichier plat -> dbo.BAN_Import)
         c. Tâche d'exécution SQL « Intégrer les adresses »
              EXEC dbo.usp_IntegrerBAN;
         d. Tâche d'exécution SQL « Libérer la place »
              TRUNCATE TABLE dbo.BAN_Import;
    4. Paramètre de projet CheminFichierBAN (String) ; sur le gestionnaire de
       connexion du fichier plat : Expressions > ConnectionString = @[$Project::CheminFichierBAN]
    5. Exécuter dans Visual Studio (F5) pour valider.
    6. Clic droit sur le projet > Déployer : serveur local, dossier /SSISDB/Geo
==============================================================================*/

/*------------------------------------------------------------------------------
  1. Prérequis : le catalogue SSISDB existe-t-il ?
  S'il n'existe pas : dans SSMS, clic droit sur « Catalogues Integration
  Services » > Créer un catalogue (il demande d'activer l'intégration CLR et un
  mot de passe pour la clé de chiffrement).
------------------------------------------------------------------------------*/
SELECT name, state_desc, create_date FROM sys.databases WHERE name = N'SSISDB';
GO

/*------------------------------------------------------------------------------
  2. Après le déploiement : le projet et le package sont bien dans le catalogue
------------------------------------------------------------------------------*/
SELECT  f.name AS Dossier, p.name AS Projet, pk.name AS Package, p.deployed_by_name, p.last_deployed_time
FROM        SSISDB.catalog.folders  f
INNER JOIN  SSISDB.catalog.projects p  ON p.folder_id   = f.folder_id
INNER JOIN  SSISDB.catalog.packages pk ON pk.project_id = p.project_id
WHERE   f.name = N'Geo';
GO

/*------------------------------------------------------------------------------
  3. On planifie : le 1er de chaque mois à 03:00
  Le plus simple est de créer le job à la souris (vidéo 18) : Nouveau job >
  Étape de type « Package SQL Server Integration Services » > Source « Catalogue
  SSIS » > \SSISDB\Geo\IntegrationBAN\Import_BAN.dtsx
  Voici l'équivalent en T-SQL (même commande que celle générée par SSMS).
------------------------------------------------------------------------------*/
USE msdb;
GO
EXEC dbo.sp_add_job         @job_name = N'Geo - Intégration BAN', @owner_login_name = N'sa',
                            @description = N'Recharge la Base Adresse Nationale via le package SSIS IntegrationBAN.';
EXEC dbo.sp_add_jobstep     @job_name = N'Geo - Intégration BAN',
                            @step_name = N'Package Import_BAN',
                            @subsystem = N'SSIS',
                            @command = N'/ISSERVER "\"\SSISDB\Geo\IntegrationBAN\Import_BAN.dtsx\"" /SERVER "\".\"" /Par "\"$ServerOption::LOGGING_LEVEL(Int16)\"";1 /Par "\"$ServerOption::SYNCHRONIZED(Boolean)\"";True /CALLERINFO SQLAGENT /REPORTING E';
EXEC dbo.sp_add_jobschedule @job_name = N'Geo - Intégration BAN', @name = N'Le 1er du mois 03:00',
                            @freq_type = 16, @freq_interval = 1, @freq_recurrence_factor = 1,
                            @active_start_time = 030000;
EXEC dbo.sp_add_jobserver   @job_name = N'Geo - Intégration BAN';
GO

-- Pour tester tout de suite sans attendre le 1er du mois :
-- EXEC msdb.dbo.sp_start_job @job_name = N'Geo - Intégration BAN';

/*------------------------------------------------------------------------------
  4. Suivi des exécutions dans le catalogue
  (ou, à la souris : clic droit sur le package > Rapports > Toutes les exécutions)
------------------------------------------------------------------------------*/
SELECT TOP (10)
        e.execution_id,
        e.package_name,
        CASE e.status WHEN 1 THEN 'Créée'   WHEN 2 THEN 'En cours' WHEN 3 THEN 'Annulée'
                      WHEN 4 THEN 'Échec'   WHEN 5 THEN 'En attente' WHEN 6 THEN 'Arrêt imprévu'
                      WHEN 7 THEN 'Réussie' WHEN 9 THEN 'Terminée' END AS Statut,
        e.start_time,
        e.end_time,
        DATEDIFF(SECOND, e.start_time, e.end_time) AS DureeSecondes
FROM    SSISDB.catalog.executions e
WHERE   e.folder_name = N'Geo'
ORDER BY e.execution_id DESC;
GO

-- Et le résultat côté données.
SELECT COUNT_BIG(*) AS AdressesEnBase FROM Geo.dbo.Adresse;
GO
