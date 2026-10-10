/*==============================================================================
  VIDÉO 19 : ATELIER PRATIQUE, LA BOUTIQUE DE A À Z
  Script 14 : chaque commercial ne voit que les clients de SES départements
  ------------------------------------------------------------------------------
  Outil : la sécurité au niveau des lignes (Row-Level Security, vidéo 13).
  Une fonction de filtre + une stratégie de sécurité sur ventes.Client :
  SQL Server ajoute tout seul un filtre invisible à TOUTES les requêtes,
  y compris celles qui passent par notre vue vRecapClient.
  Rappels : vidéo 12 (utilisateurs, rôles), vidéo 13 (RLS).
==============================================================================*/
USE Boutique;
GO

/*------------------------------------------------------------------------------
  1. Un schéma pour la sécurité et la table de rattachement
------------------------------------------------------------------------------*/
CREATE SCHEMA securite AUTHORIZATION dbo;
GO

CREATE TABLE securite.CommercialDepartement
(
    NomUtilisateur   SYSNAME     NOT NULL,     -- le nom de l'utilisateur dans la base
    CodeDepartement  VARCHAR(3)  NOT NULL,
    CONSTRAINT PK_CommercialDepartement PRIMARY KEY (NomUtilisateur, CodeDepartement),
    CONSTRAINT FK_CommercialDepartement_Departement
        FOREIGN KEY (CodeDepartement) REFERENCES ref.Departement (CodeDepartement)
);
GO

/*------------------------------------------------------------------------------
  2. Les commerciaux et leur rôle
  Pour la démo : des utilisateurs SANS LOGIN (ils ne peuvent pas se connecter,
  mais on peut « se mettre dans leur peau » avec EXECUTE AS). En entreprise, ce
  seraient des comptes Windows : CREATE USER [DOMAINE\jdupont] FOR LOGIN ...
------------------------------------------------------------------------------*/
CREATE USER commercial_ouest     WITHOUT LOGIN;
CREATE USER commercial_sud_ouest WITHOUT LOGIN;
GO

CREATE ROLE role_commercial AUTHORIZATION dbo;
ALTER ROLE role_commercial ADD MEMBER commercial_ouest;
ALTER ROLE role_commercial ADD MEMBER commercial_sud_ouest;
GO

-- Les commerciaux lisent la vue récapitulative, et rien d'autre.
GRANT SELECT ON ventes.vRecapClient TO role_commercial;
GO

INSERT INTO securite.CommercialDepartement (NomUtilisateur, CodeDepartement) VALUES
(N'commercial_ouest',     '79'), (N'commercial_ouest',     '86'),
(N'commercial_ouest',     '17'), (N'commercial_ouest',     '16'),
(N'commercial_sud_ouest', '33'), (N'commercial_sud_ouest', '40'),
(N'commercial_sud_ouest', '64'), (N'commercial_sud_ouest', '47'),
(N'commercial_sud_ouest', '24');
GO

/*------------------------------------------------------------------------------
  3. La fonction de filtre (prédicat)
  Elle reçoit le département de la ligne et renvoie une ligne (= « visible »)
  ou rien (= « invisible »).
  - Un utilisateur qui n'est PAS commercial (dbo, l'API, les jobs) voit tout.
  - Un commercial ne voit que les départements auxquels il est rattaché.
  SCHEMABINDING est obligatoire pour une fonction de sécurité.
------------------------------------------------------------------------------*/
CREATE FUNCTION securite.fn_FiltreDepartement (@CodeDepartement VARCHAR(3))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS Autorise
    WHERE  IS_ROLEMEMBER(N'role_commercial') = 0
       OR  EXISTS (SELECT 1
                   FROM   securite.CommercialDepartement cd
                   WHERE  cd.CodeDepartement = @CodeDepartement
                     AND  cd.NomUtilisateur  = USER_NAME());
GO

/*------------------------------------------------------------------------------
  4. La stratégie de sécurité : on branche le filtre sur la table des clients
------------------------------------------------------------------------------*/
CREATE SECURITY POLICY securite.PolitiqueClientParDepartement
    ADD FILTER PREDICATE securite.fn_FiltreDepartement(CodeDepartement) ON ventes.Client
    WITH (STATE = ON);
GO

/*------------------------------------------------------------------------------
  5. Démonstration
------------------------------------------------------------------------------*/
-- 5.1 Moi (dbo) : je vois toute la France.
SELECT COUNT(*) AS NbClientsVisibles, COUNT(DISTINCT CodeDepartement) AS NbDepartements
FROM   ventes.vRecapClient;

-- 5.2 Le commercial de l'Ouest : uniquement 16, 17, 79 et 86.
EXECUTE AS USER = N'commercial_ouest';
    SELECT USER_NAME() AS JeSuis;

    SELECT  CodeDepartement, Departement, COUNT(*) AS NbClients, SUM(MontantTotalTTC) AS CA_TTC
    FROM    ventes.vRecapClient
    GROUP BY CodeDepartement, Departement
    ORDER BY CodeDepartement;

    -- Même en filtrant explicitement sur Paris, il ne voit rien : la ligne n'existe pas pour lui.
    SELECT COUNT(*) AS ClientsParisVisibles FROM ventes.vRecapClient WHERE CodeDepartement = '75';

    -- Et la table directement ? Pas de droit du tout.
    BEGIN TRY
        SELECT TOP (1) * FROM ventes.Client;
    END TRY
    BEGIN CATCH
        SELECT ERROR_MESSAGE() AS ErreurAttendue;
    END CATCH
REVERT;
GO

-- 5.3 Le commercial du Sud-Ouest : uniquement ses cinq départements.
EXECUTE AS USER = N'commercial_sud_ouest';
    SELECT  CodeDepartement, Departement, COUNT(*) AS NbClients
    FROM    ventes.vRecapClient
    GROUP BY CodeDepartement, Departement
    ORDER BY CodeDepartement;
REVERT;
GO

-- 5.4 On rattache un nouveau département à un commercial : effet immédiat,
--     sans toucher ni à la vue, ni aux droits.
INSERT INTO securite.CommercialDepartement (NomUtilisateur, CodeDepartement) VALUES (N'commercial_ouest', '85');

EXECUTE AS USER = N'commercial_ouest';
    SELECT CodeDepartement, COUNT(*) AS NbClients
    FROM   ventes.vRecapClient
    GROUP BY CodeDepartement
    ORDER BY CodeDepartement;
REVERT;
GO

-- 5.5 Et l'API ? Elle n'est pas commerciale : elle voit tout, comme avant.
EXECUTE AS LOGIN = N'api_boutique';
    SELECT COUNT(*) AS ClientsVusParLAPI FROM ventes.Client;
REVERT;
GO
