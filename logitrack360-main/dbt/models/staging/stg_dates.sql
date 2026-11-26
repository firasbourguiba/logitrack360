select
    date_id,
    jour,
    mois,
    annee,
    jour_semaine,
    nom_jour,
    est_weekend
from {{ source('logitrack', 'dim_dates') }}
