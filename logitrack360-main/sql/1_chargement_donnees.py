import os
import glob
import io
import csv
from datetime import datetime
import psycopg2

DB_CONFIG = {
    "dbname": "logitrack360",
    "user": "postgres",
    "password": "",  # votre mot de passe
    "host": "localhost",
    "port": 5432
}

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "LaDe_complet")

VILLES_MAPPING = {
    "上海市": "Shanghai",
    "重庆市": "Chongqing",
    "杭州市": "Hangzhou",
    "烟台市": "Yantai",
    "吉林市": "Jilin"
}

SUFFIX_MAPPING = {
    "cq": "Chongqing",
    "hz": "Hangzhou",
    "jl": "Jilin",
    "sh": "Shanghai",
    "yt": "Yantai"
}

def get_connection():
    return psycopg2.connect(**DB_CONFIG)

def suffixe(fpath):
    base = os.path.basename(fpath).split(".")[0]
    return base.split("_")[-1].lower()

def deduire_ville(fpath, ville_cn=None):
    return SUFFIX_MAPPING.get(suffixe(fpath), "Shanghai")

# Les identifiants (region_id, courier_id, aoi_id) se repetent d'une ville a l'autre :
# on les prefixe par la ville pour garder des cles uniques.
def cle(fpath, prefixe, valeur):
    return f"{suffixe(fpath)}_{prefixe}{valeur}"

def charger_referentiels(conn):
    print("--- 1. Remplissage des dimensions (zones, depots, livreurs, dates) ---")
    cur = conn.cursor()

    # Nettoyage prealable des tables pour relancer proprement
    cur.execute("TRUNCATE TABLE colis_operations CASCADE;")
    cur.execute("TRUNCATE TABLE livreurs CASCADE;")
    cur.execute("TRUNCATE TABLE depots CASCADE;")
    cur.execute("TRUNCATE TABLE zones_geo CASCADE;")
    cur.execute("TRUNCATE TABLE dim_dates CASCADE;")

    # Racine Chine
    cur.execute("""
        INSERT INTO zones_geo (zone_id, nom_zone, niveau, parent_zone_id)
        VALUES ('CN', 'Chine', 'PAYS', NULL);
    """)

    # 5 Villes
    for v in set(SUFFIX_MAPPING.values()):
        cur.execute("""
            INSERT INTO zones_geo (zone_id, nom_zone, niveau, parent_zone_id)
            VALUES (%s, %s, 'VILLE', 'CN');
        """, (v, v))

    # Dictionnaires uniques pour eviter les doublons
    aoi_dict = {}
    depots_dict = {}
    livreurs_dict = {}

    fichiers = glob.glob(os.path.join(DATA_DIR, "delivery", "*.csv")) + \
               glob.glob(os.path.join(DATA_DIR, "pickup", "*.csv"))

    for f in fichiers:
        nom_f = os.path.basename(f)
        print(f"Scan des referentiels : {nom_f}")
        with open(f, "r", encoding="utf-8") as fp:
            reader = csv.DictReader(fp)
            for row in reader:
                ville = deduire_ville(f)
                depot = cle(f, "R", row["region_id"]) if row.get("region_id") else None
                livreur = cle(f, "C", row["courier_id"]) if row.get("courier_id") else None
                aoi = cle(f, "A", row["aoi_id"]) if row.get("aoi_id") else None

                if aoi and aoi not in aoi_dict:
                    aoi_dict[aoi] = ville
                if depot and depot not in depots_dict:
                    depots_dict[depot] = ville
                if livreur and livreur not in livreurs_dict:
                    livreurs_dict[livreur] = ville

    # Insertion des Quartiers (AOI)
    print(f"Insertion de {len(aoi_dict)} zones AOI...")
    buffer_aoi = io.StringIO()
    for aoi, ville in aoi_dict.items():
        buffer_aoi.write(f"{aoi}\tQuartier_{aoi}\tQUARTIER_AOI\t{ville}\n")
    buffer_aoi.seek(0)
    cur.copy_from(buffer_aoi, "zones_geo", columns=("zone_id", "nom_zone", "niveau", "parent_zone_id"))

    # Insertion des Depots
    print(f"Insertion de {len(depots_dict)} depots...")
    buffer_depots = io.StringIO()
    for depot, ville in depots_dict.items():
        buffer_depots.write(f"{depot}\tStation_{depot}\t{ville}\tSTATION_URBAINE\n")
    buffer_depots.seek(0)
    cur.copy_from(buffer_depots, "depots", columns=("depot_id", "nom_depot", "zone_id", "type_hub"))

    # Insertion des Livreurs
    print(f"Insertion de {len(livreurs_dict)} livreurs...")
    buffer_livreurs = io.StringIO()
    for livreur, ville in livreurs_dict.items():
        buffer_livreurs.write(f"{livreur}\t{ville}\tACTIF\n")
    buffer_livreurs.seek(0)
    cur.copy_from(buffer_livreurs, "livreurs", columns=("livreur_id", "zone_affiliation_id", "statut"))

    # Generation de la dimension calendrier (2023 a 2025)
    print("Insertion de la dimension dim_dates...")
    cur.execute("""
        INSERT INTO dim_dates (date_id, jour, mois, annee, jour_semaine, nom_jour, est_weekend)
        SELECT 
            d::date,
            EXTRACT(DAY FROM d)::int,
            EXTRACT(MONTH FROM d)::int,
            EXTRACT(YEAR FROM d)::int,
            EXTRACT(ISODOW FROM d)::int,
            TO_CHAR(d, 'Day'),
            CASE WHEN EXTRACT(ISODOW FROM d) IN (6, 7) THEN TRUE ELSE FALSE END
        FROM generate_series('2023-01-01'::date, '2025-12-31'::date, '1 day'::interval) d;
    """)

    conn.commit()
    print("Dimensions chargees avec succes.")
    return aoi_dict

def charger_operations(conn, aoi_dict):
    print("--- 2. Chargement des ~10.6M d'operations avec COPY ---")
    cur = conn.cursor()

    # 2.1 Chargement des livraisons
    for f in glob.glob(os.path.join(DATA_DIR, "delivery", "*.csv")):
        nom = os.path.basename(f)
        print(f"Importation livraison : {nom}...")
        buffer = io.StringIO()
        with open(f, "r", encoding="utf-8") as fp:
            reader = csv.DictReader(fp)
            for row in reader:
                order_id = row.get("order_id")
                depot = cle(f, "R", row["region_id"])
                livreur = cle(f, "C", row["courier_id"])
                aoi = cle(f, "A", row["aoi_id"]) if row.get("aoi_id") else None
                # Si aoi manquant, rattachement a la ville
                zone_fk = aoi if (aoi and aoi in aoi_dict) else deduire_ville(f)

                rec_t = row.get("accept_time")
                sign_t = row.get("delivery_time")
                ds = row.get("ds", "")
                typecode = row.get("aoi_type", "")
                poi_lng = row.get("lng") or "\\N"
                poi_lat = row.get("lat") or "\\N"
                gps_lng = row.get("delivery_gps_lng") or "\\N"
                gps_lat = row.get("delivery_gps_lat") or "\\N"

                date_op = f"2023-{ds[:2]}-{ds[2:]}" if len(ds) == 4 else "2023-03-18"
                debut = f"2023-{rec_t}" if rec_t else "\\N"
                fin = f"2023-{sign_t}" if sign_t else "\\N"

                duree = "\\N"
                if rec_t and sign_t:
                    try:
                        t1 = datetime.strptime(f"2023-{rec_t}", "%Y-%m-%d %H:%M:%S")
                        t2 = datetime.strptime(f"2023-{sign_t}", "%Y-%m-%d %H:%M:%S")
                        sec = (t2 - t1).total_seconds()
                        if 0 <= sec <= 86400:
                            duree = str(round(sec / 60.0, 2))
                    except:
                        pass

                buffer.write(f"{order_id}\tLIVRAISON\t{depot}\t{livreur}\t{zone_fk}\t{date_op}\t{debut}\t{fin}\t\\N\t{duree}\tfalse\t{typecode}\t{poi_lng}\t{poi_lat}\t{gps_lng}\t{gps_lat}\n")

        buffer.seek(0)
        cur.copy_from(
            buffer, 
            "colis_operations", 
            columns=("order_id", "type_operation", "depot_id", "livreur_id", "zone_id", "date_id", "heure_debut", "heure_fin", "heure_promise", "duree_minutes", "est_en_retard", "typecode", "poi_lng", "poi_lat", "gps_lng", "gps_lat")
        )
        conn.commit()
        print(f"{nom} termine.")

    # 2.2 Chargement des ramassages (pickup)
    for f in glob.glob(os.path.join(DATA_DIR, "pickup", "*.csv")):
        nom = os.path.basename(f)
        print(f"Importation ramassage : {nom}...")
        buffer = io.StringIO()
        with open(f, "r", encoding="utf-8") as fp:
            reader = csv.DictReader(fp)
            for row in reader:
                order_id = row.get("order_id")
                depot = cle(f, "R", row["region_id"])
                livreur = cle(f, "C", row["courier_id"])
                aoi = cle(f, "A", row["aoi_id"]) if row.get("aoi_id") else None
                zone_fk = aoi if (aoi and aoi in aoi_dict) else deduire_ville(f)

                acc_t = row.get("accept_time")
                got_t = row.get("pickup_time")
                exp_t = row.get("time_window_end")
                ds = row.get("ds", "")
                typecode = row.get("aoi_type", "")
                poi_lng = row.get("lng") or "\\N"
                poi_lat = row.get("lat") or "\\N"
                gps_lng = row.get("pickup_gps_lng") or "\\N"
                gps_lat = row.get("pickup_gps_lat") or "\\N"

                date_op = f"2023-{ds[:2]}-{ds[2:]}" if len(ds) == 4 else "2023-03-18"
                debut = f"2023-{acc_t}" if acc_t else "\\N"
                fin = f"2023-{got_t}" if got_t else "\\N"
                promise = f"2023-{exp_t}" if exp_t else "\\N"

                duree = "\\N"
                retard = "false"
                if acc_t and got_t:
                    try:
                        t1 = datetime.strptime(f"2023-{acc_t}", "%Y-%m-%d %H:%M:%S")
                        t2 = datetime.strptime(f"2023-{got_t}", "%Y-%m-%d %H:%M:%S")
                        sec = (t2 - t1).total_seconds()
                        if 0 <= sec <= 86400:
                            duree = str(round(sec / 60.0, 2))
                    except:
                        pass

                if got_t and exp_t:
                    try:
                        t_got = datetime.strptime(f"2023-{got_t}", "%Y-%m-%d %H:%M:%S")
                        t_exp = datetime.strptime(f"2023-{exp_t}", "%Y-%m-%d %H:%M:%S")
                        if t_got > t_exp:
                            retard = "true"
                    except:
                        pass

                buffer.write(f"{order_id}\tRAMASSAGE\t{depot}\t{livreur}\t{zone_fk}\t{date_op}\t{debut}\t{fin}\t{promise}\t{duree}\t{retard}\t{typecode}\t{poi_lng}\t{poi_lat}\t{gps_lng}\t{gps_lat}\n")

        buffer.seek(0)
        cur.copy_from(
            buffer,
            "colis_operations",
            columns=("order_id", "type_operation", "depot_id", "livreur_id", "zone_id", "date_id", "heure_debut", "heure_fin", "heure_promise", "duree_minutes", "est_en_retard", "typecode", "poi_lng", "poi_lat", "gps_lng", "gps_lat")
        )
        conn.commit()
        print(f"{nom} termine.")

    print("Chargement des 10,6M d'operations termine avec succes !")

if __name__ == "__main__":
    conn = get_connection()
    try:
        aoi_dict = charger_referentiels(conn)
        charger_operations(conn, aoi_dict)
    finally:
        conn.close()