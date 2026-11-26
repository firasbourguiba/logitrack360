-- Test de coherence : la table de faits doit avoir autant de lignes que le staging des operations.
-- Echoue si une jointure a perdu ou duplique des lignes.
with f as (select count(*) as nb from {{ ref('fct_operations') }}),
     s as (select count(*) as nb from {{ ref('stg_logitrack__operations') }})
select f.nb as lignes_fait, s.nb as lignes_staging
from f, s
where f.nb <> s.nb
