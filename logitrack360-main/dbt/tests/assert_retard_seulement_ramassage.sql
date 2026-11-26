-- Test metier : seuls les ramassages ont une heure promise, donc seuls eux peuvent etre en retard.
-- Echoue si une livraison est marquee en retard.
select *
from {{ ref('fct_operations') }}
where est_en_retard
  and type_operation <> 'RAMASSAGE'
