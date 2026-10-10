/*==============================================================================
  VIDÉO 19 : ATELIER PRATIQUE, LA BOUTIQUE DE A À Z
  Script 04 : un compte pour la future API
==============================================================================*/

/*------------------------------------------------------------------------------
  1. Le LOGIN : la porte d'entrée sur le SERVEUR
  Authentification SQL (l'API tournera peut-être sur un serveur Linux ou un
  conteneur, hors domaine). On garde la politique de mot de passe Windows.
  Le mot de passe ci-dessous est un exemple : en vrai, il vient d'un coffre-fort.
------------------------------------------------------------------------------*/
USE master;
GO
CREATE LOGIN api_boutique
    WITH PASSWORD        = N'Api!Boutique#2026-ChangezMoi',
         DEFAULT_DATABASE = Boutique,
         CHECK_POLICY     = ON,
         CHECK_EXPIRATION = OFF;
GO

/*------------------------------------------------------------------------------
  2. L'UTILISATEUR : la porte d'entrée sur la BASE
------------------------------------------------------------------------------*/
USE Boutique;
GO
CREATE USER api_boutique FOR LOGIN api_boutique WITH DEFAULT_SCHEMA = ventes;
GO

/*------------------------------------------------------------------------------
  3. Un RÔLE applicatif qui porte les droits
  On ne donne jamais les droits directement à l'utilisateur : demain, une
  deuxième API ou un batch auront besoin des mêmes droits, on les ajoutera au rôle.
------------------------------------------------------------------------------*/
CREATE ROLE role_api AUTHORIZATION dbo;
GO

-- Lecture / écriture sur le cœur métier.
-- Le DELETE est autorisé : on verra qu'il sera transformé en suppression LOGIQUE.
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::ventes TO role_api;

-- Lecture seule sur les référentiels.
GRANT SELECT ON SCHEMA::ref TO role_api;

-- Rien sur le schéma admin : l'API n'a pas à lancer de sauvegarde ou de maintenance.
-- Pas de droit de créer ou modifier des tables : l'API manipule des DONNÉES, pas la structure.
GO

ALTER ROLE role_api ADD MEMBER api_boutique;
GO

/*------------------------------------------------------------------------------
  4. Vérification : on se met dans la peau de l'API
------------------------------------------------------------------------------*/
EXECUTE AS LOGIN = N'api_boutique';

    SELECT SUSER_NAME() AS LoginCourant, USER_NAME() AS UtilisateurCourant;

    SELECT COUNT(*) AS NbDepartements FROM ref.Departement;     -- autorisé

    BEGIN TRY
        CREATE TABLE ventes.Test (Id INT);                       -- refusé
    END TRY
    BEGIN CATCH
        SELECT ERROR_MESSAGE() AS ErreurAttendue;
    END CATCH

    BEGIN TRY
        INSERT INTO ref.Region (CodeRegion, Nom) VALUES ('99', N'Test');  -- refusé
    END TRY
    BEGIN CATCH
        SELECT ERROR_MESSAGE() AS ErreurAttendue;
    END CATCH

REVERT;
GO

-- Les droits effectifs du rôle, vus depuis les vues système.
SELECT  pr.name AS Principal, pe.permission_name, pe.state_desc,
        pe.class_desc, SCHEMA_NAME(pe.major_id) AS Schema_
FROM        sys.database_permissions pe
INNER JOIN  sys.database_principals  pr ON pr.principal_id = pe.grantee_principal_id
WHERE   pr.name = N'role_api';
GO
