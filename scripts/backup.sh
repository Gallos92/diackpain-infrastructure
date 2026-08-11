#!/bin/bash
BACKUP_DIR="/home/ubuntu/diackpain/backups"
S3_BUCKET="diackpain-backups-2026"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
DB_NAME="diackpain"

# Create backup locally
BACKUP_FILE="diackpain_$TIMESTAMP.sql.gz"
docker compose exec -T db pg_dump -U diackuser $DB_NAME | gzip > "$BACKUP_DIR/$BACKUP_FILE"

# Upload to S3
aws s3 cp "$BACKUP_DIR/$BACKUP_FILE" "s3://$S3_BUCKET/$BACKUP_FILE"

# Keep only last 7 days locally
find $BACKUP_DIR -name "diackpain_*.sql.gz" -mtime +7 -delete

echo "Backup completed and uploaded to S3: $BACKUP_FILE"
