-- Une ligne par operation (livraison ou ramassage). Colonnes geographiques GPS exclues.
select
    operation_id,
    cast(order_id as varchar) as order_id,
    upper(trim(type_operation)) as type_operation,
    cast(date_id as date) as date_jour,
    cast(zone_id as varchar) as zone_id,
    cast(depot_id as varchar) as depot_id,
    cast(livreur_id as varchar) as livreur_id,
    heure_debut,
    heure_fin,
    heure_promise,
    duree_minutes,
    coalesce(est_en_retard, false) as est_en_retard
from {{ source('logitrack', 'colis_operations') }}
