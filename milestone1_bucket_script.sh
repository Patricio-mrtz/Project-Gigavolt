#!/bin/bash
set -euo pipefail

# ==============================================================================
# PROJECT GIGAVOLT
# MariaDB 12.3 + Galera 4 + ColumnStore + Milestone 1 Database
# Ubuntu 26.04
# ==============================================================================

# ==============================================================================
# LOGGING
# ==============================================================================

LOGFILE="/var/log/user-data.log"
exec > >(tee -a "${LOGFILE}") 2>&1

trap 'echo "[ERROR] Installation failed at line $LINENO."' ERR

echo "================================================================="
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting User Data initialization..."
echo "================================================================="


# ==============================================================================
# NON-INTERACTIVE MODE
# ==============================================================================

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a


# ==============================================================================
# STEP 1 - UPDATE PACKAGE LISTS
# ==============================================================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Step 1/6] Updating package lists..."

apt-get update -y


# ==============================================================================
# STEP 2 - UPGRADE PACKAGES
# ==============================================================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Step 2/6] Upgrading packages..."

apt-get upgrade -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold"


# ==============================================================================
# STEP 3 - INSTALL PREREQUISITES
# ==============================================================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Step 3/6] Installing prerequisites..."

apt-get install -y \
  ca-certificates \
  curl \
  apt-transport-https \
  socat \
  wget \
  unzip


# ==============================================================================
# STEP 4 - CONFIGURE MARIADB 12.3 REPOSITORY
# ==============================================================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Step 4/6] Adding MariaDB repository..."

mkdir -p /etc/apt/keyrings

curl -fsSL \
  https://mariadb.org/mariadb_release_signing_key.pgp \
  -o /etc/apt/keyrings/mariadb-keyring.asc

chmod 644 /etc/apt/keyrings/mariadb-keyring.asc

cat <<'EOF' > /etc/apt/sources.list.d/mariadb.sources
# MariaDB 12.3 Community Repository
X-Repolib-Name: MariaDB
Types: deb
URIs: https://deb.mariadb.org/12.3/ubuntu
Suites: resolute
Components: main
Signed-By: /etc/apt/keyrings/mariadb-keyring.asc
EOF


# ==============================================================================
# STEP 5 - REFRESH PACKAGE LISTS
# ==============================================================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Step 5/6] Refreshing package lists..."

apt-get update -y


# ==============================================================================
# VERIFY PACKAGES
# ==============================================================================

echo "Checking available MariaDB packages..."

apt-cache policy \
  mariadb-server \
  mariadb-server-galera \
  galera-4 \
  mariadb-plugin-columnstore

CANDIDATE=$(apt-cache policy mariadb-server | awk '/Candidate:/ {print $2}')

echo "MariaDB Candidate: $CANDIDATE"

if [[ ! "$CANDIDATE" =~ ^1:12\.3\.|^12\.3\. ]]; then

    echo "ERROR: MariaDB 12.3 is not the selected package version."
    echo "Candidate: $CANDIDATE"

    exit 1

fi


# ==============================================================================
# STEP 6 - INSTALL MARIADB + GALERA + COLUMNSTORE
# ==============================================================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Step 6/6] Installing MariaDB 12.3, Galera 4, and ColumnStore..."

apt-get install -y \
  mariadb-server \
  mariadb-server-galera \
  galera-4 \
  mariadb-client \
  mariadb-backup \
  mariadb-plugin-columnstore \
  socat


# ==============================================================================
# VERIFY INSTALLATION
# ==============================================================================

echo "================================================================="
echo "VERIFYING MARIADB / GALERA / COLUMNSTORE"
echo "================================================================="

mariadb --version
mariadbd --version

dpkg-query -W \
  mariadb-server \
  mariadb-server-galera \
  galera-4 \
  mariadb-client \
  mariadb-backup \
  mariadb-plugin-columnstore


# ==============================================================================
# START MARIADB TEMPORARILY FOR MILESTONE 1
# ==============================================================================

echo "================================================================="
echo "STARTING MARIADB FOR MILESTONE 1"
echo "================================================================="

systemctl enable mariadb
systemctl start mariadb

mariadb -e "SET GLOBAL local_infile=1;"

echo "MariaDB installed and started"


# ==============================================================================
# MILESTONE 1 - DOWNLOAD GIGAVOLT DATA
# ==============================================================================

echo "================================================================="
echo "BEGINNING MILESTONE 1"
echo "================================================================="

mkdir -p /tmp/data
cd /tmp/data

wget -O fall2026.zip \
  https://622.gomillion.org/data/fall2026.zip

unzip -o fall2026.zip

echo "Gigavolt files downloaded and extracted"

find /tmp/data -maxdepth 2 -type f


# ==============================================================================
# CREATE MILESTONE 1 SQL SCRIPT
# ==============================================================================

cat <<'SQL' > /tmp/data/init_db.sql


-- =============================================================================
-- CREATE DATABASE
-- =============================================================================

DROP DATABASE IF EXISTS gigavolt_erp;

CREATE DATABASE gigavolt_erp
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE gigavolt_erp;

SET NAMES utf8mb4;


-- =============================================================================
-- BRONZE TABLES
-- =============================================================================

CREATE TABLE import_customers (
    staging_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    customer_id VARCHAR(50),
    company_name VARCHAR(255),
    contact_name VARCHAR(255),
    phone VARCHAR(100),
    email VARCHAR(255),
    address VARCHAR(255),
    city VARCHAR(100),
    state VARCHAR(50),
    zip VARCHAR(30),
    country VARCHAR(100),
    created_date VARCHAR(100),
    status VARCHAR(100)
) ENGINE=MyISAM;


CREATE TABLE import_equipment (
    staging_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    equipment_id VARCHAR(50),
    customer_id VARCHAR(50),
    model VARCHAR(100),
    serial_number VARCHAR(100),
    install_date VARCHAR(100),
    capacity_kw VARCHAR(50),
    voltage VARCHAR(50),
    warranty_expiration VARCHAR(100),
    status VARCHAR(100),
    location_notes TEXT
) ENGINE=MyISAM;


CREATE TABLE import_dispatches (
    staging_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    dispatch_id VARCHAR(50),
    equipment_id VARCHAR(50),
    customer_id VARCHAR(50),
    dispatch_date VARCHAR(100),
    technician VARCHAR(255),
    service_type VARCHAR(100),
    hours_spent VARCHAR(50),
    labor_cost VARCHAR(50),
    resolution_summary TEXT,
    status VARCHAR(100)
) ENGINE=MyISAM;


CREATE TABLE import_parts (
    staging_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    part_id VARCHAR(50),
    part_name VARCHAR(255),
    category VARCHAR(100),
    manufacturer VARCHAR(255),
    supplier VARCHAR(255),
    unit_cost VARCHAR(50),
    unit_price VARCHAR(50),
    stock_quantity VARCHAR(50),
    reorder_level VARCHAR(50)
) ENGINE=MyISAM;


CREATE TABLE import_warranty_claims (
    staging_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    claim_id VARCHAR(50),
    equipment_id VARCHAR(50),
    dispatch_id VARCHAR(50),
    part_id VARCHAR(50),
    claim_date VARCHAR(100),
    claim_amount VARCHAR(50),
    approved_amount VARCHAR(50),
    status VARCHAR(100),
    denial_reason TEXT,
    claim_notes TEXT
) ENGINE=MyISAM;


-- =============================================================================
-- RESET BRONZE TABLES
-- =============================================================================

TRUNCATE TABLE import_customers;
TRUNCATE TABLE import_equipment;
TRUNCATE TABLE import_dispatches;
TRUNCATE TABLE import_parts;
TRUNCATE TABLE import_warranty_claims;


-- =============================================================================
-- LOAD RAW DATA
-- =============================================================================

LOAD DATA LOCAL INFILE '/tmp/data/customers.csv'
INTO TABLE import_customers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    customer_id,
    company_name,
    contact_name,
    phone,
    email,
    address,
    city,
    state,
    zip,
    country,
    created_date,
    status
);


LOAD DATA LOCAL INFILE '/tmp/data/equipment.csv'
INTO TABLE import_equipment
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    equipment_id,
    customer_id,
    model,
    serial_number,
    install_date,
    capacity_kw,
    voltage,
    warranty_expiration,
    status,
    location_notes
);


LOAD DATA LOCAL INFILE '/tmp/data/dispatches.csv'
INTO TABLE import_dispatches
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    dispatch_id,
    equipment_id,
    customer_id,
    dispatch_date,
    technician,
    service_type,
    hours_spent,
    labor_cost,
    resolution_summary,
    status
);


LOAD DATA LOCAL INFILE '/tmp/data/parts.csv'
INTO TABLE import_parts
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    part_id,
    part_name,
    category,
    manufacturer,
    supplier,
    unit_cost,
    unit_price,
    stock_quantity,
    reorder_level
);


LOAD DATA LOCAL INFILE '/tmp/data/warranty_claims.csv'
INTO TABLE import_warranty_claims
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    claim_id,
    equipment_id,
    dispatch_id,
    part_id,
    claim_date,
    claim_amount,
    approved_amount,
    status,
    denial_reason,
    claim_notes
);


-- =============================================================================
-- VALIDATE BRONZE
-- =============================================================================

SELECT
    'Customers' AS table_name,
    COUNT(*) AS row_count
FROM import_customers

UNION ALL

SELECT
    'Equipment',
    COUNT(*)
FROM import_equipment

UNION ALL

SELECT
    'Dispatches',
    COUNT(*)
FROM import_dispatches

UNION ALL

SELECT
    'Parts',
    COUNT(*)
FROM import_parts

UNION ALL

SELECT
    'Warranty Claims',
    COUNT(*)
FROM import_warranty_claims;


-- =============================================================================
-- CHECK DUPLICATES
-- =============================================================================

SELECT
    'Customers' AS table_name,
    COUNT(*) - COUNT(DISTINCT customer_id) AS duplicates
FROM import_customers

UNION ALL

SELECT
    'Equipment',
    COUNT(*) - COUNT(DISTINCT equipment_id)
FROM import_equipment

UNION ALL

SELECT
    'Dispatches',
    COUNT(*) - COUNT(DISTINCT dispatch_id)
FROM import_dispatches

UNION ALL

SELECT
    'Parts',
    COUNT(*) - COUNT(DISTINCT part_id)
FROM import_parts

UNION ALL

SELECT
    'Warranty Claims',
    COUNT(*) - COUNT(DISTINCT claim_id)
FROM import_warranty_claims;


-- =============================================================================
-- REMOVE DUPLICATES
-- =============================================================================

DELIMITER //

CREATE PROCEDURE remove_duplicates(
    IN table_name VARCHAR(50),
    IN id_column VARCHAR(50)
)
BEGIN

    SET @sql = CONCAT(
        'DELETE a FROM ', table_name, ' a ',
        'JOIN ', table_name, ' b ',
        'ON a.', id_column, ' = b.', id_column,
        ' AND a.staging_id > b.staging_id'
    );

    PREPARE stmt FROM @sql;

    EXECUTE stmt;

    DEALLOCATE PREPARE stmt;

END //

DELIMITER ;


CALL remove_duplicates(
    'import_customers',
    'customer_id'
);

CALL remove_duplicates(
    'import_equipment',
    'equipment_id'
);

CALL remove_duplicates(
    'import_dispatches',
    'dispatch_id'
);

CALL remove_duplicates(
    'import_parts',
    'part_id'
);

CALL remove_duplicates(
    'import_warranty_claims',
    'claim_id'
);

DROP PROCEDURE remove_duplicates;


-- =============================================================================
-- CLEANING FUNCTIONS
-- =============================================================================

DELIMITER //


CREATE FUNCTION standardize_date(
    raw_date VARCHAR(100)
)
RETURNS DATE
DETERMINISTIC
BEGIN

    RETURN CASE

        WHEN TRIM(raw_date)
            REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}'

            THEN STR_TO_DATE(
                LEFT(TRIM(raw_date), 10),
                '%Y-%m-%d'
            )

        WHEN TRIM(raw_date)
            REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'

            THEN STR_TO_DATE(
                TRIM(raw_date),
                '%Y/%m/%d'
            )

        WHEN TRIM(raw_date)
            REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'

            THEN STR_TO_DATE(
                TRIM(raw_date),
                '%m/%d/%Y'
            )

        WHEN TRIM(raw_date)
            REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'

            THEN STR_TO_DATE(
                TRIM(raw_date),
                '%m-%d-%Y'
            )

        ELSE NULL

    END;

END //


CREATE FUNCTION clean_text(
    raw_text TEXT
)
RETURNS TEXT
DETERMINISTIC
BEGIN

    RETURN TRIM(
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                raw_text,
                '<[^>]+>',
                ''
            ),
            '[[:space:]]+',
            ' '
        )
    );

END //


CREATE FUNCTION clean_number(
    raw_number VARCHAR(100)
)
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN

    RETURN CAST(
        NULLIF(
            REGEXP_REPLACE(
                TRIM(raw_number),
                '[^0-9.-]',
                ''
            ),
            ''
        )
        AS DECIMAL(12,2)
    );

END //

DELIMITER ;


-- =============================================================================
-- CLEAN BRONZE DATA
-- =============================================================================

UPDATE import_customers
SET
    created_date = standardize_date(created_date),
    company_name = clean_text(company_name),
    contact_name = clean_text(contact_name),
    phone = clean_text(phone),
    email = clean_text(email),
    address = clean_text(address),
    city = clean_text(city),
    state = clean_text(state),
    zip = clean_text(zip),
    country = clean_text(country),
    status = clean_text(status);


UPDATE import_equipment
SET
    install_date = standardize_date(install_date),
    warranty_expiration = standardize_date(warranty_expiration),
    model = clean_text(model),
    serial_number = clean_text(serial_number),
    voltage = clean_text(voltage),
    status = clean_text(status),
    location_notes = clean_text(location_notes);


UPDATE import_dispatches
SET
    dispatch_date = standardize_date(dispatch_date),
    technician = clean_text(technician),
    service_type = clean_text(service_type),
    labor_cost = clean_text(labor_cost),
    resolution_summary = clean_text(resolution_summary),
    status = clean_text(status);


UPDATE import_parts
SET
    part_name = clean_text(part_name),
    category = clean_text(category),
    manufacturer = clean_text(manufacturer),
    supplier = clean_text(supplier);


UPDATE import_warranty_claims
SET
    claim_date = standardize_date(claim_date),
    status = clean_text(status),
    denial_reason = clean_text(denial_reason),
    claim_notes = clean_text(claim_notes);


-- =============================================================================
-- SILVER TABLES
-- =============================================================================

CREATE TABLE locations (
    zip VARCHAR(30) PRIMARY KEY,
    city VARCHAR(100),
    state VARCHAR(50),
    country VARCHAR(100)
) ENGINE=InnoDB;


CREATE TABLE customers (
    customer_id VARCHAR(50) PRIMARY KEY,
    company_name VARCHAR(255),
    contact_name VARCHAR(255),
    phone VARCHAR(100),
    email VARCHAR(255),
    address VARCHAR(255),
    zip VARCHAR(30),
    created_date DATE,
    status VARCHAR(50),

    FOREIGN KEY (zip)
        REFERENCES locations(zip)

) ENGINE=InnoDB;


CREATE TABLE equipment_units (
    equipment_id VARCHAR(50) PRIMARY KEY,
    customer_id VARCHAR(50),
    model VARCHAR(100),
    serial_number VARCHAR(100),
    install_date DATE,
    capacity_kw DECIMAL(12,2),
    voltage VARCHAR(50),
    warranty_expiration DATE,
    status VARCHAR(50),
    location_notes TEXT,

    FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id)

) ENGINE=InnoDB;


CREATE TABLE service_logs (
    dispatch_id VARCHAR(50) PRIMARY KEY,
    equipment_id VARCHAR(50),
    dispatch_date DATE,
    technician VARCHAR(255),
    service_type VARCHAR(100),
    hours_spent DECIMAL(12,2),
    labor_cost DECIMAL(12,2),
    resolution_summary TEXT,
    status VARCHAR(50),

    FOREIGN KEY (equipment_id)
        REFERENCES equipment_units(equipment_id)

) ENGINE=InnoDB;


CREATE TABLE parts_inventory (
    part_id VARCHAR(50) PRIMARY KEY,
    part_name VARCHAR(255),
    category VARCHAR(100),
    manufacturer VARCHAR(255),
    supplier VARCHAR(255),
    unit_cost DECIMAL(12,2),
    unit_price DECIMAL(12,2),
    stock_quantity INT,
    reorder_level INT
) ENGINE=InnoDB;


CREATE TABLE warranty_claims (
    claim_id VARCHAR(50) PRIMARY KEY,
    equipment_id VARCHAR(50),
    dispatch_id VARCHAR(50),
    part_id VARCHAR(50),
    claim_date DATE,
    claim_amount DECIMAL(12,2),
    approved_amount DECIMAL(12,2),
    status VARCHAR(50),
    denial_reason TEXT,
    claim_notes TEXT,

    FOREIGN KEY (equipment_id)
        REFERENCES equipment_units(equipment_id),

    FOREIGN KEY (dispatch_id)
        REFERENCES service_logs(dispatch_id),

    FOREIGN KEY (part_id)
        REFERENCES parts_inventory(part_id)

) ENGINE=InnoDB;


-- =============================================================================
-- MIGRATE TO SILVER
-- =============================================================================

INSERT INTO locations (
    zip,
    city,
    state,
    country
)
SELECT
    zip,

    MAX(city),

    MAX(state),

    MAX(
        CASE
            WHEN UPPER(
                COALESCE(country, '')
            ) IN (
                '',
                'NULL',
                'US',
                'USA',
                'UNITED STATES'
            )
            THEN 'USA'

            ELSE UPPER(country)

        END
    )

FROM import_customers

WHERE NULLIF(
    TRIM(zip),
    ''
) IS NOT NULL

GROUP BY zip;


INSERT INTO customers (
    customer_id,
    company_name,
    contact_name,
    phone,
    email,
    address,
    zip,
    created_date,
    status
)
SELECT
    customer_id,
    company_name,
    contact_name,
    phone,
    email,
    address,
    NULLIF(TRIM(zip), ''),
    created_date,
    UPPER(TRIM(status))

FROM import_customers;


INSERT INTO equipment_units (
    equipment_id,
    customer_id,
    model,
    serial_number,
    install_date,
    capacity_kw,
    voltage,
    warranty_expiration,
    status,
    location_notes
)
SELECT
    e.equipment_id,

    CASE
        WHEN c.customer_id IS NULL
            THEN NULL
        ELSE e.customer_id
    END,

    e.model,
    e.serial_number,
    e.install_date,
    clean_number(e.capacity_kw),
    e.voltage,
    e.warranty_expiration,
    UPPER(TRIM(e.status)),
    e.location_notes

FROM import_equipment e

LEFT JOIN customers c
    ON c.customer_id = e.customer_id;


INSERT INTO service_logs (
    dispatch_id,
    equipment_id,
    dispatch_date,
    technician,
    service_type,
    hours_spent,
    labor_cost,
    resolution_summary,
    status
)
SELECT
    d.dispatch_id,

    CASE
        WHEN e.equipment_id IS NULL
            THEN NULL
        ELSE d.equipment_id
    END,

    d.dispatch_date,
    d.technician,
    d.service_type,
    clean_number(d.hours_spent),
    clean_number(d.labor_cost),
    d.resolution_summary,
    UPPER(TRIM(d.status))

FROM import_dispatches d

LEFT JOIN equipment_units e
    ON e.equipment_id = d.equipment_id;


INSERT INTO parts_inventory (
    part_id,
    part_name,
    category,
    manufacturer,
    supplier,
    unit_cost,
    unit_price,
    stock_quantity,
    reorder_level
)
SELECT
    part_id,
    part_name,
    category,
    manufacturer,
    supplier,
    clean_number(unit_cost),
    clean_number(unit_price),
    CAST(
        clean_number(stock_quantity)
        AS SIGNED
    ),
    CAST(
        clean_number(reorder_level)
        AS SIGNED
    )

FROM import_parts;


INSERT INTO warranty_claims (
    claim_id,
    equipment_id,
    dispatch_id,
    part_id,
    claim_date,
    claim_amount,
    approved_amount,
    status,
    denial_reason,
    claim_notes
)
SELECT
    w.claim_id,

    CASE
        WHEN e.equipment_id IS NULL
            THEN NULL
        ELSE w.equipment_id
    END,

    CASE
        WHEN s.dispatch_id IS NULL
            THEN NULL
        ELSE w.dispatch_id
    END,

    CASE
        WHEN p.part_id IS NULL
            THEN NULL
        ELSE w.part_id
    END,

    w.claim_date,
    clean_number(w.claim_amount),
    clean_number(w.approved_amount),
    UPPER(TRIM(w.status)),
    w.denial_reason,
    w.claim_notes

FROM import_warranty_claims w

LEFT JOIN equipment_units e
    ON e.equipment_id = w.equipment_id

LEFT JOIN service_logs s
    ON s.dispatch_id =
       NULLIF(
           NULLIF(
               TRIM(w.dispatch_id),
               ''
           ),
           'NULL'
       )

LEFT JOIN parts_inventory p
    ON p.part_id =
       NULLIF(
           NULLIF(
               TRIM(w.part_id),
               ''
           ),
           'NULL'
       );


-- =============================================================================
-- VALIDATE MIGRATION
-- =============================================================================

SELECT
    'Customers' AS table_name,
    (SELECT COUNT(*) FROM import_customers) AS bronze_count,
    (SELECT COUNT(*) FROM customers) AS silver_count

UNION ALL

SELECT
    'Equipment',
    (SELECT COUNT(*) FROM import_equipment),
    (SELECT COUNT(*) FROM equipment_units)

UNION ALL

SELECT
    'Dispatches',
    (SELECT COUNT(*) FROM import_dispatches),
    (SELECT COUNT(*) FROM service_logs)

UNION ALL

SELECT
    'Parts',
    (SELECT COUNT(*) FROM import_parts),
    (SELECT COUNT(*) FROM parts_inventory)

UNION ALL

SELECT
    'Warranty Claims',
    (SELECT COUNT(*) FROM import_warranty_claims),
    (SELECT COUNT(*) FROM warranty_claims);


-- =============================================================================
-- VALIDATE FOREIGN KEYS
-- =============================================================================

SELECT
    'Customers -> Locations' AS relationship,
    COUNT(*) AS orphan_count
FROM customers c
LEFT JOIN locations l
    ON l.zip = c.zip
WHERE c.zip IS NOT NULL
AND l.zip IS NULL

UNION ALL

SELECT
    'Equipment -> Customers',
    COUNT(*)
FROM equipment_units e
LEFT JOIN customers c
    ON c.customer_id = e.customer_id
WHERE e.customer_id IS NOT NULL
AND c.customer_id IS NULL

UNION ALL

SELECT
    'Service Logs -> Equipment',
    COUNT(*)
FROM service_logs s
LEFT JOIN equipment_units e
    ON e.equipment_id = s.equipment_id
WHERE s.equipment_id IS NOT NULL
AND e.equipment_id IS NULL

UNION ALL

SELECT
    'Warranty -> Equipment',
    COUNT(*)
FROM warranty_claims w
LEFT JOIN equipment_units e
    ON e.equipment_id = w.equipment_id
WHERE w.equipment_id IS NOT NULL
AND e.equipment_id IS NULL

UNION ALL

SELECT
    'Warranty -> Service Logs',
    COUNT(*)
FROM warranty_claims w
LEFT JOIN service_logs s
    ON s.dispatch_id = w.dispatch_id
WHERE w.dispatch_id IS NOT NULL
AND s.dispatch_id IS NULL

UNION ALL

SELECT
    'Warranty -> Parts',
    COUNT(*)
FROM warranty_claims w
LEFT JOIN parts_inventory p
    ON p.part_id = w.part_id
WHERE w.part_id IS NOT NULL
AND p.part_id IS NULL;


SHOW TABLES;


SQL


# ==============================================================================
# RUN MILESTONE 1 SQL PIPELINE
# ==============================================================================

echo "================================================================="
echo "RUNNING MILESTONE 1 GIGAVOLT PIPELINE"
echo "================================================================="

mariadb --local-infile=1 < /tmp/data/init_db.sql

echo "Gigavolt database setup complete"


# ==============================================================================
# VERIFY GIGAVOLT DATABASE
# ==============================================================================

echo "================================================================="
echo "VERIFYING GIGAVOLT DATABASE"
echo "================================================================="

mariadb -e "
SHOW DATABASES LIKE 'gigavolt_erp';
"

mariadb gigavolt_erp -e "
SHOW TABLES;
"


# ==============================================================================
# VERIFY COLUMNSTORE PACKAGE
# ==============================================================================

echo "================================================================="
echo "VERIFYING COLUMNSTORE PACKAGE"
echo "================================================================="

dpkg-query -W mariadb-plugin-columnstore


# ==============================================================================
# STOP MARIADB FOR GALERA CONFIGURATION
# ==============================================================================

echo "================================================================="
echo "PREPARING MARIADB FOR GALERA CLUSTER CONFIGURATION"
echo "================================================================="

systemctl stop mariadb

# Prevent standalone MariaDB startup before Galera configuration
systemctl disable mariadb


# ==============================================================================
# FINAL STATUS
# ==============================================================================

echo "================================================================="
echo "[$(date '+%Y-%m-%d %H:%M:%S')] INSTALLATION COMPLETE"
echo "================================================================="

echo "MariaDB Version:"
mariadb --version

echo ""

echo "Galera:"
dpkg-query -W galera-4

echo ""

echo "ColumnStore:"
dpkg-query -W mariadb-plugin-columnstore

echo ""

echo "Gigavolt Database:"
mariadb -e "SHOW DATABASES LIKE 'gigavolt_erp';" 2>/dev/null || true

echo ""

echo "MariaDB Service Status:"
systemctl is-active mariadb || true

echo ""

echo "Milestone 1 database has been created."
echo "MariaDB is intentionally stopped for Galera configuration."

echo "================================================================="