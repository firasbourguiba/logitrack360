select
    zone_id,
    nom_zone,
    niveau,
    parent_zone_id
from {{ source('logitrack', 'zones_geo') }}
