{{ config(post_hook="alter table {{ this }} add primary key (date_key)") }}
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
