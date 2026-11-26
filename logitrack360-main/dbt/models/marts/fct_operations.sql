-- Table de faits : une ligne par operation, mesures + cles vers les 4 dimensions.
select
    operation_id,
    order_id,
    type_operation,
    date_id,
    zone_id,
    depot_id,
    livreur_id,
    duree_minutes,
    est_en_retard,
    heure_debut,
    heure_fin,
    heure_promise
from {{ ref('stg_operations') }}
