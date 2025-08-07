#!/bin/bash

# Script de Backup Orthanc PACS Radiweb
# Autor: Manus AI
# Data: $(date +%Y-%m-%d)

set -e

# Configurações
BACKUP_DIR="/backups"
DATE=$(date +%Y%m%d_%H%M%S)
POSTGRES_HOST=${POSTGRES_HOST:-postgres}
POSTGRES_USER=${POSTGRES_USER:-orthanc}
POSTGRES_DB=${POSTGRES_DB:-orthanc}
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[BACKUP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "${YELLOW}[BACKUP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "${RED}[BACKUP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Criar diretório de backup se não existir
mkdir -p $BACKUP_DIR

log "Iniciando backup do Orthanc PACS..."

# Backup do PostgreSQL
log "Fazendo backup do PostgreSQL..."
pg_dump -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB > $BACKUP_DIR/postgres_$DATE.sql

if [ $? -eq 0 ]; then
    log "Backup do PostgreSQL concluído: postgres_$DATE.sql"
else
    error "Falha no backup do PostgreSQL"
    exit 1
fi

# Backup dos dados DICOM (se montado como volume)
if [ -d "/var/lib/orthanc/db" ]; then
    log "Fazendo backup dos dados DICOM..."
    tar -czf $BACKUP_DIR/orthanc_data_$DATE.tar.gz -C /var/lib/orthanc db/
    
    if [ $? -eq 0 ]; then
        log "Backup dos dados DICOM concluído: orthanc_data_$DATE.tar.gz"
    else
        warn "Falha no backup dos dados DICOM (pode não estar disponível)"
    fi
fi

# Backup da configuração
if [ -f "/etc/orthanc/orthanc.json" ]; then
    log "Fazendo backup da configuração..."
    cp /etc/orthanc/orthanc.json $BACKUP_DIR/orthanc_config_$DATE.json
    log "Backup da configuração concluído: orthanc_config_$DATE.json"
fi

# Criar arquivo de metadados do backup
cat > $BACKUP_DIR/backup_metadata_$DATE.json << EOF
{
    "timestamp": "$(date -Iseconds)",
    "date": "$DATE",
    "postgres_backup": "postgres_$DATE.sql",
    "dicom_data_backup": "orthanc_data_$DATE.tar.gz",
    "config_backup": "orthanc_config_$DATE.json",
    "postgres_host": "$POSTGRES_HOST",
    "postgres_user": "$POSTGRES_USER",
    "postgres_db": "$POSTGRES_DB",
    "backup_size": "$(du -sh $BACKUP_DIR/*_$DATE.* | awk '{print $1}' | tr '\n' ' ')"
}
EOF

# Comprimir todos os backups em um arquivo único
log "Comprimindo backup completo..."
tar -czf $BACKUP_DIR/orthanc_full_backup_$DATE.tar.gz -C $BACKUP_DIR \
    postgres_$DATE.sql \
    orthanc_data_$DATE.tar.gz \
    orthanc_config_$DATE.json \
    backup_metadata_$DATE.json

# Remover arquivos individuais
rm -f $BACKUP_DIR/postgres_$DATE.sql \
      $BACKUP_DIR/orthanc_data_$DATE.tar.gz \
      $BACKUP_DIR/orthanc_config_$DATE.json \
      $BACKUP_DIR/backup_metadata_$DATE.json

log "Backup completo criado: orthanc_full_backup_$DATE.tar.gz"

# Calcular tamanho do backup
BACKUP_SIZE=$(du -sh $BACKUP_DIR/orthanc_full_backup_$DATE.tar.gz | awk '{print $1}')
log "Tamanho do backup: $BACKUP_SIZE"

# Limpeza de backups antigos
log "Limpando backups antigos (mais de $RETENTION_DAYS dias)..."
find $BACKUP_DIR -name "orthanc_full_backup_*.tar.gz" -mtime +$RETENTION_DAYS -delete

REMAINING_BACKUPS=$(ls -1 $BACKUP_DIR/orthanc_full_backup_*.tar.gz 2>/dev/null | wc -l)
log "Backups restantes: $REMAINING_BACKUPS"

# Enviar notificação via webhook (se configurado)
if [ ! -z "$WEBHOOK_URL" ]; then
    log "Enviando notificação via webhook..."
    
    WEBHOOK_PAYLOAD=$(cat << EOF
{
    "event": "backup_completed",
    "timestamp": "$(date -Iseconds)",
    "backup_file": "orthanc_full_backup_$DATE.tar.gz",
    "backup_size": "$BACKUP_SIZE",
    "retention_days": $RETENTION_DAYS,
    "remaining_backups": $REMAINING_BACKUPS,
    "status": "success"
}
EOF
)
    
    curl -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -H "X-Webhook-Secret: ${WEBHOOK_SECRET:-}" \
        -d "$WEBHOOK_PAYLOAD" \
        --max-time 30 \
        --silent || warn "Falha ao enviar notificação via webhook"
fi

log "Backup concluído com sucesso!"

# Mostrar resumo
echo ""
echo "📊 Resumo do Backup"
echo "==================="
echo "Data/Hora: $(date)"
echo "Arquivo: orthanc_full_backup_$DATE.tar.gz"
echo "Tamanho: $BACKUP_SIZE"
echo "Localização: $BACKUP_DIR"
echo "Retenção: $RETENTION_DAYS dias"
echo "Backups restantes: $REMAINING_BACKUPS"
echo ""

