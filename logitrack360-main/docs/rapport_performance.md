# Rapport de performance - LogiTrack 360

Table testée : `colis_operations`, 10 650 808 lignes (4 514 661 livraisons, 6 136 147 ramassages).
Environnement : PostgreSQL 18, pgAdmin, machine locale.
Protocole : `EXPLAIN (ANALYZE, BUFFERS)`, chaque requête lancée plusieurs fois sans index puis avec index ;
on retient la **médiane**. Les requêtes sont dans `sql/3_index.sql`.

## Index créés

| Index | Définition |
|---|---|
| `idx_ops_depot` | `(depot_id)` |
| `idx_ops_livreur` | `(livreur_id)` |
| `idx_ops_zone` | `(zone_id)` |
| `idx_ops_type_date` | `(type_operation, date_id)` composite |
| `idx_ops_retard` | `(depot_id) WHERE est_en_retard` partiel |
| `idx_zones_parent` | `zones_geo(parent_zone_id)` |

Création : environ 1 min 20 s pour les 5 index de `colis_operations`.

## Résultats

| Requête | Sans index (médiane, ms) | Plan sans index | Avec index (médiane, ms) | Plan avec index | Gain |
|---|---|---|---|---|---|
| A1 - retards du dépôt `sh_R53` (5 589 lignes) | 812 (5 mesures) | Parallel Seq Scan | 2,1 (3 mesures) | Index Scan `idx_ops_retard` | x380 |
| A4 - **jointure + RANK()**, dépôt `sh_R53` (32 288 lignes) | 935 (3 mesures) | Parallel Seq Scan + Hash Join | environ 75 (3 mesures) | Index Scan `idx_ops_depot` + Hash Join | x12 |
| A3 - ramassages du 2023-09-15 (33 538 lignes) | 887 (5 mesures) | Parallel Seq Scan | 493 (3 mesures) | Index Scan `idx_ops_type_date` | x1,8 |
| A2 - historique du livreur `cq_C73` (1 209 lignes) | 2 488 / 2 714 | Parallel Seq Scan | environ 7 (1 mesure) | Index Scan `idx_ops_livreur` | x350 |

Toutes les mesures :
- A1 sans index : 923, 822, 812, 715, 789 ms ; avec index : 2,38 / 2,12 / 1,95 ms.
- A3 sans index : 927, 907, 887, 867, 840 ms ; avec index : 2 087 (cache froid) / 493 / 365 ms.
- A4 sans index : 2 708 (cache froid) / 929 / 935 ms ; avec index : 79 ms, puis environ 69 et 75 ms.
  Pour les deux dernières, le temps total n'était pas visible : on retient la fin du nœud `WindowAgg`
  (68,5 et 75,3 ms), légèrement inférieure au temps total.
- A2 : mesures initiales, une seule par état ; elle sert d'illustration, pas de benchmark.

## Interprétation

**A1 - gain très net (x380).** Sans index, PostgreSQL lit toute la table (`Parallel Seq Scan`,
environ 183 000 pages, soit 1,4 Go) et écarte 3,5 millions de lignes pour n'en garder que 5 589
(0,05 %). Avec l'index partiel `idx_ops_retard`, il lit directement les lignes utiles :
583 pages, toutes déjà en cache. L'index partiel ne contient que les opérations en retard : il est
bien plus petit qu'un index complet sur `depot_id`, et le filtre `est_en_retard` est inclus dans l'index.

**A4 - jointure + fonction de fenêtre (x12).** Le plan garde la même forme : filtre,
`Hash Join` avec `livreurs`, `Sort`, puis `WindowAgg`. La différence vient de l'accès à
`colis_operations` : `Parallel Seq Scan` (3,5 millions de lignes écartées) remplacé par un
`Index Scan` sur `idx_ops_depot`. Le gain est plus faible que pour A1 parce que le reste du travail
ne dépend pas de l'index : lecture de `livreurs` (19 679 lignes), tri de 32 288 lignes
(environ 40 ms) et calcul de la fenêtre. Après l'index, le tri devient le poste principal.

**A3 - gain modeste (x1,8).** L'index est utilisé, mais le gain est limité. Le jour visé contient
33 538 lignes réparties sur environ 25 400 pages : la table n'est pas triée par date, donc chaque
ligne demande une lecture disque dispersée. Les mesures le montrent : 2 087 ms à froid, puis 493 et
365 ms une fois les pages en cache, alors que le parcours complet reste autour de 850 ms.
Un index n'est donc rentable que si le filtre est très sélectif ou si les lignes recherchées sont
proches sur le disque. Pistes (non testées) : index couvrant
`(type_operation, date_id) INCLUDE (zone_id)` pour un `Index Only Scan` après `VACUUM`,
ou index `BRIN` sur `date_id` (efficace sur des données triées par date).

**Point de méthode.** Un `CREATE INDEX` qui échoue dans un script annule tout le bloc
(une seule transaction implicite) ; nous avons dû vérifier dans `pg_indexes` que les 5 index
existaient avant de mesurer. Les scripts utilisent maintenant `CREATE INDEX IF NOT EXISTS`.

## Limites

- Une seule machine ; les temps varient de 10 à 20 % entre deux exécutions, et la première
  exécution après une coupure est plus lente (cache froid).
- Le dépôt `sh_R53` et le livreur `cq_C73` ont été choisis car ils ont des lignes en retard et
  un volume suffisant ; les gains dépendent de la sélectivité du filtre.
- Base de 10,65 millions de lignes, sans multiplication des données.
