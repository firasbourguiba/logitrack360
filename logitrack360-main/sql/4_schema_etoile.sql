-- Projet LogiTrack 360 - Schema en etoile (couche "marts")
-- Question metier : ou, quand et par qui les operations de livraison / ramassage
-- sont-elles en retard ou lentes ?
--
-- Le schema relationnel (0_creation_schema.sql, normalise) reste la couche "staging".
-- Ici on construit le modele dimensionnel : 1 table de faits + dimensions AUTONOMES
-- (aucune dimension ne pointe vers une autre dimension).
-- Equivalent des futurs modeles dbt : dim_*.sql et fct_operations.sql

DROP SCHEMA IF EXISTS mart CASCADE;
CREATE SCHEMA mart;

-- Dimension temps
CREATE TABLE mart.dim_date AS
SELECT date_id, jour, mois, annee, jour_semaine, nom_jour, est_weekend
FROM dim_dates;
ALTER TABLE mart.dim_date ADD PRIMARY KEY (date_id);

-- Dimension geographique APLATIE (la hierarchie Pays > Ville > Quartier devient des colonnes)
CREATE TABLE mart.dim_zone AS
SELECT
    z.zone_id,
    CASE WHEN z.niveau = 'QUARTIER_AOI' THEN z.nom_zone END AS quartier,
    COALESCE(v.nom_zone, CASE WHEN z.niveau = 'VILLE' THEN z.nom_zone END) AS ville,
    'Chine' AS pays,
    z.niveau
FROM zones_geo z
LEFT JOIN zones_geo v ON v.zone_id = z.parent_zone_id AND v.niveau = 'VILLE'
WHERE z.niveau <> 'PAYS';
ALTER TABLE mart.dim_zone ADD PRIMARY KEY (zone_id);

-- Dimension depot (ville recopiee : pas de lien vers dim_zone)
CREATE TABLE mart.dim_depot AS
SELECT d.depot_id, d.nom_depot, d.type_hub, z.nom_zone AS ville
FROM depots d
JOIN zones_geo z ON z.zone_id = d.zone_id;
ALTER TABLE mart.dim_depot ADD PRIMARY KEY (depot_id);

-- Dimension livreur
CREATE TABLE mart.dim_livreur AS
SELECT l.livreur_id, l.statut, z.nom_zone AS ville_affiliation
FROM livreurs l
LEFT JOIN zones_geo z ON z.zone_id = l.zone_affiliation_id;
ALTER TABLE mart.dim_livreur ADD PRIMARY KEY (livreur_id);

-- Table de faits : 1 ligne = 1 operation ; mesures + cles vers les 4 dimensions
CREATE TABLE mart.fct_operations AS
SELECT
    operation_id,
    order_id,
    type_operation,          -- dimension degeneree
    date_id,
    zone_id,
    depot_id,
    livreur_id,
    duree_minutes,           -- mesures
    est_en_retard,
    heure_debut,
    heure_fin,
    heure_promise
FROM colis_operations;
ALTER TABLE mart.fct_operations ADD PRIMARY KEY (operation_id);
ALTER TABLE mart.fct_operations
    ADD FOREIGN KEY (date_id)    REFERENCES mart.dim_date(date_id),
    ADD FOREIGN KEY (zone_id)    REFERENCES mart.dim_zone(zone_id),
    ADD FOREIGN KEY (depot_id)   REFERENCES mart.dim_depot(depot_id),
    ADD FOREIGN KEY (livreur_id) REFERENCES mart.dim_livreur(livreur_id);

CREATE INDEX ON mart.fct_operations (date_id);
CREATE INDEX ON mart.fct_operations (zone_id);
CREATE INDEX ON mart.fct_operations (depot_id);
CREATE INDEX ON mart.fct_operations (livreur_id);

-- Exemple : taux de retard par ville et par mois
-- SELECT z.ville, d.annee, d.mois, COUNT(*) nb, ROUND(100.0*AVG(est_en_retard::int),1) pct_retard
-- FROM mart.fct_operations f
-- JOIN mart.dim_zone z USING (zone_id) JOIN mart.dim_date d USING (date_id)
-- WHERE f.type_operation = 'RAMASSAGE' GROUP BY 1,2,3 ORDER BY 1,2,3;
