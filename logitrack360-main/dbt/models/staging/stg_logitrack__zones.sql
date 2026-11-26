-- Une ligne par zone geographique. Aucune jointure, aucune agregation.
select
    cast(zone_id as varchar) as zone_id,
    trim(nom_zone) as nom_zone,
    upper(trim(niveau)) as niveau,
    cast(parent_zone_id as varchar) as parent_zone_id
from {{ source('logitrack', 'zones_geo') }}
