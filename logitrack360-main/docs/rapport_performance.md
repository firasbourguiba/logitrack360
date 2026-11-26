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

## Passage à l'échelle : x3 (31 952 424 lignes)

Consigne : multiplier les données, analyser avec `EXPLAIN ANALYZE`, indexer, mesurer l'impact.
La table `colis_operations` est copiée 3 fois dans `colis_operations_x3` (`sql/5_passage_echelle.sql`),
avec identifiants et dates décalés de +365 et +730 jours ; la table d'origine n'est pas modifiée.
Mêmes requêtes A1, A3 et A4, mêmes protocole et index (5 index créés en 3 min 51 s).

Taille : 5 437 MB de données et clé primaire. Index : 211 à 221 MB chacun pour les index complets,
684 MB pour la clé primaire, environ 2,4 MB pour l'index partiel `idx_x3_retard`.

| Requête | Sans index (médiane, ms) | Avec index (médiane, ms) | Gain | Plan avec index |
|---|---|---|---|---|
| A1 - retards du dépôt `sh_R53` (16 767 lignes) | 7 065 | 5,9 | x1 200 | Bitmap Index Scan `idx_x3_retard` |
| A3 - ramassages du 2023-09-15 (33 538 lignes) | environ 7 281 | 500 | x15 | Index Scan `idx_x3_type_date` |
| A4 - jointure + `RANK()` (96 864 lignes) | environ 7 540 | 268 | x28 | Bitmap Index Scan `idx_x3_depot` + Hash Join |

Toutes les mesures :
- A1 sans index : 7 065 / 7 067 / 6 837 ms ; avec index : 32,7 (cache froid) / 5,9 / 5,8 ms.
- A3 sans index : environ 6 774 / 8 012 / 7 281 ms (fin du nœud principal, le temps total était coupé) ;
  avec index : 5 396 (cache froid) / 500 / 438 ms.
- A4 sans index : environ 7 538 / 7 577 / 6 870 ms (même remarque) ; avec index : 303 / 268 / 262 ms.

### Comparaison 10,65 M et 32 M de lignes

| Requête | Sans index 10 M | Sans index 32 M | Avec index 10 M | Avec index 32 M | Gain 10 M | Gain 32 M |
|---|---|---|---|---|---|---|
| A1 | 812 ms | 7 065 ms | 2,1 ms | 5,9 ms | x380 | x1 200 |
| A3 | 887 ms | environ 7 281 ms | 493 ms | 500 ms | x1,8 | x15 |
| A4 | 935 ms | environ 7 540 ms | environ 75 ms | 268 ms | x12 | x28 |

### Interprétation

**Sans index, le coût explose.** Les données sont multipliées par 3 mais les temps par 8 à 9
(A1 : 812 à 7 065 ms). Le nombre de pages lues est multiplié par 3,2 seulement (183 000 à 592 000) :
le surcoût vient donc de la lecture disque. Hypothèse : la table d'origine (environ 1,4 Go) tenait
dans les caches mémoire, alors que `colis_operations_x3` (environ 4,6 Go) n'y tient plus.
Le parcours complet (`Parallel Seq Scan`) ne passe donc pas à l'échelle.

**Avec index, le coût suit le volume retourné, pas la taille de la table.** A1 retourne 3 fois plus de
lignes (16 767 contre 5 589) et son temps est environ multiplié par 3 (2,1 à 5,9 ms) ; de même pour A4
(75 à 268 ms). Le gain de l'index augmente donc avec le volume : plus la table grossit, plus l'index
est rentable.

**A3 illustre bien ce principe.** À 10 M de lignes, l'index n'apportait presque rien (x1,8) : le
parcours complet était encore raisonnable. À 32 M, il devient très rentable (x15) : le parcours
complet coûte 7 s alors que la recherche indexée reste à environ 500 ms. Le nombre de lignes du jour
est le même (33 538), seule la table a grossi. Le temps de l'index (500 ms) vient de lectures
disque dispersées, car la table n'est pas triée par date.

**Plans.** Avec 16 767 lignes (A1) et 96 864 lignes (A4), PostgreSQL choisit un `Bitmap Index Scan`
suivi d'un `Bitmap Heap Scan` : il lit d'abord l'index, trie les pages à lire, puis lit la table dans
l'ordre, ce qui évite les lectures dispersées d'un `Index Scan` simple. Pour A3, il garde un `Index Scan`.

**Point d'amélioration sur A4.** Le tri passe par le disque (`Sort Method: external merge Disk: 3560kB`)
car la mémoire de tri (`work_mem`, 4 Mo par défaut) est dépassée. Augmenter `work_mem`
(par exemple `SET work_mem = '16MB'`) devrait supprimer ce tri sur disque (non testé).

**Coût des index.** Les 5 index occupent environ 0,9 Go sur 32 M de lignes (hors clé primaire : 211 + 217 + 221 + 215 MB + 2,4 MB),
et leur création a pris 3 min 51 s. L'index partiel `idx_x3_retard` ne pèse que 2,4 MB contre
211 MB pour l'index complet sur la même colonne : il ne contient que les opérations en retard
et sert la requête A1 sans le coût d'un index complet.

## Limites

- Une seule machine ; les temps varient de 10 à 20 % entre deux exécutions, et la première
  exécution après une coupure est plus lente (cache froid).
- Le dépôt `sh_R53` et le livreur `cq_C73` ont été choisis car ils ont des lignes en retard et
  un volume suffisant ; les gains dépendent de la sélectivité du filtre.
- Les données multipliées par 3 sont des copies décalées dans le temps : elles ont les mêmes distributions
  que l'original, ce qui est plus régulier que des données réelles.
