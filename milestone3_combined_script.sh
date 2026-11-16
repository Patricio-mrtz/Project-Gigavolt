#!/bin/bash
set -euo pipefail

exec > >(tee -a /var/log/user-data.log) 2>&1
trap 'echo "ERROR line $LINENO"' ERR

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a


# ============================================================
# MARIADB 12.3 + GALERA INSTALLATION
# ============================================================

echo "============================================================"
echo "INSTALLING MARIADB 12.3 + GALERA"
echo "============================================================"

apt-get update -y
apt-get install -y ca-certificates curl apt-transport-https socat awscli wget unzip

mkdir -p /etc/apt/keyrings

curl -fsSL \
https://mariadb.org/mariadb_release_signing_key.pgp \
-o /etc/apt/keyrings/mariadb-keyring.asc

chmod 644 /etc/apt/keyrings/mariadb-keyring.asc

cat > /etc/apt/sources.list.d/mariadb.sources <<'EOF'
X-Repolib-Name: MariaDB
Types: deb
URIs: https://deb.mariadb.org/12.3/ubuntu
Suites: resolute
Components: main
Signed-By: /etc/apt/keyrings/mariadb-keyring.asc
EOF

apt-get update -y

apt-get install -y \
mariadb-server \
mariadb-server-galera \
mariadb-client \
mariadb-backup \
galera-4 \
socat

systemctl enable mariadb
systemctl start mariadb

echo "MariaDB Version:"
mariadb --version


# ============================================================
# MILESTONE 1 - GIGAVOLT DATABASE
# ============================================================

echo "============================================================"
echo "MILESTONE 1 STARTING"
echo "============================================================"

aws s3 cp \
"s3://projectmilestone1bucket/bucket.txt" \
/tmp/milestone1.sh

sed -i 's/\r$//' /tmp/milestone1.sh
chmod +x /tmp/milestone1.sh

bash /tmp/milestone1.sh

echo "Verifying Milestone 1..."

mariadb -e "
SHOW DATABASES LIKE 'gigavolt_erp';
"

mariadb gigavolt_erp -e "
SHOW TABLES;
"

echo "============================================================"
echo "MILESTONE 1 COMPLETE"
echo "============================================================"


# ============================================================
# MILESTONE 2 - RAG / AUDIT / SECURITY
# ============================================================

echo "============================================================"
echo "MILESTONE 2 STARTING"
echo "============================================================"

cat > /tmp/milestone2.sql <<'SQL'

USE gigavolt_erp;


-- ============================================================
-- GENERATED RAG COLUMN
-- ============================================================

ALTER TABLE service_logs
ADD COLUMN IF NOT EXISTS full_service_context TEXT
GENERATED ALWAYS AS (
    CONCAT_WS(
        ' | ',
        CONCAT(
            'SERVICE DATE: ',
            COALESCE(CAST(dispatch_date AS CHAR),'UNKNOWN')
        ),
        CONCAT(
            'TECHNICIAN: ',
            COALESCE(
                NULLIF(
                    TRIM(
                        REGEXP_REPLACE(
                            technician,
                            '[[:space:]]+',
                            ' '
                        )
                    ),
                    ''
                ),
                'UNKNOWN'
            )
        ),
        CONCAT(
            'SERVICE TYPE: ',
            COALESCE(
                UPPER(
                    NULLIF(
                        TRIM(
                            REGEXP_REPLACE(
                                service_type,
                                '[[:space:]]+',
                                ' '
                            )
                        ),
                        ''
                    )
                ),
                'UNKNOWN'
            )
        ),
        CONCAT(
            'RESOLUTION: ',
            COALESCE(
                NULLIF(
                    TRIM(
                        REGEXP_REPLACE(
                            resolution_summary,
                            '[[:space:]]+',
                            ' '
                        )
                    ),
                    ''
                ),
                'UNKNOWN'
            )
        ),
        CONCAT(
            'STATUS: ',
            COALESCE(
                UPPER(NULLIF(TRIM(status),'')),
                'UNKNOWN'
            )
        )
    )
) VIRTUAL;


-- ============================================================
-- RAG STORED PROCEDURE
-- ============================================================

DROP PROCEDURE IF EXISTS sp_Prepare_RAG_Payloads;

DELIMITER //

CREATE PROCEDURE sp_Prepare_RAG_Payloads()

BEGIN

SELECT
    s.dispatch_id,

    COALESCE(
        NULLIF(
            TRIM(
                REGEXP_REPLACE(
                    e.model,
                    '[[:space:]]+',
                    ' '
                )
            ),
            ''
        ),
        'UNKNOWN'
    ) AS equipment_model,

    COALESCE(
        UPPER(
            NULLIF(
                TRIM(e.serial_number),
                ''
            )
        ),
        'UNKNOWN'
    ) AS serial_number,

    COALESCE(
        CAST(s.dispatch_date AS CHAR),
        'UNKNOWN'
    ) AS service_date,

    COALESCE(
        NULLIF(
            TRIM(
                REGEXP_REPLACE(
                    s.technician,
                    '[[:space:]]+',
                    ' '
                )
            ),
            ''
        ),
        'UNKNOWN'
    ) AS technician,

    COALESCE(
        UPPER(
            NULLIF(
                TRIM(
                    REGEXP_REPLACE(
                        s.service_type,
                        '[[:space:]]+',
                        ' '
                    )
                ),
                ''
            )
        ),
        'UNKNOWN'
    ) AS service_type,

    COALESCE(
        NULLIF(
            TRIM(
                REGEXP_REPLACE(
                    s.resolution_summary,
                    '[[:space:]]+',
                    ' '
                )
            ),
            ''
        ),
        'UNKNOWN'
    ) AS resolution,

    COALESCE(
        UPPER(
            NULLIF(
                TRIM(s.status),
                ''
            )
        ),
        'UNKNOWN'
    ) AS status,

    CONCAT_WS(
        ' | ',

        CONCAT(
            'EQUIPMENT MODEL: ',
            COALESCE(
                NULLIF(
                    TRIM(
                        REGEXP_REPLACE(
                            e.model,
                            '[[:space:]]+',
                            ' '
                        )
                    ),
                    ''
                ),
                'UNKNOWN'
            )
        ),

        CONCAT(
            'SERIAL NUMBER: ',
            COALESCE(
                UPPER(
                    NULLIF(
                        TRIM(e.serial_number),
                        ''
                    )
                ),
                'UNKNOWN'
            )
        ),

        s.full_service_context

    ) AS rag_payload

FROM service_logs s

LEFT JOIN equipment_units e
ON e.equipment_id = s.equipment_id

LIMIT 10;

END //

DELIMITER ;


-- ============================================================
-- AUDIT LOG TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS Audit_Logs (
    audit_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id VARCHAR(100) NOT NULL,
    operation VARCHAR(20) NOT NULL,
    old_values LONGTEXT,
    new_values LONGTEXT,
    changed_by VARCHAR(255) NOT NULL,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;


-- ============================================================
-- AUDIT TRIGGERS
-- ============================================================

DROP TRIGGER IF EXISTS before_service_logs_update;
DROP TRIGGER IF EXISTS after_service_logs_insert;
DROP TRIGGER IF EXISTS prevent_audit_update;
DROP TRIGGER IF EXISTS prevent_audit_delete;

DELIMITER //

CREATE TRIGGER before_service_logs_update
BEFORE UPDATE ON service_logs
FOR EACH ROW

BEGIN

INSERT INTO Audit_Logs (
    table_name,
    record_id,
    operation,
    old_values,
    new_values,
    changed_by
)

VALUES (

    'service_logs',

    OLD.dispatch_id,

    'UPDATE',

    JSON_OBJECT(
        'equipment_id', OLD.equipment_id,
        'dispatch_date', OLD.dispatch_date,
        'technician', OLD.technician,
        'service_type', OLD.service_type,
        'hours_spent', OLD.hours_spent,
        'labor_cost', OLD.labor_cost,
        'resolution_summary', OLD.resolution_summary,
        'status', OLD.status
    ),

    JSON_OBJECT(
        'equipment_id', NEW.equipment_id,
        'dispatch_date', NEW.dispatch_date,
        'technician', NEW.technician,
        'service_type', NEW.service_type,
        'hours_spent', NEW.hours_spent,
        'labor_cost', NEW.labor_cost,
        'resolution_summary', NEW.resolution_summary,
        'status', NEW.status
    ),

    USER()

);

END //


CREATE TRIGGER after_service_logs_insert
AFTER INSERT ON service_logs
FOR EACH ROW

BEGIN

INSERT INTO Audit_Logs (
    table_name,
    record_id,
    operation,
    new_values,
    changed_by
)

VALUES (

    'service_logs',

    NEW.dispatch_id,

    'INSERT',

    JSON_OBJECT(
        'equipment_id', NEW.equipment_id,
        'dispatch_date', NEW.dispatch_date,
        'technician', NEW.technician,
        'service_type', NEW.service_type,
        'hours_spent', NEW.hours_spent,
        'labor_cost', NEW.labor_cost,
        'resolution_summary', NEW.resolution_summary,
        'status', NEW.status
    ),

    USER()

);

END //


CREATE TRIGGER prevent_audit_update
BEFORE UPDATE ON Audit_Logs
FOR EACH ROW

BEGIN

SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'Audit logs cannot be modified';

END //


CREATE TRIGGER prevent_audit_delete
BEFORE DELETE ON Audit_Logs
FOR EACH ROW

BEGIN

SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'Audit logs cannot be deleted';

END //

DELIMITER ;


-- ============================================================
-- CUSTOMER SECURITY VIEW
-- ============================================================

CREATE OR REPLACE SQL SECURITY DEFINER
VIEW customer_safe_view AS

SELECT
    customer_id,
    company_name,
    zip,
    created_date,
    status

FROM customers;


CREATE USER IF NOT EXISTS
'limited_user'@'localhost'
IDENTIFIED BY 'Gigavolt2026!';

ALTER USER
'limited_user'@'localhost'
IDENTIFIED BY 'Gigavolt2026!';

GRANT SELECT
ON gigavolt_erp.customer_safe_view
TO 'limited_user'@'localhost';

SQL


# ============================================================
# RUN / VERIFY MILESTONE 2
# ============================================================

mariadb < /tmp/milestone2.sql

mariadb gigavolt_erp -e "
CALL sp_Prepare_RAG_Payloads();
"

mariadb gigavolt_erp -e "
SELECT
TRIGGER_NAME,
EVENT_MANIPULATION,
ACTION_TIMING
FROM information_schema.TRIGGERS
WHERE TRIGGER_SCHEMA='gigavolt_erp';
"

mariadb gigavolt_erp -e "
SELECT *
FROM customer_safe_view
LIMIT 3;
"

echo "============================================================"
echo "MILESTONE 2 COMPLETE"
echo "============================================================"


# ============================================================
# MILESTONE 3 - DISABLE AUTO START / RESTART
# ============================================================

echo "============================================================"
echo "MILESTONE 3 STARTING"
echo "============================================================"

systemctl stop mariadb || true
systemctl disable mariadb

mkdir -p /etc/systemd/system/mariadb.service.d

cat > /etc/systemd/system/mariadb.service.d/override.conf <<'EOF'
[Service]
Restart=no
EOF

systemctl daemon-reload


# ============================================================
# MILESTONE 3 - CHECK grastate.dat
# ============================================================

cat > /usr/local/sbin/galera-check-bootstrap.sh <<'EOF'
#!/bin/bash

F=/var/lib/mysql/grastate.dat

[ -f "$F" ] || {
    echo "grastate.dat not found"
    exit 1
}

echo "=== grastate.dat ==="

cat "$F"

SAFE=$(awk '/safe_to_bootstrap:/ {print $2}' "$F")
SEQ=$(awk '/seqno:/ {print $2}' "$F")

echo ""
echo "Sequence Number: $SEQ"
echo "Safe To Bootstrap: $SAFE"

if [ "$SAFE" = "1" ]; then
    echo "THIS NODE IS SAFE TO BOOTSTRAP"
else
    echo "THIS NODE IS NOT SAFE TO BOOTSTRAP"
    echo "Check the other nodes."
fi
EOF

chmod +x /usr/local/sbin/galera-check-bootstrap.sh


# ============================================================
# MILESTONE 3 - SAFE BOOTSTRAP
# ============================================================

cat > /usr/local/sbin/galera-bootstrap-safe.sh <<'EOF'
#!/bin/bash
set -e

F=/var/lib/mysql/grastate.dat

[ -f "$F" ] || {
    echo "grastate.dat not found"
    exit 1
}

SAFE=$(awk '/safe_to_bootstrap:/ {print $2}' "$F")

echo "Safe To Bootstrap: $SAFE"

if [ "$SAFE" != "1" ]; then
    echo "BOOTSTRAP REFUSED"
    exit 1
fi

systemctl stop mariadb || true

galera_new_cluster

mariadb -e "
SHOW STATUS
WHERE Variable_name IN (
'wsrep_cluster_size',
'wsrep_cluster_status',
'wsrep_connected',
'wsrep_ready',
'wsrep_local_state_comment'
);
"
EOF

chmod +x /usr/local/sbin/galera-bootstrap-safe.sh


# ============================================================
# MILESTONE 3 - RECOVER POSITION
# ============================================================

cat > /usr/local/sbin/galera-recover-position.sh <<'EOF'
#!/bin/bash
set -e

if systemctl is-active --quiet mariadb; then
    echo "Stop MariaDB first."
    exit 1
fi

echo "=== GALERA RECOVERY ==="

galera_recovery

echo ""
echo "Compare the recovered sequence numbers"
echo "on Node A, Node B and Node C."
echo "Use the most advanced node."
EOF

chmod +x /usr/local/sbin/galera-recover-position.sh


# ============================================================
# MILESTONE 3 - VERIFY SETTINGS
# ============================================================

echo "Automatic startup:"
systemctl is-enabled mariadb || true

echo "Restart policy:"
systemctl show mariadb -p Restart

echo "MariaDB status:"
systemctl is-active mariadb || true

echo "============================================================"
echo "MILESTONE 3 BASE SETUP COMPLETE"
echo "============================================================"


# ============================================================
# FINAL STATUS
# ============================================================

echo ""
echo "============================================================"
echo "PROJECT GIGAVOLT SETUP COMPLETE"
echo "============================================================"

echo "MILESTONE 1 COMPLETE"
echo "MILESTONE 2 COMPLETE"
echo "MILESTONE 3 BASE SETUP COMPLETE"

echo ""
echo "Milestone 1:"
echo "s3://projectmilestone1bucket/bucket.txt"

echo ""
echo "Recovery commands:"
echo "sudo galera-check-bootstrap.sh"
echo "sudo galera-bootstrap-safe.sh"
echo "sudo galera-recover-position.sh"

echo ""
echo "ColumnStore will be configured manually on Node 3."

echo "============================================================"

