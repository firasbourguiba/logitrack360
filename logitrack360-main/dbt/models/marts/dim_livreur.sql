select
    l.livreur_id,
    l.statut,
    z.nom_zone as ville_affiliation
from {{ ref('stg_livreurs') }} l
left join {{ ref('stg_zones') }} z on z.zone_id = l.zone_affiliation_id
