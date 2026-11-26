-- grain : une operation (une livraison ou un ramassage)
select
    operation_id,
    order_id,
    type_operation,
    cast(to_char(date_jour, 'YYYYMMDD') as int) as date_key,
    md5(zone_id) as zone_key,
    md5(depot_id) as depot_key,
    md5(livreur_id) as livreur_key,
    duree_minutes,
    est_en_retard,
    heure_debut,
    heure_fin,
    heure_promise
from {{ ref('int_operations_enrichies') }}
