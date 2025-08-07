#!/bin/bash

# Script de Restauração Orthanc PACS Radiweb
# Autor: Manus AI
# Data: $(date +%Y-%m-%d)

set -e

# Configurações
BACKUP_DIR="/backups"
POSTGRES_HOST=${POSTGRES_HOST:-postgres}
POSTGRES_USER=${POSTGRES_USER:-orthanc}
POSTGRES_DB=${POSTGRES_DB:-orthanc}

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[RESTORE]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "${YELLOW}[RESTORE]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "${RED}[RESTORE]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

info() {
    echo -e "${BLUE}[RESTORE]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Função para mostrar uso
show_usage() {
    echo "Uso: $0 [BACKUP_FILE]"
    echo ""
    echo "Opções:"
    echo "  BACKUP_FILE    Arquivo de backup para restaurar (opcional)"
    echo ""
    echo "Exemplos:"
    echo "  $0                                    # Lista backups disponíveis"
    echo "  $0 orthanc_full_backup_20240101_120000.tar.gz"
    echo ""
}

# Função para listar backups disponíveis
list_backups() {
    echo ""
    echo "📋 Backups disponíveis em $BACKUP_DIR:"
    echo "========================================"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        warn "Diretório de backup não encontrado: $BACKUP_DIR"
        return 1
    fi
    
    BACKUPS=$(ls -1t $BACKUP_DIR/orthanc_full_backup_*.tar.gz 2>/dev/null || true)
    
    if [ -z "$BACKUPS" ]; then
        warn "Nenhum backup encontrado"
        return 1
    fi
    
    echo ""
    printf "%-5s %-35s %-15s %-20s\n" "Nº" "Arquivo" "Tamanho" "Data"
    printf "%-5s %-35s %-15s %-20s\n" "---" "-----------------------------------" "---------------" "--------------------"
    
    i=1
    for backup in $BACKUPS; do
        filename=$(basename "$backup")
        size=$(du -sh "$backup" | awk '{print $1}')
        date=$(stat -c %y "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)
        printf "%-5s %-35s %-15s %-20s\n" "$i" "$filename" "$size" "$date"
        i=$((i+1))
    done
    
    echo ""
}

# Função para confirmar ação
confirm_action() {
    local message="$1"
    echo ""
    warn "$message"
    read -p "Tem certeza? Digite 'sim' para continuar: " confirmation
    
    if [ "$confirmation" != "sim" ]; then
        log "Operação cancelada pelo usuário"
        exit 0
    fi
}

# Função para extrair backup
extract_backup() {
    local backup_file="$1"
    local temp_dir="/tmp/orthanc_restore_$$"
    
    log "Extraindo backup: $backup_file"
    
    mkdir -p "$temp_dir"
    tar -xzf "$backup_file" -C "$temp_dir"
    
    echo "$temp_dir"
}

# Função para restaurar PostgreSQL
restore_postgres() {
    local sql_file="$1"
    
    if [ ! -f "$sql_file" ]; then
        error "Arquivo SQL não encontrado: $sql_file"
        return 1
    fi
    
    log "Restaurando PostgreSQL..."
    
    # Verificar conexão com PostgreSQL
    if ! pg_isready -h $POSTGRES_HOST -U $POSTGRES_USER; then
        error "Não foi possível conectar ao PostgreSQL"
        return 1
    fi
    
    # Fazer backup atual antes de restaurar
    local current_backup="/tmp/current_backup_$(date +%Y%m%d_%H%M%S).sql"
    log "Fazendo backup atual antes da restauração..."
    pg_dump -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB > "$current_backup"
    log "Backup atual salvo em: $current_backup"
    
    # Restaurar banco
    log "Restaurando dados do PostgreSQL..."
    psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB < "$sql_file"
    
    if [ $? -eq 0 ]; then
        log "PostgreSQL restaurado com sucesso"
        rm -f "$current_backup"
        return 0
    else
        error "Falha na restauração do PostgreSQL"
        warn "Restaurando backup atual..."
        psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB < "$current_backup"
        return 1
    fi
}

# Função para restaurar dados DICOM
restore_dicom_data() {
    local data_file="$1"
    local target_dir="/var/lib/orthanc"
    
    if [ ! -f "$data_file" ]; then
        warn "Arquivo de dados DICOM não encontrado: $data_file"
        return 0
    fi
    
    if [ ! -d "$target_dir" ]; then
        warn "Diretório de dados DICOM não encontrado: $target_dir"
        return 0
    fi
    
    log "Restaurando dados DICOM..."
    
    # Fazer backup dos dados atuais
    local current_backup="/tmp/current_dicom_$(date +%Y%m%d_%H%M%S).tar.gz"
    log "Fazendo backup dos dados DICOM atuais..."
    tar -czf "$current_backup" -C "$target_dir" db/ 2>/dev/null || true
    
    # Restaurar dados
    tar -xzf "$data_file" -C "$target_dir"
    
    if [ $? -eq 0 ]; then
        log "Dados DICOM restaurados com sucesso"
        rm -f "$current_backup"
        return 0
    else
        error "Falha na restauração dos dados DICOM"
        warn "Restaurando dados atuais..."
        tar -xzf "$current_backup" -C "$target_dir" 2>/dev/null || true
        return 1
    fi
}

# Função para restaurar configuração
restore_config() {
    local config_file="$1"
    local target_file="/etc/orthanc/orthanc.json"
    
    if [ ! -f "$config_file" ]; then
        warn "Arquivo de configuração não encontrado: $config_file"
        return 0
    fi
    
    log "Restaurando configuração..."
    
    # Fazer backup da configuração atual
    if [ -f "$target_file" ]; then
        local current_backup="/tmp/current_config_$(date +%Y%m%d_%H%M%S).json"
        cp "$target_file" "$current_backup"
        log "Backup da configuração atual salvo em: $current_backup"
    fi
    
    # Restaurar configuração
    cp "$config_file" "$target_file"
    
    if [ $? -eq 0 ]; then
        log "Configuração restaurada com sucesso"
        return 0
    else
        error "Falha na restauração da configuração"
        return 1
    fi
}

# Função principal de restauração
restore_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        error "Arquivo de backup não encontrado: $backup_file"
        exit 1
    fi
    
    log "Iniciando restauração do backup: $(basename $backup_file)"
    
    # Extrair backup
    local temp_dir=$(extract_backup "$backup_file")
    
    # Verificar conteúdo do backup
    local postgres_file="$temp_dir/postgres_*.sql"
    local dicom_file="$temp_dir/orthanc_data_*.tar.gz"
    local config_file="$temp_dir/orthanc_config_*.json"
    local metadata_file="$temp_dir/backup_metadata_*.json"
    
    # Expandir wildcards
    postgres_file=$(ls $postgres_file 2>/dev/null | head -1)
    dicom_file=$(ls $dicom_file 2>/dev/null | head -1)
    config_file=$(ls $config_file 2>/dev/null | head -1)
    metadata_file=$(ls $metadata_file 2>/dev/null | head -1)
    
    # Mostrar informações do backup
    if [ -f "$metadata_file" ]; then
        log "Informações do backup:"
        cat "$metadata_file" | python3 -m json.tool 2>/dev/null || cat "$metadata_file"
        echo ""
    fi
    
    # Confirmar restauração
    confirm_action "Esta operação irá substituir os dados atuais do Orthanc!"
    
    # Parar serviços (se estiver rodando via Docker Compose)
    if command -v docker-compose &> /dev/null; then
        log "Parando serviços..."
        docker-compose stop orthanc 2>/dev/null || true
    fi
    
    # Restaurar componentes
    local success=true
    
    # PostgreSQL
    if [ -f "$postgres_file" ]; then
        restore_postgres "$postgres_file" || success=false
    fi
    
    # Dados DICOM
    if [ -f "$dicom_file" ]; then
        restore_dicom_data "$dicom_file" || success=false
    fi
    
    # Configuração
    if [ -f "$config_file" ]; then
        restore_config "$config_file" || success=false
    fi
    
    # Limpeza
    rm -rf "$temp_dir"
    
    # Reiniciar serviços
    if command -v docker-compose &> /dev/null; then
        log "Reiniciando serviços..."
        docker-compose start orthanc 2>/dev/null || true
    fi
    
    # Resultado
    if [ "$success" = true ]; then
        log "Restauração concluída com sucesso!"
        
        # Enviar notificação via webhook (se configurado)
        if [ ! -z "$WEBHOOK_URL" ]; then
            log "Enviando notificação via webhook..."
            
            WEBHOOK_PAYLOAD=$(cat << EOF
{
    "event": "restore_completed",
    "timestamp": "$(date -Iseconds)",
    "backup_file": "$(basename $backup_file)",
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
        
        echo ""
        echo "🎉 Restauração Concluída!"
        echo "========================"
        echo "Backup restaurado: $(basename $backup_file)"
        echo "Data/Hora: $(date)"
        echo ""
        echo "⚠️  Recomendações pós-restauração:"
        echo "1. Verificar se os serviços estão funcionando"
        echo "2. Testar acesso ao Orthanc"
        echo "3. Verificar integridade dos dados DICOM"
        echo "4. Fazer um novo backup de segurança"
        echo ""
        
    else
        error "Falha na restauração! Verifique os logs acima."
        exit 1
    fi
}

# Script principal
main() {
    echo ""
    echo "🔄 Orthanc PACS Radiweb - Restauração de Backup"
    echo "==============================================="
    
    if [ $# -eq 0 ]; then
        list_backups
        echo ""
        echo "Para restaurar um backup, execute:"
        echo "$0 <nome_do_arquivo_backup>"
        exit 0
    fi
    
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_usage
        exit 0
    fi
    
    local backup_file="$1"
    
    # Se não for caminho absoluto, assumir que está no diretório de backup
    if [[ "$backup_file" != /* ]]; then
        backup_file="$BACKUP_DIR/$backup_file"
    fi
    
    restore_backup "$backup_file"
}

# Executar script principal
main "$@"

