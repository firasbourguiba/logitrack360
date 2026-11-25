-- Projet LogiTrack 360 - Requetes avancees
-- Question metier : "La bataille du dernier kilometre"

-- ============================================================
-- Q1. RANK : classement des livreurs par ville selon leur duree moyenne
--     (au moins 200 operations pour eviter les petits echantillons)
-- ============================================================
WITH perf AS (
    SELECT l.zone_affiliation_id AS ville,
           o.livreur_id,
           COUNT(*)                       AS nb_ops,
           ROUND(AVG(o.duree_minutes), 1) AS duree_moy
    FROM colis_operations o
    JOIN livreurs l ON l.livreur_id = o.livreur_id
    WHERE o.duree_minutes IS NOT NULL
    GROUP BY l.zone_affiliation_id, o.livreur_id
    HAVING COUNT(*) >= 200
)
SELECT ville, livreur_id, nb_ops, duree_moy,
       RANK() OVER (PARTITION BY ville ORDER BY duree_moy) AS rang_ville
FROM perf
ORDER BY ville, rang_ville
LIMIT 50;

-- ============================================================
-- Q2. NTILE : livreurs d'elite (quartile 1) vs en difficulte (quartile 4)
-- ============================================================
WITH perf AS (
    SELECT livreur_id, COUNT(*) AS nb_ops, AVG(duree_minutes) AS duree_moy
    FROM colis_operations
    WHERE duree_minutes IS NOT NULL
    GROUP BY livreur_id
    HAVING COUNT(*) >= 200
)
SELECT NTILE(4) OVER (ORDER BY duree_moy) AS quartile,
       COUNT(*)                         AS nb_livreurs,
       ROUND(AVG(duree_moy), 1)         AS duree_moy_groupe
FROM perf
GROUP BY 1 ORDER BY 1;
-- (version par livreur : remplacer le GROUP BY par un SELECT livreur_id, NTILE(4) OVER (...) FROM perf)

-- ============================================================
-- Q3. Ponctualite : taux de retard des RAMASSAGES par ville
--     (seuls les ramassages ont une heure promise : time_window_end)
-- ============================================================
SELECT z.parent_zone_id AS ville,
       COUNT(*) AS nb_ramassages,
       ROUND(100.0 * AVG(o.est_en_retard::int), 2) AS pct_retard
FROM colis_operations o
JOIN zones_geo z ON z.zone_id = o.zone_id
WHERE o.type_operation = 'RAMASSAGE' AND o.heure_promise IS NOT NULL
GROUP BY z.parent_zone_id
ORDER BY pct_retard DESC;

-- ============================================================
-- Q4. LAG : evolution quotidienne du volume (Shanghai) et variation vs veille
-- ============================================================
WITH jour AS (
    SELECT o.date_id, COUNT(*) AS nb_ops
    FROM colis_operations o
    JOIN zones_geo z ON z.zone_id = o.zone_id
    WHERE z.parent_zone_id = 'Shanghai' OR z.zone_id = 'Shanghai'
    GROUP BY o.date_id
)
SELECT date_id, nb_ops,
       LAG(nb_ops) OVER (ORDER BY date_id) AS nb_veille,
       nb_ops - LAG(nb_ops) OVER (ORDER BY date_id) AS variation,
       ROUND(AVG(nb_ops) OVER (ORDER BY date_id ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 0) AS moy_mobile_7j
FROM jour
ORDER BY date_id;

-- ============================================================
-- Q5. Heures de saturation : operations par heure de la journee et par depot (top 3 depots)
-- ============================================================
WITH top_depots AS (
    SELECT depot_id FROM colis_operations GROUP BY depot_id ORDER BY COUNT(*) DESC LIMIT 3
)
SELECT o.depot_id,
       EXTRACT(HOUR FROM o.heure_debut)::int AS heure,
       COUNT(*) AS nb_ops,
       RANK() OVER (PARTITION BY o.depot_id ORDER BY COUNT(*) DESC) AS rang_heure
FROM colis_operations o
JOIN top_depots t USING (depot_id)
WHERE o.heure_debut IS NOT NULL
GROUP BY o.depot_id, EXTRACT(HOUR FROM o.heure_debut)
ORDER BY o.depot_id, rang_heure;

-- ============================================================
-- Q6. CTE RECURSIVE : parcours de la hierarchie Pays > Ville > Quartier
--     avec le nombre de quartiers par noeud
-- ============================================================
WITH RECURSIVE arbre AS (
    SELECT zone_id, nom_zone, niveau, parent_zone_id,
           0 AS profondeur, nom_zone::text AS chemin
    FROM zones_geo
    WHERE parent_zone_id IS NULL
  UNION ALL
    SELECT z.zone_id, z.nom_zone, z.niveau, z.parent_zone_id,
           a.profondeur + 1, a.chemin || ' > ' || z.nom_zone
    FROM zones_geo z
    JOIN arbre a ON z.parent_zone_id = a.zone_id
)
SELECT profondeur, niveau, COUNT(*) AS nb_noeuds
FROM arbre
GROUP BY profondeur, niveau
ORDER BY profondeur;

-- Variante : nombre d'operations remontees jusqu'a chaque ville
WITH RECURSIVE remonte AS (
    SELECT o.operation_id, o.zone_id, z.parent_zone_id, z.niveau
    FROM colis_operations o
    JOIN zones_geo z ON z.zone_id = o.zone_id
  UNION ALL
    SELECT r.operation_id, z.zone_id, z.parent_zone_id, z.niveau
    FROM remonte r
    JOIN zones_geo z ON z.zone_id = r.parent_zone_id
)
SELECT zone_id AS ville, COUNT(DISTINCT operation_id) AS nb_ops
FROM remonte
WHERE niveau = 'VILLE'
GROUP BY zone_id
ORDER BY nb_ops DESC;
-- Attention : cette variante parcourt 10,6 M de lignes, elle est lente sans filtre
-- (a mesurer avec EXPLAIN ANALYZE, ou limiter avec WHERE o.date_id = '2023-09-01').
