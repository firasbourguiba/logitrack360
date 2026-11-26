select
    date_id,
    jour,
    mois,
    annee,
    jour_semaine,
    nom_jour,
    est_weekend
from {{ ref('stg_dates') }}
