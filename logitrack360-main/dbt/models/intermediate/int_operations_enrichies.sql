-- Une ligne par operation, enrichie du contexte geographique (ville, quartier).
-- Les jointures se font sur des cles uniques : le nombre de lignes reste celui du staging.
select
    o.operation_id,
    o.order_id,
    o.type_operation,
    o.date_jour,
    o.zone_id,
    o.depot_id,
    o.livreur_id,
    o.heure_debut,
    o.heure_fin,
    o.heure_promise,
    o.duree_minutes,
    o.est_en_retard,
    case when z.niveau = 'QUARTIER_AOI' then z.nom_zone end as quartier,
    coalesce(v.nom_zone, case when z.niveau = 'VILLE' then z.nom_zone end) as ville
from {{ ref('stg_logitrack__operations') }} o
join {{ ref('stg_logitrack__zones') }} z on z.zone_id = o.zone_id
left join {{ ref('stg_logitrack__zones') }} v
    on v.zone_id = z.parent_zone_id and v.niveau = 'VILLE'
