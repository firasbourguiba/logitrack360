select
    cast(to_char(date_jour, 'YYYYMMDD') as int) as date_key,
    date_jour,
    jour,
    mois,
    annee,
    jour_semaine,
    nom_jour,
    est_weekend
from {{ ref('stg_logitrack__dates') }}
