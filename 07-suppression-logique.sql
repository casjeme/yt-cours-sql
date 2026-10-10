/*==============================================================================
  VIDÉO 19 : ATELIER PRATIQUE, LA BOUTIQUE DE A À Z
  Script 07 : la suppression LOGIQUE par triggers
  ------------------------------------------------------------------------------
  Besoin métier : quand un client demande sa suppression (ou quand l'API envoie
  un DELETE), on ne détruit rien tout de suite. On marque la ligne avec la date
  de suppression (colonne Suppression), pour le client ET ses commandes.
  La suppression définitive viendra plus tard (chapitre RGPD).

  Outil : un trigger INSTEAD OF DELETE. Il se déclenche À LA PLACE du DELETE :
  le DELETE demandé n'a jamais lieu, c'est le trigger qui décide quoi faire.
  Rappels : vidéo 10 (triggers, tables inserted / deleted).
==============================================================================*/
USE Boutique;
GO

/*------------------------------------------------------------------------------
  1. Trigger sur les COMMANDES : un DELETE de commande devient une date de suppression
------------------------------------------------------------------------------*/
CREATE OR ALTER TRIGGER ventes.trg_Commande_SuppressionLogique
ON ventes.Commande
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- « deleted » contient les lignes que l'utilisateur voulait supprimer.
    UPDATE cm
    SET    cm.Suppression = SYSDATETIME()
    FROM        ventes.Commande cm
    INNER JOIN  deleted         d ON d.IdCommande = cm.IdCommande
    WHERE   cm.Suppression IS NULL;          -- on ne réécrit pas une date déjà posée
END;
GO

/*------------------------------------------------------------------------------
  2. Trigger sur les CLIENTS : le client ET toutes ses commandes sont marqués
------------------------------------------------------------------------------*/
CREATE OR ALTER TRIGGER ventes.trg_Client_SuppressionLogique
ON ventes.Client
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Maintenant DATETIME2(0) = SYSDATETIME();   -- même date partout

    -- Les commandes du client
    UPDATE cm
    SET    cm.Suppression = @Maintenant
    FROM        ventes.Commande cm
    INNER JOIN  deleted         d ON d.IdClient = cm.IdClient
    WHERE   cm.Suppression IS NULL;

    -- Le client lui-même
    UPDATE c
    SET    c.Suppression = @Maintenant
    FROM        ventes.Client c
    INNER JOIN  deleted       d ON d.IdClient = c.IdClient
    WHERE   c.Suppression IS NULL;
END;
GO

/*------------------------------------------------------------------------------
  3. Démonstration avec notre cliente témoin n°1, Léa Martin
------------------------------------------------------------------------------*/
-- Avant : Léa est active, ses commandes aussi.
SELECT IdClient, Prenom, Nom, Suppression FROM ventes.Client   WHERE IdClient = 1;
SELECT IdCommande, DateCommande, Statut, Suppression FROM ventes.Commande WHERE IdClient = 1;

-- On supprime Léa, comme le ferait l'API...
DELETE FROM ventes.Client WHERE IdClient = 1;

-- Après : la ligne est TOUJOURS là, avec une date de suppression. Ses commandes aussi.
SELECT IdClient, Prenom, Nom, Suppression FROM ventes.Client   WHERE IdClient = 1;
SELECT IdCommande, DateCommande, Statut, Suppression FROM ventes.Commande WHERE IdClient = 1;
GO

-- Léa change d'avis ? Avec une suppression logique, on la « ressuscite » en une ligne.
UPDATE ventes.Commande SET Suppression = NULL WHERE IdClient = 1;
UPDATE ventes.Client   SET Suppression = NULL WHERE IdClient = 1;
GO

-- Le même mécanisme fonctionne avec les droits de l'API : elle a le droit DELETE,
-- mais elle ne peut plus rien détruire physiquement.
EXECUTE AS LOGIN = N'api_boutique';
    DELETE FROM ventes.Commande WHERE IdCommande = 2;
REVERT;
SELECT IdCommande, Suppression FROM ventes.Commande WHERE IdCommande = 2;
UPDATE ventes.Commande SET Suppression = NULL WHERE IdCommande = 2;   -- on remet en état
GO

-- Les triggers de la base
SELECT  OBJECT_SCHEMA_NAME(parent_id) + '.' + OBJECT_NAME(parent_id) AS Table_,
        name AS Trigger_, is_instead_of_trigger, is_disabled
FROM    sys.triggers
WHERE   parent_class = 1;
GO
