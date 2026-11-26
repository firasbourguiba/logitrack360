{{ config(post_hook="alter table {{ this }} add primary key (depot_key)") }}
-- La ville est recopiee dans la dimension : pas de lien vers dim_zone (schema en etoile).
select
    md5(d.depot_id) as depot_key,
    d.depot_id,
    d.nom_depot,
    d.type_hub,
    z.nom_zone as ville
from {{ ref('stg_logitrack__depots') }} d
join {{ ref('stg_logitrack__zones') }} z on z.zone_id = d.zone_id
