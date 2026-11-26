select
    operation_id,
    order_id,
    type_operation,
    date_id,
    zone_id,
    depot_id,
    livreur_id,
    heure_debut,
    heure_fin,
    heure_promise,
    duree_minutes,
    est_en_retard
from {{ source('logitrack', 'colis_operations') }}
