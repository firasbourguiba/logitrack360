select
    livreur_id,
    zone_affiliation_id,
    statut
from {{ source('logitrack', 'livreurs') }}
