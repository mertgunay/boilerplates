#!/usr/bin/env bash
# Snapshot the signoz-sqlite volume (alert rules, dashboards, users, integrations).
#
# Restore:
#   docker compose stop signoz
#   docker run --rm -v signoz-sqlite:/dst -v /path/to/backup:/src alpine:3.21 \
#       sh -c 'cd /dst && tar -xzf /src/<backup>.tar.gz'
#   docker compose start signoz
#
# Schedule with cron, systemd timer, or your favourite scheduler.
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/signoz}"
RETENTION_DAYS="${RETENTION_DAYS:-60}"
VOLUME_NAME="${VOLUME_NAME:-signoz-sqlite}"
TS=$(date -u +%Y%m%d-%H%M%S)
OUT_NAME="${VOLUME_NAME}-${TS}.tar.gz"

mkdir -p "$BACKUP_DIR"

docker run --rm \
    -v "${VOLUME_NAME}:/src:ro" \
    -v "${BACKUP_DIR}:/backup" \
    alpine:3.21 \
    sh -c "tar -czf /backup/${OUT_NAME} -C /src ."

find "$BACKUP_DIR" -name "${VOLUME_NAME}-*.tar.gz" -mtime "+${RETENTION_DAYS}" -delete

printf '[%s] backup ok: %s/%s (%s)\n' \
    "$(date -Iseconds)" \
    "$BACKUP_DIR" \
    "$OUT_NAME" \
    "$(du -h "${BACKUP_DIR}/${OUT_NAME}" | cut -f1)"
