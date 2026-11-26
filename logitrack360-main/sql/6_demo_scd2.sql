-- Projet LogiTrack 360 - Demonstration du SCD2 (snapshot dbt sur les livreurs)
-- Ordre : 1) dbt snapshot   2) ce script, partie A   3) dbt snapshot   4) partie B   5) partie C pour remettre
-- la base dans son etat d'origine.
-- Le snapshot est cree dans le schema dbt_snapshots, table snap_livreurs.

-- A. Simuler un changement : le livreur cq_C73 passe en conge, cq_C3706 est desactive
UPDATE livreurs SET statut = 'EN_CONGE' WHERE livreur_id = 'cq_C73';
UPDATE livreurs SET statut = 'INACTIF'  WHERE livreur_id = 'cq_C3706';
-- (puis relancer : dbt snapshot --profiles-dir .)

-- B. Lire l'historique : 2 lignes par livreur modifie
SELECT livreur_id, statut, dbt_valid_from, dbt_valid_to,
       CASE WHEN dbt_valid_to IS NULL THEN 'courante' ELSE 'historique' END AS version
FROM dbt_snapshots.snap_livreurs
WHERE livreur_id IN ('cq_C73', 'cq_C3706')
ORDER BY livreur_id, dbt_valid_from;

-- Etat du livreur cq_C73 AVANT le changement : on se place une seconde avant la fermeture
-- de l'ancienne version. Resultat attendu : ACTIF.
WITH t AS (
    SELECT MIN(dbt_valid_to) - interval '1 second' AS instant
    FROM dbt_snapshots.snap_livreurs
    WHERE livreur_id = 'cq_C73'
)
SELECT s.livreur_id, s.statut, t.instant
FROM dbt_snapshots.snap_livreurs s, t
WHERE s.livreur_id = 'cq_C73'
  AND s.dbt_valid_from <= t.instant
  AND (s.dbt_valid_to IS NULL OR s.dbt_valid_to > t.instant);

-- Etat actuel du meme livreur : les lignes sans dbt_valid_to. Resultat attendu : EN_CONGE.
SELECT livreur_id, statut
FROM dbt_snapshots.snap_livreurs
WHERE livreur_id = 'cq_C73' AND dbt_valid_to IS NULL;

-- C. Remise a l'etat d'origine de la table source (le snapshot garde son historique)
UPDATE livreurs SET statut = 'ACTIF' WHERE livreur_id IN ('cq_C73', 'cq_C3706');
