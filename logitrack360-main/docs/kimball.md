# Conception du schéma en étoile (méthode de Kimball)

## 1. Processus métier

Les opérations du dernier kilomètre : livraisons et ramassages de colis du réseau Cainiao dans
5 villes chinoises. Question métier : où, quand et par qui les opérations sont-elles lentes ou en retard ?

## 2. Grain

**Une ligne de `fct_operations` = une opération (une livraison ou un ramassage d'un colis).**

## 3. Dimensions

| Dimension | Clé de substitution | Clé naturelle | Attributs | Axe d'analyse |
|---|---|---|---|---|
| `dim_date` | `date_key` (AAAAMMJJ) | `date_jour` | jour, mois, année, jour de la semaine, week-end | quand |
| `dim_zone` | `zone_key` (hash) | `zone_id` | quartier, ville, pays, niveau | où |
| `dim_depot` | `depot_key` (hash) | `depot_id` | nom, type, ville | quel dépôt |
| `dim_livreur` | `livreur_key` (hash) | `livreur_id` | statut, ville d'affiliation | par qui |

`dim_zone` est aplatie : la hiérarchie Pays > Ville > Quartier devient des colonnes, sans lien parent / enfant.
La ville est recopiée dans `dim_depot` et `dim_livreur` : aucune dimension ne dépend d'une autre dimension.
C'est ce qui distingue l'étoile du flocon.

## 4. Faits (mesures)

| Mesure | Description |
|---|---|
| `duree_minutes` | durée de l'opération, vide si une heure manque ou si elle dépasse 24 h |
| `est_en_retard` | vrai si le ramassage a eu lieu après l'heure promise (toujours faux pour les livraisons) |
| `heure_debut`, `heure_fin`, `heure_promise` | horodatages de l'opération |

Dimension dégénérée : `type_operation` (livraison ou ramassage), et `order_id`.

## Choix et limites

- **Étoile plutôt que flocon** : une seule jointure par axe, plus simple pour les analystes.
- **Dimension livreur** : version courante. L'historique des changements est dans le snapshot `snap_livreurs` (SCD2).
  Une jointure du fait sur la période de validité n'est pas faite : le snapshot date de 2026 alors que les
  opérations datent de 2023, aucune version ne correspondrait.
- **Retard** défini seulement pour les ramassages, car la source ne donne pas d'heure promise pour les livraisons.
- **Source** : le modèle relationnel normalisé (`public`) sert à l'écriture et à la CTE récursive ;
  l'étoile (`dbt_marts`) sert à l'analyse. dbt réalise le passage de l'un à l'autre.
