-- Projet LogiTrack 360 - Index et benchmark (EXPLAIN ANALYZE)
-- Mesures faites sur public.colis_operations (~10,65 M lignes).
-- Methode : 1) lancer chaque EXPLAIN AVANT les index, noter le temps
--           2) creer les index  3) relancer les memes EXPLAIN, comparer.

-- A. Requetes a mesurer (a lancer AVANT puis APRES les index)

-- A1. Filtre sur une cle etrangere (retards d'un depot)
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), AVG(duree_minutes)
FROM colis_operations
WHERE depot_id = 'sh_R53' AND est_en_retard;

-- A2. Historique d'un livreur
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_id, COUNT(*), AVG(duree_minutes)
FROM colis_operations
WHERE livreur_id = 'cq_C73'
GROUP BY date_id ORDER BY date_id;

-- A3. Filtre sur un type + un jour
EXPLAIN (ANALYZE, BUFFERS)
SELECT zone_id, COUNT(*)
FROM colis_operations
WHERE type_operation = 'RAMASSAGE' AND date_id = '2023-09-15'
GROUP BY zone_id;

-- A4. JOINTURE + FENETRE : rang de chaque operation du jour dans le depot sh_R53
--     (question metier : quelles operations sont les plus longues chaque jour ?)
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.date_id, o.livreur_id, l.zone_affiliation_id, o.duree_minutes,
       RANK() OVER (PARTITION BY o.date_id ORDER BY o.duree_minutes DESC) AS rang_jour
FROM colis_operations o
JOIN livreurs l ON l.livreur_id = o.livreur_id
WHERE o.depot_id = 'sh_R53' AND o.duree_minutes IS NOT NULL;

-- B. Creation des index

-- Index sur les cles etrangères (jointures et filtres)
CREATE INDEX IF NOT EXISTS idx_ops_depot    ON colis_operations (depot_id);
CREATE INDEX IF NOT EXISTS idx_ops_livreur  ON colis_operations (livreur_id);
CREATE INDEX IF NOT EXISTS idx_ops_zone     ON colis_operations (zone_id);

-- Index composite : type + date (A3)
CREATE INDEX IF NOT EXISTS idx_ops_type_date ON colis_operations (type_operation, date_id);

-- Index partiel : uniquement les operations en retard (petit et tres selectif)
CREATE INDEX IF NOT EXISTS idx_ops_retard ON colis_operations (depot_id) WHERE est_en_retard;

-- Index sur la hierarchie geographique (CTE recursive)
CREATE INDEX IF NOT EXISTS idx_zones_parent ON zones_geo (parent_zone_id);

ANALYZE colis_operations;
ANALYZE zones_geo;

-- C. Relancer A1, A2, A3 et noter les nouveaux temps dans docs/rapport_performance.md
