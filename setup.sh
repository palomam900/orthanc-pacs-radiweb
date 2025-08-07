#!/bin/bash

# Script de Setup do Orthanc PACS Radiweb
# Autor: Manus AI
# Data: $(date +%Y-%m-%d)

set -e

echo "🏥 Configurando Orthanc PACS Radiweb..."
echo "========================================"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para log
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar se Docker está instalado
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker não está instalado. Por favor, instale o Docker primeiro."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose não está instalado. Por favor, instale o Docker Compose primeiro."
        exit 1
    fi
    
    log "Docker e Docker Compose encontrados ✓"
}

# Criar arquivo .env se não existir
setup_env() {
    if [ ! -f .env ]; then
        log "Criando arquivo .env..."
        cp .env.example .env
        
        # Gerar senhas seguras
        POSTGRES_PASS=$(openssl rand -base64 32)
        ADMIN_PASS=$(openssl rand -base64 16)
        VIEWER_PASS=$(openssl rand -base64 16)
        
        # Substituir no arquivo .env
        sed -i "s/orthanc_secure_password_2024/$POSTGRES_PASS/g" .env
        sed -i "s/admin_radiweb_2024/$ADMIN_PASS/g" .env
        sed -i "s/viewer_radiweb_2024/$VIEWER_PASS/g" .env
        
        log "Arquivo .env criado com senhas seguras geradas automaticamente"
        warn "IMPORTANTE: Anote as credenciais geradas:"
        echo "  - Admin: admin / $ADMIN_PASS"
        echo "  - Viewer: viewer / $VIEWER_PASS"
        echo "  - PostgreSQL: orthanc / $POSTGRES_PASS"
    else
        log "Arquivo .env já existe ✓"
    fi
}

# Criar certificados SSL self-signed para desenvolvimento
create_ssl_certs() {
    if [ ! -f ssl/certificate.pem ]; then
        log "Criando certificados SSL self-signed para desenvolvimento..."
        
        mkdir -p ssl
        
        # Gerar certificado self-signed
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout ssl/private.key \
            -out ssl/certificate.crt \
            -subj "/C=BR/ST=SP/L=São Paulo/O=Radiweb/OU=PACS/CN=pacs.radiweb.com.br"
        
        # Combinar chave e certificado
        cat ssl/private.key ssl/certificate.crt > ssl/certificate.pem
        
        log "Certificados SSL criados ✓"
        warn "ATENÇÃO: Estes são certificados self-signed apenas para desenvolvimento!"
        warn "Para produção, use certificados válidos (Let's Encrypt, etc.)"
    else
        log "Certificados SSL já existem ✓"
    fi
}

# Configurar permissões
setup_permissions() {
    log "Configurando permissões dos diretórios..."
    
    # Criar diretórios se não existirem
    mkdir -p data/orthanc data/postgres logs
    
    # Configurar permissões
    chmod 755 data/orthanc data/postgres
    chmod 600 ssl/private.key 2>/dev/null || true
    chmod 644 ssl/certificate.crt 2>/dev/null || true
    chmod 600 ssl/certificate.pem 2>/dev/null || true
    
    log "Permissões configuradas ✓"
}

# Validar configuração do Orthanc
validate_config() {
    log "Validando configuração do Orthanc..."
    
    if [ ! -f config/orthanc.json ]; then
        error "Arquivo config/orthanc.json não encontrado!"
        exit 1
    fi
    
    # Verificar se é um JSON válido (básico)
    if ! python3 -m json.tool config/orthanc.json > /dev/null 2>&1; then
        error "Arquivo config/orthanc.json contém JSON inválido!"
        exit 1
    fi
    
    log "Configuração do Orthanc validada ✓"
}

# Função para iniciar os serviços
start_services() {
    log "Iniciando serviços..."
    
    # Parar serviços existentes
    docker-compose down 2>/dev/null || true
    
    # Iniciar serviços
    docker-compose up -d
    
    log "Aguardando serviços ficarem prontos..."
    sleep 10
    
    # Verificar status dos serviços
    if docker-compose ps | grep -q "Up"; then
        log "Serviços iniciados com sucesso ✓"
        
        echo ""
        echo "🎉 Orthanc PACS Radiweb configurado com sucesso!"
        echo "=============================================="
        echo ""
        echo "📋 Informações de acesso:"
        echo "  - URL HTTP: http://localhost"
        echo "  - URL HTTPS: https://localhost (certificado self-signed)"
        echo "  - Porta DICOM: 4242"
        echo "  - Stone Web Viewer: http://localhost/stone-webviewer/"
        echo ""
        echo "🔐 Credenciais (verifique o arquivo .env para senhas atuais):"
        echo "  - Usuário Admin: admin"
        echo "  - Usuário Viewer: viewer"
        echo ""
        echo "📊 Monitoramento:"
        echo "  - Status: docker-compose ps"
        echo "  - Logs: docker-compose logs -f"
        echo "  - Health: curl http://localhost/health"
        echo ""
        echo "🛠️  Comandos úteis:"
        echo "  - Parar: docker-compose down"
        echo "  - Reiniciar: docker-compose restart"
        echo "  - Atualizar: docker-compose pull && docker-compose up -d"
        echo ""
    else
        error "Falha ao iniciar alguns serviços. Verifique os logs:"
        docker-compose logs
        exit 1
    fi
}

# Função para mostrar status
show_status() {
    echo ""
    echo "📊 Status dos serviços:"
    docker-compose ps
    
    echo ""
    echo "🔍 Health checks:"
    
    # Verificar Orthanc
    if curl -s http://localhost/system > /dev/null 2>&1; then
        echo "  ✓ Orthanc: OK"
    else
        echo "  ✗ Orthanc: Falha"
    fi
    
    # Verificar Nginx
    if curl -s http://localhost/health > /dev/null 2>&1; then
        echo "  ✓ Nginx: OK"
    else
        echo "  ✗ Nginx: Falha"
    fi
    
    # Verificar PostgreSQL
    if docker-compose exec -T postgres pg_isready -U orthanc > /dev/null 2>&1; then
        echo "  ✓ PostgreSQL: OK"
    else
        echo "  ✗ PostgreSQL: Falha"
    fi
}

# Menu principal
main_menu() {
    echo ""
    echo "🏥 Orthanc PACS Radiweb - Menu de Setup"
    echo "======================================"
    echo "1. Setup completo (recomendado)"
    echo "2. Apenas configurar ambiente"
    echo "3. Apenas criar certificados SSL"
    echo "4. Iniciar serviços"
    echo "5. Mostrar status"
    echo "6. Parar serviços"
    echo "7. Sair"
    echo ""
    read -p "Escolha uma opção [1-7]: " choice
    
    case $choice in
        1)
            check_docker
            setup_env
            create_ssl_certs
            setup_permissions
            validate_config
            start_services
            show_status
            ;;
        2)
            setup_env
            setup_permissions
            ;;
        3)
            create_ssl_certs
            ;;
        4)
            start_services
            ;;
        5)
            show_status
            ;;
        6)
            log "Parando serviços..."
            docker-compose down
            log "Serviços parados ✓"
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

# Verificar se foi passado argumento
if [ $# -eq 0 ]; then
    main_menu
else
    case $1 in
        "setup")
            check_docker
            setup_env
            create_ssl_certs
            setup_permissions
            validate_config
            start_services
            show_status
            ;;
        "start")
            start_services
            ;;
        "stop")
            docker-compose down
            ;;
        "status")
            show_status
            ;;
        "logs")
            docker-compose logs -f
            ;;
        *)
            echo "Uso: $0 [setup|start|stop|status|logs]"
            exit 1
            ;;
    esac
fi

