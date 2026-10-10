/*==============================================================================
  VIDÉO 19 : ATELIER PRATIQUE, LA BOUTIQUE DE A À Z
  Script 11 : plans d'exécution, avant et après les index
  ------------------------------------------------------------------------------
  Rappels : vidéo 14 (plans d'exécution, Scan vs Seek, Key Lookup, index
            couvrant, SARGabilité), vidéo 04 (index cluster / non cluster).

  AVANT DE COMMENCER dans SSMS :
    - Ctrl+M : « Inclure le plan d'exécution réel »
    - les statistiques d'E/S et de temps, activées ci-dessous
  À regarder à chaque requête : l'onglet « Plan d'exécution » et, dans l'onglet
  « Messages », les LECTURES LOGIQUES (logical reads) = pages de 8 Ko lues.
==============================================================================*/
SET STATISTICS IO, TIME ON;
GO

/*==============================================================================
  PARTIE 1 : LA BASE GEO, 26 MILLIONS D'ADRESSES SANS AUCUN INDEX
  La question que posera l'API : « quelles sont les coordonnées GPS du
  20 rue Victor Hugo à Niort ? »
==============================================================================*/
USE Geo;
GO

-- 1.1 Sans index : SQL Server n'a pas le choix, il lit TOUTE la table (Table Scan).
--     Regardez les lectures logiques, le temps, et le conseil en vert dans le plan :
--     « Index manquant ».
SELECT  Numero, NomVoie, NomCommune, Latitude, Longitude
FROM    dbo.Adresse
WHERE   CodePostal = '79000'
  AND   NomVoie    = N'Rue Victor Hugo'
  AND   Numero     = 20;
GO

-- 1.2 On crée l'index qui correspond EXACTEMENT à la recherche :
--     - la clé : les colonnes du WHERE, de la plus sélective à la moins sélective
--       à l'usage (on cherche toujours par code postal + voie + numéro),
--     - INCLUDE : les colonnes du SELECT, stockées dans l'index sans faire partie
--       de la clé => l'index COUVRE la requête, plus besoin d'aller dans la table.
--     Sur 26 millions de lignes, la création prend une à deux minutes.
CREATE INDEX IX_Adresse_Recherche
    ON dbo.Adresse (CodePostal, NomVoie, Numero)
    INCLUDE (NomCommune, Latitude, Longitude)
    WITH (SORT_IN_TEMPDB = ON);
GO

-- 1.3 La même requête : Index Seek, une poignée de lectures, temps proche de zéro.
SELECT  Numero, NomVoie, NomCommune, Latitude, Longitude
FROM    dbo.Adresse
WHERE   CodePostal = '79000'
  AND   NomVoie    = N'Rue Victor Hugo'
  AND   Numero     = 20;
GO

-- 1.4 Deux pièges classiques qui « cassent » l'index (SARGabilité, vidéo 14)
-- a) Le code postal écrit comme un NOMBRE : SQL Server doit convertir la colonne
--    sur chaque ligne (CONVERT_IMPLICIT dans le plan) => retour au scan.
SELECT  Numero, NomVoie, Latitude, Longitude
FROM    dbo.Adresse
WHERE   CodePostal = 79000
  AND   NomVoie    = N'Rue Victor Hugo'
  AND   Numero     = 20;

-- b) Un LIKE qui commence par % : l'index sert encore à trouver le code postal
--    (Seek sur '79000'), mais il faut ensuite lire TOUTES les adresses de Niort
--    pour tester le nom de voie. Comparez les lectures avec la requête 1.3.
SELECT  Numero, NomVoie, Latitude, Longitude
FROM    dbo.Adresse
WHERE   CodePostal = '79000'
  AND   NomVoie LIKE N'%Hugo%';
GO

/*==============================================================================
  PARTIE 2 : LA BOUTIQUE, UNE CLÉ ÉTRANGÈRE SANS INDEX
  Question du service commercial : « combien a-t-on vendu de tel produit ? »
  ventes.LigneCommande.IdProduit est une clé étrangère... sans index.
==============================================================================*/
USE Boutique;
GO

-- Un produit qui se vend peu, et un best-seller.
SELECT IdProduit, COUNT(*) AS NbLignes
FROM   ventes.LigneCommande
WHERE  IdProduit IN (1, 1999)
GROUP BY IdProduit;
GO

-- 2.1 Sans index : parcours complet de l'index cluster (Clustered Index Scan),
--     toutes les lignes de commande sont lues pour en garder quelques centaines.
SELECT  p.Reference, p.Nom,
        SUM(l.Quantite)                    AS QuantiteVendue,
        SUM(l.Quantite * l.PrixUnitaireHT) AS CA_HT
FROM        ventes.LigneCommande l
INNER JOIN  ventes.Produit       p ON p.IdProduit = l.IdProduit
WHERE   l.IdProduit = 1999
GROUP BY p.Reference, p.Nom;
GO

-- 2.2 Un index « simple » sur la clé étrangère.
CREATE INDEX IX_LigneCommande_Produit
    ON ventes.LigneCommande (IdProduit);
GO

-- 2.3 Même requête : Index Seek... suivi d'un KEY LOOKUP.
--     L'index trouve les lignes, mais Quantite et PrixUnitaireHT n'y sont pas :
--     pour CHAQUE ligne trouvée, SQL Server retourne chercher dans la table.
SELECT  p.Reference, p.Nom,
        SUM(l.Quantite)                    AS QuantiteVendue,
        SUM(l.Quantite * l.PrixUnitaireHT) AS CA_HT
FROM        ventes.LigneCommande l
INNER JOIN  ventes.Produit       p ON p.IdProduit = l.IdProduit
WHERE   l.IdProduit = 1999
GROUP BY p.Reference, p.Nom;
GO

-- 2.4 Et pour le best-seller ? Trop de lignes : faire des milliers de Key Lookup
--     coûterait plus cher que tout lire. L'optimiseur IGNORE notre index et
--     repart sur un scan. C'est le « point de bascule » (tipping point).
SELECT  p.Reference, p.Nom,
        SUM(l.Quantite)                    AS QuantiteVendue,
        SUM(l.Quantite * l.PrixUnitaireHT) AS CA_HT
FROM        ventes.LigneCommande l
INNER JOIN  ventes.Produit       p ON p.IdProduit = l.IdProduit
WHERE   l.IdProduit = 1
GROUP BY p.Reference, p.Nom;
GO

-- 2.5 La solution : un index COUVRANT. On reconstruit le même index en
--     embarquant les colonnes utiles (DROP_EXISTING : en une seule opération).
CREATE INDEX IX_LigneCommande_Produit
    ON ventes.LigneCommande (IdProduit)
    INCLUDE (Quantite, PrixUnitaireHT)
    WITH (DROP_EXISTING = ON);
GO

-- 2.6 Les deux requêtes : Index Seek, plus de Key Lookup, même pour le best-seller.
SELECT  p.Reference, p.Nom,
        SUM(l.Quantite)                    AS QuantiteVendue,
        SUM(l.Quantite * l.PrixUnitaireHT) AS CA_HT
FROM        ventes.LigneCommande l
INNER JOIN  ventes.Produit       p ON p.IdProduit = l.IdProduit
WHERE   l.IdProduit = 1999
GROUP BY p.Reference, p.Nom;

SELECT  p.Reference, p.Nom,
        SUM(l.Quantite)                    AS QuantiteVendue,
        SUM(l.Quantite * l.PrixUnitaireHT) AS CA_HT
FROM        ventes.LigneCommande l
INNER JOIN  ventes.Produit       p ON p.IdProduit = l.IdProduit
WHERE   l.IdProduit = 1
GROUP BY p.Reference, p.Nom;
GO

/*==============================================================================
  PARTIE 3 : CE QUE SQL SERVER NOUS SUGGÈRE (DMV des index manquants)
  SQL Server note en permanence les index qui lui auraient été utiles.
  C'est une piste, pas une vérité : on réfléchit avant de tout créer.
==============================================================================*/
SELECT  DB_NAME(d.database_id)                    AS Base,
        d.statement                               AS TableConcernee,
        d.equality_columns, d.inequality_columns, d.included_columns,
        s.user_seeks,
        CAST(s.avg_user_impact AS DECIMAL(5,1))   AS GainEstimePourcent
FROM        sys.dm_db_missing_index_details     d
INNER JOIN  sys.dm_db_missing_index_groups      g ON g.index_handle = d.index_handle
INNER JOIN  sys.dm_db_missing_index_group_stats s ON s.group_handle = g.index_group_handle
WHERE   d.database_id IN (DB_ID(N'Boutique'), DB_ID(N'Geo'))
ORDER BY s.avg_user_impact * s.user_seeks DESC;
GO

SET STATISTICS IO, TIME OFF;
GO
