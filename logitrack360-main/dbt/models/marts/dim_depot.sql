-- La ville est recopiee dans la dimension : pas de lien vers dim_zone (schema en etoile).
select
    d.depot_id,
    d.nom_depot,
    d.type_hub,
    z.nom_zone as ville
from {{ ref('stg_depots') }} d
join {{ ref('stg_zones') }} z on z.zone_id = d.zone_id
