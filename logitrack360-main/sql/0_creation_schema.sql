-- Projet LogiTrack 360 - Creation du schema relationnel
-- Base PostgreSQL : logitrack360

DROP TABLE IF EXISTS colis_operations CASCADE;
DROP TABLE IF EXISTS livreurs CASCADE;
DROP TABLE IF EXISTS depots CASCADE;
DROP TABLE IF EXISTS zones_geo CASCADE;
DROP TABLE IF EXISTS dim_dates CASCADE;

-- 1. Table zones_geo : hierarchie geographique pour la CTE recursive
CREATE TABLE zones_geo (
    zone_id VARCHAR(64) PRIMARY KEY,
    nom_zone VARCHAR(100) NOT NULL,
    niveau VARCHAR(20) NOT NULL CHECK (niveau IN ('PAYS', 'VILLE', 'QUARTIER_AOI')),
    parent_zone_id VARCHAR(64) REFERENCES zones_geo(zone_id) ON DELETE SET NULL
);

-- 2. Table depots : stations logistiques de depart
CREATE TABLE depots (
    depot_id VARCHAR(64) PRIMARY KEY,
    nom_depot VARCHAR(100) NOT NULL,
    zone_id VARCHAR(64) NOT NULL REFERENCES zones_geo(zone_id),
    type_hub VARCHAR(50) DEFAULT 'STATION_URBAINE'
);

-- 3. Table livreurs : coursiers et chauffeurs
CREATE TABLE livreurs (
    livreur_id VARCHAR(64) PRIMARY KEY,
    zone_affiliation_id VARCHAR(64) REFERENCES zones_geo(zone_id),
    statut VARCHAR(20) DEFAULT 'ACTIF' CHECK (statut IN ('ACTIF', 'INACTIF', 'EN_CONGE')),
    cree_le TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 4. Table dim_dates : dimension calendrier
CREATE TABLE dim_dates (
    date_id DATE PRIMARY KEY,
    jour INT NOT NULL CHECK (jour BETWEEN 1 AND 31),
    mois INT NOT NULL CHECK (mois BETWEEN 1 AND 12),
    annee INT NOT NULL CHECK (annee >= 2020),
    jour_semaine INT NOT NULL CHECK (jour_semaine BETWEEN 1 AND 7),
    nom_jour VARCHAR(20) NOT NULL,
    est_weekend BOOLEAN NOT NULL
);

-- 5. Table colis_operations : faits unifies 
CREATE TABLE colis_operations (
    operation_id BIGSERIAL PRIMARY KEY,
    order_id VARCHAR(64) NOT NULL,
    type_operation VARCHAR(20) NOT NULL CHECK (type_operation IN ('LIVRAISON', 'RAMASSAGE')),
    depot_id VARCHAR(64) NOT NULL REFERENCES depots(depot_id),
    livreur_id VARCHAR(64) NOT NULL REFERENCES livreurs(livreur_id),
    zone_id VARCHAR(64) NOT NULL REFERENCES zones_geo(zone_id),
    date_id DATE NOT NULL REFERENCES dim_dates(date_id),
    heure_debut TIMESTAMPTZ,
    heure_fin TIMESTAMPTZ,
    heure_promise TIMESTAMPTZ,
    duree_minutes NUMERIC(10, 2),
    est_en_retard BOOLEAN DEFAULT FALSE,
    typecode VARCHAR(64),
    poi_lng DOUBLE PRECISION,
    poi_lat DOUBLE PRECISION,
    gps_lng DOUBLE PRECISION,
    gps_lat DOUBLE PRECISION
);
