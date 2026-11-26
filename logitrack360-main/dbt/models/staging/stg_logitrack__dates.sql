-- Une ligne par jour du calendrier.
select
    cast(date_id as date) as date_jour,
    jour,
    mois,
    annee,
    jour_semaine,
    trim(nom_jour) as nom_jour,
    est_weekend
from {{ source('logitrack', 'dim_dates') }}
