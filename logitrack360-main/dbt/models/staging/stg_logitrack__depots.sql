-- Une ligne par depot.
select
    cast(depot_id as varchar) as depot_id,
    trim(nom_depot) as nom_depot,
    upper(trim(type_hub)) as type_hub,
    cast(zone_id as varchar) as zone_id
from {{ source('logitrack', 'depots') }}
