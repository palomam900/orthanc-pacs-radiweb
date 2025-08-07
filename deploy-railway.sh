#!/bin/bash

# Script de Deploy Railway - Orthanc PACS Radiweb
# Autor: Manus AI
# Data: $(date +%Y-%m-%d)

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[RAILWAY]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[RAILWAY]${NC} $1"
}

error() {
    echo -e "${RED}[RAILWAY]${NC} $1"
}

info() {
    echo -e "${BLUE}[RAILWAY]${NC} $1"
}

# Banner
echo ""
echo "🚂 Railway Deploy - Orthanc PACS Radiweb"
echo "========================================"
echo ""

# Verificar se Railway CLI está instalado
check_railway_cli() {
    if ! command -v railway &> /dev/null; then
        warn "Railway CLI não encontrado. Instalando..."
        
        if command -v npm &> /dev/null; then
            npm install -g @railway/cli
        else
            error "NPM não encontrado. Instale Node.js primeiro:"
            echo "  curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -"
            echo "  sudo apt-get install -y nodejs"
            exit 1
        fi
    fi
    
    log "Railway CLI encontrado ✓"
}

# Verificar login no Railway
check_railway_auth() {
    if ! railway whoami &> /dev/null; then
        warn "Não logado no Railway. Fazendo login..."
        railway login
    fi
    
    local user=$(railway whoami)
    log "Logado como: $user ✓"
}

# Criar projeto no Railway
create_railway_project() {
    local project_name="orthanc-pacs-radiweb"
    
    info "Criando projeto no Railway..."
    
    # Verificar se já existe um projeto linkado
    if railway status &> /dev/null; then
        local current_project=$(railway status | grep "Project:" | awk '{print $2}')
        warn "Projeto já linkado: $current_project"
        
        read -p "Deseja usar o projeto existente? (y/n): " use_existing
        if [ "$use_existing" != "y" ]; then
            railway unlink
        else
            log "Usando projeto existente ✓"
            return 0
        fi
    fi
    
    # Criar novo projeto
    railway init --name "$project_name"
    log "Projeto criado: $project_name ✓"
}

# Adicionar PostgreSQL
add_postgresql() {
    info "Adicionando PostgreSQL..."
    
    # Verificar se PostgreSQL já existe
    if railway services | grep -q "postgresql"; then
        log "PostgreSQL já configurado ✓"
        return 0
    fi
    
    # Adicionar PostgreSQL
    railway add postgresql
    log "PostgreSQL adicionado ✓"
    
    # Aguardar PostgreSQL ficar pronto
    info "Aguardando PostgreSQL ficar pronto..."
    sleep 30
}

# Configurar variáveis de ambiente
configure_environment() {
    info "Configurando variáveis de ambiente..."
    
    # Gerar senhas seguras
    local admin_pass=$(openssl rand -base64 24)
    local viewer_pass=$(openssl rand -base64 16)
    local api_pass=$(openssl rand -base64 16)
    local webhook_secret=$(openssl rand -base64 32)
    
    # Configurar variáveis principais
    railway variables set \
        ADMIN_PASSWORD="$admin_pass" \
        VIEWER_PASSWORD="$viewer_pass" \
        API_PASSWORD="$api_pass" \
        WEBHOOK_SECRET="$webhook_secret" \
        ORTHANC_NAME="RADIWEB_PACS" \
        DICOM_AET="RADIWEB_PACS" \
        ENABLE_HTTPS="true" \
        LOG_LEVEL="default" \
        CONCURRENT_JOBS="4" \
        BACKUP_ENABLED="true" \
        BACKUP_RETENTION_DAYS="7"
    
    log "Variáveis de ambiente configuradas ✓"
    
    # Salvar credenciais localmente
    cat > .env.production << EOF
# Credenciais geradas para Railway
ADMIN_PASSWORD=$admin_pass
VIEWER_PASSWORD=$viewer_pass
API_PASSWORD=$api_pass
WEBHOOK_SECRET=$webhook_secret
EOF
    
    warn "IMPORTANTE: Credenciais salvas em .env.production"
    echo "  Admin: admin / $admin_pass"
    echo "  Viewer: viewer / $viewer_pass"
    echo "  API: api / $api_pass"
    echo ""
}

# Configurar domínio
configure_domain() {
    info "Configurando domínio..."
    
    # Obter URL do Railway
    local railway_url=$(railway domain)
    
    if [ -n "$railway_url" ]; then
        log "URL Railway: $railway_url"
        
        # Atualizar variável de domínio
        railway variables set DOMAIN_NAME="$railway_url"
        
        echo ""
        info "URLs de acesso:"
        echo "  🌐 Interface: https://$railway_url"
        echo "  👁️  Stone Viewer: https://$railway_url/stone-webviewer/"
        echo "  🔍 Health Check: https://$railway_url/health"
        echo "  📊 System Info: https://$railway_url/system"
        echo ""
        
        # Perguntar sobre domínio personalizado
        read -p "Deseja configurar domínio personalizado? (y/n): " setup_custom
        if [ "$setup_custom" = "y" ]; then
            read -p "Digite o domínio (ex: pacs.radiweb.com.br): " custom_domain
            
            if [ -n "$custom_domain" ]; then
                railway domain add "$custom_domain"
                railway variables set DOMAIN_NAME="$custom_domain"
                
                log "Domínio personalizado configurado: $custom_domain"
                warn "Configure o DNS:"
                echo "  CNAME $custom_domain $railway_url"
            fi
        fi
    else
        warn "Não foi possível obter URL do Railway"
    fi
}

# Deploy da aplicação
deploy_application() {
    info "Fazendo deploy da aplicação..."
    
    # Verificar se há mudanças para commit
    if ! git diff --quiet; then
        log "Commitando mudanças..."
        git add .
        git commit -m "Configure Railway deployment - $(date)"
    fi
    
    # Deploy
    railway up --detach
    
    log "Deploy iniciado ✓"
    
    # Aguardar deploy
    info "Aguardando deploy completar..."
    sleep 60
    
    # Verificar status
    railway status
}

# Verificar saúde da aplicação
check_health() {
    info "Verificando saúde da aplicação..."
    
    local railway_url=$(railway domain)
    
    if [ -n "$railway_url" ]; then
        # Aguardar aplicação ficar pronta
        local max_attempts=30
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            if curl -s "https://$railway_url/health" > /dev/null 2>&1; then
                log "Aplicação está saudável ✓"
                break
            fi
            
            echo -n "."
            sleep 10
            attempt=$((attempt + 1))
        done
        
        if [ $attempt -gt $max_attempts ]; then
            error "Aplicação não respondeu no tempo esperado"
            warn "Verifique os logs: railway logs"
            return 1
        fi
        
        # Testar endpoints principais
        echo ""
        info "Testando endpoints..."
        
        if curl -s "https://$railway_url/system" > /dev/null 2>&1; then
            log "✓ Sistema Orthanc"
        else
            warn "✗ Sistema Orthanc não responde"
        fi
        
        if curl -s "https://$railway_url/stone-webviewer/" > /dev/null 2>&1; then
            log "✓ Stone Web Viewer"
        else
            warn "✗ Stone Web Viewer não responde"
        fi
        
    else
        error "URL do Railway não encontrada"
        return 1
    fi
}

# Mostrar resumo final
show_summary() {
    local railway_url=$(railway domain)
    
    echo ""
    echo "🎉 Deploy Railway Concluído!"
    echo "============================"
    echo ""
    echo "📋 Informações do Deploy:"
    echo "  Projeto: $(railway status | grep "Project:" | awk '{print $2}')"
    echo "  URL: https://$railway_url"
    echo "  Status: $(railway status | grep "Status:" | awk '{print $2}')"
    echo ""
    echo "🔐 Credenciais (salvas em .env.production):"
    if [ -f .env.production ]; then
        grep "ADMIN_PASSWORD\|VIEWER_PASSWORD\|API_PASSWORD" .env.production | sed 's/^/  /'
    fi
    echo ""
    echo "🌐 URLs de Acesso:"
    echo "  Interface Principal: https://$railway_url"
    echo "  Stone Web Viewer: https://$railway_url/stone-webviewer/"
    echo "  API REST: https://$railway_url/studies"
    echo "  Health Check: https://$railway_url/health"
    echo ""
    echo "📊 Comandos Úteis:"
    echo "  Ver logs: railway logs"
    echo "  Status: railway status"
    echo "  Variáveis: railway variables"
    echo "  Redeploy: railway up"
    echo ""
    echo "🔧 Configuração DICOM:"
    echo "  AE Title: RADIWEB_PACS"
    echo "  Host: $railway_url"
    echo "  Porta: 4242"
    echo ""
    echo "⚠️  Próximos Passos:"
    echo "  1. Testar envio de imagens DICOM"
    echo "  2. Configurar webhook no sistema Radiweb"
    echo "  3. Configurar backup automatizado"
    echo "  4. Configurar monitoramento"
    echo ""
}

# Menu principal
main_menu() {
    echo "Escolha uma opção:"
    echo "1. Deploy completo (recomendado)"
    echo "2. Apenas criar projeto"
    echo "3. Apenas configurar variáveis"
    echo "4. Apenas fazer deploy"
    echo "5. Verificar status"
    echo "6. Ver logs"
    echo "7. Sair"
    echo ""
    read -p "Opção [1-7]: " choice
    
    case $choice in
        1)
            check_railway_cli
            check_railway_auth
            create_railway_project
            add_postgresql
            configure_environment
            deploy_application
            configure_domain
            check_health
            show_summary
            ;;
        2)
            check_railway_cli
            check_railway_auth
            create_railway_project
            add_postgresql
            ;;
        3)
            configure_environment
            ;;
        4)
            deploy_application
            ;;
        5)
            railway status
            ;;
        6)
            railway logs
            ;;
        7)
            log "Saindo..."
            exit 0
            ;;
        *)
            error "Opção inválida!"
            main_menu
            ;;
    esac
}

# Verificar argumentos
if [ $# -eq 0 ]; then
    main_menu
else
    case $1 in
        "deploy")
            check_railway_cli
            check_railway_auth
            create_railway_project
            add_postgresql
            configure_environment
            deploy_application
            configure_domain
            check_health
            show_summary
            ;;
        "status")
            railway status
            ;;
        "logs")
            railway logs
            ;;
        "help")
            echo "Uso: $0 [deploy|status|logs|help]"
            ;;
        *)
            error "Comando inválido: $1"
            echo "Uso: $0 [deploy|status|logs|help]"
            exit 1
            ;;
    esac
fi

