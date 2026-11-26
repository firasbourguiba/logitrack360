-- Projet LogiTrack 360 - 3 questions metier sur le schema en etoile (schema dbt_marts)
-- Table de faits : fct_operations (grain : une operation). Dimensions : dim_date, dim_zone,
-- dim_depot, dim_livreur. Chaque requete n'utilise qu'une jointure par axe d'analyse.

-- Q1. Quel est le taux de retard des ramassages, par ville et par mois ?
-- (seuls les ramassages ont une heure promise, donc seuls eux peuvent etre en retard)
select z.ville, d.annee, d.mois,
       count(*) as nb_ramassages,
       round(100.0 * avg(f.est_en_retard::int), 2) as pct_retard
from dbt_marts.fct_operations f
join dbt_marts.dim_zone z using (zone_key)
join dbt_marts.dim_date d using (date_key)
where f.type_operation = 'RAMASSAGE'
group by z.ville, d.annee, d.mois
order by z.ville, d.annee, d.mois;

-- Q2. Quels sont les livreurs les plus rapides (au moins 200 operations) ?
select l.livreur_id, l.ville_affiliation,
       count(*) as nb_ops,
       round(avg(f.duree_minutes), 1) as duree_moy_min
from dbt_marts.fct_operations f
join dbt_marts.dim_livreur l using (livreur_key)
where f.duree_minutes is not null
group by l.livreur_id, l.ville_affiliation
having count(*) >= 200
order by duree_moy_min
limit 10;

-- Q3. Quels jours de la semaine sont les plus charges, et les operations y sont-elles plus longues ?
select d.jour_semaine, d.nom_jour,
       count(*) as nb_ops,
       round(avg(f.duree_minutes), 1) as duree_moy_min
from dbt_marts.fct_operations f
join dbt_marts.dim_date d using (date_key)
group by d.jour_semaine, d.nom_jour
order by d.jour_semaine;
