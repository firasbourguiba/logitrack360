-- Hierarchie geographique aplatie : quartier, ville et pays deviennent des colonnes.
select
    z.zone_id,
    case when z.niveau = 'QUARTIER_AOI' then z.nom_zone end as quartier,
    coalesce(v.nom_zone, case when z.niveau = 'VILLE' then z.nom_zone end) as ville,
    'Chine' as pays,
    z.niveau
from {{ ref('stg_zones') }} z
left join {{ ref('stg_zones') }} v
    on v.zone_id = z.parent_zone_id and v.niveau = 'VILLE'
where z.niveau <> 'PAYS'
