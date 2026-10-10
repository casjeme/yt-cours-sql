/*==============================================================================
  VIDÉO 19 : ATELIER PRATIQUE, LA BOUTIQUE DE A À Z
  Script 08 : la vue récapitulative des clients
  ------------------------------------------------------------------------------
  Une seule vue qui répond à « qui sont nos clients, combien ont-ils dépensé,
  quand ont-ils commandé pour la dernière fois, et où sont-ils ? ».
  Rappels : vidéo 07 (jointures, vues), vidéo 06 (agrégats),
            vidéo 15 (le type geography).
==============================================================================*/
USE Boutique;
GO

CREATE OR ALTER VIEW ventes.vRecapClient
AS
SELECT  c.IdClient,
        c.Nom,
        c.Prenom,
        c.Email,
        c.CodePostal,
        c.Ville,
        d.CodeDepartement,
        d.Nom                                      AS Departement,
        r.Nom                                      AS Region,
        ISNULL(a.NbCommandes, 0)                   AS NbCommandes,
        ISNULL(a.MontantTotalTTC, 0)               AS MontantTotalTTC,
        a.DateDerniereCommande,
        -- Un point GPS exploitable par une carte (SRID 4326 = le GPS mondial).
        -- Attention à l'ordre : geography::Point(LATITUDE, LONGITUDE, SRID).
        CASE WHEN c.Latitude IS NOT NULL
             THEN geography::Point(c.Latitude, c.Longitude, 4326)
        END                                        AS Position
FROM        ventes.Client     c
INNER JOIN  ref.Departement   d ON d.CodeDepartement = c.CodeDepartement
INNER JOIN  ref.Region        r ON r.CodeRegion      = d.CodeRegion
LEFT  JOIN
(
    -- Les commandes valides seulement : ni annulées, ni supprimées.
    SELECT  cm.IdClient,
            COUNT(DISTINCT cm.IdCommande)                                         AS NbCommandes,
            CAST(SUM(l.Quantite * l.PrixUnitaireHT * (1 + l.TauxTVA / 100))
                 AS DECIMAL(12,2))                                                AS MontantTotalTTC,
            MAX(cm.DateCommande)                                                  AS DateDerniereCommande
    FROM        ventes.Commande      cm
    INNER JOIN  ventes.LigneCommande l ON l.IdCommande = cm.IdCommande
    WHERE   cm.Statut <> 'ANNULEE'
      AND   cm.Suppression IS NULL
    GROUP BY cm.IdClient
) a ON a.IdClient = c.IdClient
WHERE   c.Suppression IS NULL;          -- les clients supprimés n'apparaissent plus
GO

/*------------------------------------------------------------------------------
  Démonstrations
------------------------------------------------------------------------------*/
-- 1. Notre cliente témoin
SELECT * FROM ventes.vRecapClient WHERE IdClient = 1;

-- 2. Le top 10 des meilleurs clients
SELECT TOP (10) Prenom, Nom, Ville, Departement, NbCommandes, MontantTotalTTC, DateDerniereCommande
FROM   ventes.vRecapClient
ORDER BY MontantTotalTTC DESC;

-- 3. Le chiffre d'affaires par région
SELECT  Region,
        COUNT(*)              AS NbClients,
        SUM(MontantTotalTTC)  AS CA_TTC
FROM    ventes.vRecapClient
GROUP BY Region
ORDER BY CA_TTC DESC;

-- 4. La carte ! Dans SSMS, ouvrir l'onglet « Résultats spatiaux ».
--    STBuffer(2000) dessine un cercle de 2 km autour de chaque client pour qu'on le voie.
--    SSMS affiche au maximum 5 000 objets : on se limite à deux départements.
SELECT  Position.STBuffer(2000) AS Carte, Ville, NbCommandes
FROM    ventes.vRecapClient
WHERE   CodeDepartement IN ('79', '86');

-- 5. Les clients à moins de 10 km de Niort (Place de la Brèche), du plus proche au plus loin
DECLARE @Niort geography = geography::Point(46.3213, -0.4629, 4326);

SELECT  TOP (20) Prenom, Nom, Ville,
        CAST(Position.STDistance(@Niort) / 1000 AS DECIMAL(6,2)) AS DistanceKm
FROM    ventes.vRecapClient
WHERE   Position.STDistance(@Niort) <= 10000
ORDER BY DistanceKm;
GO
