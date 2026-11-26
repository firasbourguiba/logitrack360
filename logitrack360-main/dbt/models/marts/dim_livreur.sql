{{ config(post_hook="alter table {{ this }} add primary key (livreur_key)") }}
-- Version courante de chaque livreur. L'historique des changements est dans snap_livreurs (SCD2).
select
    md5(l.livreur_id) as livreur_key,
    l.livreur_id,
    l.statut,
    z.nom_zone as ville_affiliation
from {{ ref('stg_logitrack__livreurs') }} l
left join {{ ref('stg_logitrack__zones') }} z on z.zone_id = l.zone_affiliation_id
