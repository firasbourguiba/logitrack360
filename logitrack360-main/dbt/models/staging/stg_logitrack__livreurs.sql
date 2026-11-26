-- Une ligne par livreur.
select
    cast(livreur_id as varchar) as livreur_id,
    cast(zone_affiliation_id as varchar) as zone_affiliation_id,
    upper(trim(statut)) as statut
from {{ source('logitrack', 'livreurs') }}
