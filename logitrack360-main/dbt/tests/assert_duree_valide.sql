-- Test metier : une duree est positive ou nulle et ne depasse pas 24 h (1 440 minutes).
-- Echoue pour toute duree negative ou superieure a 1 440 minutes.
select *
from {{ ref('fct_operations') }}
where duree_minutes < 0
   or duree_minutes > 1440
