select
    depot_id,
    nom_depot,
    type_hub,
    zone_id
from {{ source('logitrack', 'depots') }}
