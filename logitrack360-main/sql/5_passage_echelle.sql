-- Projet LogiTrack 360 - Passage a l'echelle (x3, environ 32 M de lignes)
-- Etape 1 de la consigne : multiplier les donnees. On copie colis_operations en 3 exemplaires dans
-- une table separee, en decalant les identifiants et les dates (+365 et +730 jours), sans toucher
-- a la table d'origine.
-- Etapes 2 a 4 : memes requetes A1, A3, A4 que dans 3_index.sql, mesurees sur la nouvelle table
-- sans index puis avec index.
-- Prevoir environ 3 Go d'espace disque pour les donnees et environ 2 Go pour les index.

-- 0. Taille de depart (a noter dans le rapport)
SELECT pg_size_pretty(pg_total_relation_size('colis_operations')) AS taille_origine,
       (SELECT COUNT(*) FROM colis_operations) AS lignes_origine;

-- 1. Creation et remplissage (plusieurs minutes)
DROP TABLE IF EXISTS colis_operations_x3;
CREATE TABLE colis_operations_x3 (LIKE colis_operations INCLUDING DEFAULTS);
ALTER TABLE colis_operations_x3 ALTER COLUMN operation_id DROP DEFAULT;

INSERT INTO colis_operations_x3
    (operation_id, order_id, type_operation, depot_id, livreur_id, zone_id, date_id,
     heure_debut, heure_fin, heure_promise, duree_minutes, est_en_retard,
     typecode, poi_lng, poi_lat, gps_lng, gps_lat)
SELECT
    o.operation_id + k * 20000000,
    CASE WHEN k = 0 THEN o.order_id ELSE o.order_id || '_' || k END,
    o.type_operation, o.depot_id, o.livreur_id, o.zone_id,
    o.date_id + k * 365,
    o.heure_debut   + make_interval(days => k * 365),
    o.heure_fin     + make_interval(days => k * 365),
    o.heure_promise + make_interval(days => k * 365),
    o.duree_minutes, o.est_en_retard,
    o.typecode, o.poi_lng, o.poi_lat, o.gps_lng, o.gps_lat
FROM colis_operations o
CROSS JOIN generate_series(0, 2) AS k;

ALTER TABLE colis_operations_x3 ADD PRIMARY KEY (operation_id);
ANALYZE colis_operations_x3;

-- 2. Controles : 3 fois le nombre de lignes, dates toutes presentes dans dim_dates
SELECT COUNT(*) AS lignes_x3 FROM colis_operations_x3;
SELECT COUNT(*) AS dates_absentes
FROM colis_operations_x3 x
LEFT JOIN dim_dates d ON d.date_id = x.date_id
WHERE d.date_id IS NULL;
SELECT pg_size_pretty(pg_total_relation_size('colis_operations_x3')) AS taille_x3;

-- 3. Mesures SANS index (a lancer 3 fois chacune, noter l'Execution Time et le type de scan)
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), AVG(duree_minutes)
FROM colis_operations_x3
WHERE depot_id = 'sh_R53' AND est_en_retard;

EXPLAIN (ANALYZE, BUFFERS)
SELECT zone_id, COUNT(*)
FROM colis_operations_x3
WHERE type_operation = 'RAMASSAGE' AND date_id = '2023-09-15'
GROUP BY zone_id;

EXPLAIN (ANALYZE, BUFFERS)
SELECT o.date_id, o.livreur_id, l.zone_affiliation_id, o.duree_minutes,
       RANK() OVER (PARTITION BY o.date_id ORDER BY o.duree_minutes DESC) AS rang_jour
FROM colis_operations_x3 o
JOIN livreurs l ON l.livreur_id = o.livreur_id
WHERE o.depot_id = 'sh_R53' AND o.duree_minutes IS NOT NULL;

-- 4. Creation des index (a lancer en un seul bloc ; verifier ensuite avec pg_indexes)
CREATE INDEX IF NOT EXISTS idx_x3_depot     ON colis_operations_x3 (depot_id);
CREATE INDEX IF NOT EXISTS idx_x3_livreur   ON colis_operations_x3 (livreur_id);
CREATE INDEX IF NOT EXISTS idx_x3_zone      ON colis_operations_x3 (zone_id);
CREATE INDEX IF NOT EXISTS idx_x3_type_date ON colis_operations_x3 (type_operation, date_id);
CREATE INDEX IF NOT EXISTS idx_x3_retard    ON colis_operations_x3 (depot_id) WHERE est_en_retard;
ANALYZE colis_operations_x3;

SELECT indexname, pg_size_pretty(pg_relation_size(indexname::regclass)) AS taille
FROM pg_indexes WHERE tablename = 'colis_operations_x3';

-- 5. Mesures AVEC index : relancer les 3 requetes de l'etape 3, 3 fois chacune.

-- 6. Nettoyage si besoin de liberer l'espace disque
-- DROP TABLE colis_operations_x3;
