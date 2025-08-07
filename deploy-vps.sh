#!/bin/bash

# Script de Deploy VPS - Orthanc PACS Radiweb
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
    echo -e "${GREEN}[VPS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[VPS]${NC} $1"
}

error() {
    echo -e "${RED}[VPS]${NC} $1"
}

info() {
    echo -e "${BLUE}[VPS]${NC} $1"
}

# Banner
echo ""
echo "🖥️  VPS Deploy - Orthanc PACS Radiweb"
echo "====================================="
echo ""

# Verificar se está rodando como root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        warn "Rodando como root. Recomendado usar usuário não-root com sudo."
        read -p "Continuar mesmo assim? (y/n): " continue_root
        if [ "$continue_root" != "y" ]; then
            exit 1
        fi
    fi
}

# Verificar sistema operacional
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        log "Sistema detectado: $OS $VER"
    else
        error "Sistema operacional não suportado"
        exit 1
    fi
}

# Instalar dependências
install_dependencies() {
    info "Instalando dependências..."
    
    # Atualizar sistema
    sudo apt update && sudo apt upgrade -y
    
    # Instalar Docker
    if ! command -v docker &> /dev/null; then
        log "Instalando Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        rm get-docker.sh
    else
        log "Docker já instalado ✓"
    fi
    
    # Instalar Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log "Instalando Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    else
        log "Docker Compose já instalado ✓"
    fi
    
    # Instalar outras dependências
    sudo apt install -y curl wget git openssl ufw fail2ban htop
    
    log "Dependências instaladas ✓"
}

# Configurar firewall
configure_firewall() {
    info "Configurando firewall..."
    
    # Configurar UFW
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # Permitir SSH
    sudo ufw allow ssh
    
    # Permitir HTTP/HTTPS
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    
    # Permitir DICOM
    sudo ufw allow 4242/tcp
    
    # Ativar firewall
    sudo ufw --force enable
    
    log "Firewall configurado ✓"
}

# Configurar fail2ban
configure_fail2ban() {
    info "Configurando fail2ban..."
    
    # Configuração básica do fail2ban
    sudo tee /etc/fail2ban/jail.local > /dev/null << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
EOF
    
    sudo systemctl restart fail2ban
    sudo systemctl enable fail2ban
    
    log "Fail2ban configurado ✓"
}

# Configurar ambiente
setup_environment() {
    info "Configurando ambiente..."
    
    # Criar arquivo .env se não existir
    if [ ! -f .env ]; then
        log "Criando arquivo .env..."
        cp .env.example .env
        
        # Gerar senhas seguras
        POSTGRES_PASS=$(openssl rand -base64 32)
        ADMIN_PASS=$(openssl rand -base64 24)
        VIEWER_PASS=$(openssl rand -base64 16)
        API_PASS=$(openssl rand -base64 16)
        WEBHOOK_SECRET=$(openssl rand -base64 32)
        REDIS_PASS=$(openssl rand -base64 16)
        GRAFANA_PASS=$(openssl rand -base64 16)
        
        # Substituir no arquivo .env
        sed -i "s/orthanc_secure_password_2024/$POSTGRES_PASS/g" .env
        sed -i "s/admin_radiweb_2024/$ADMIN_PASS/g" .env
        sed -i "s/viewer_radiweb_2024/$VIEWER_PASS/g" .env
        sed -i "s/webhook_secret_key_2024/$WEBHOOK_SECRET/g" .env
        
        # Adicionar novas variáveis
        echo "API_PASSWORD=$API_PASS" >> .env
        echo "REDIS_PASSWORD=$REDIS_PASS" >> .env
        echo "GRAFANA_PASSWORD=$GRAFANA_PASS" >> .env
        
        log "Arquivo .env criado com senhas seguras"
        warn "IMPORTANTE: Anote as credenciais:"
        echo "  - Admin: admin / $ADMIN_PASS"
        echo "  - Viewer: viewer / $VIEWER_PASS"
        echo "  - API: api / $API_PASS"
        echo "  - Grafana: admin / $GRAFANA_PASS"
    else
        log "Arquivo .env já existe ✓"
    fi
    
    # Configurar domínio
    read -p "Digite o domínio (ex: pacs.radiweb.com.br): " domain_name
    if [ -n "$domain_name" ]; then
        sed -i "s/DOMAIN_NAME=.*/DOMAIN_NAME=$domain_name/g" .env
        log "Domínio configurado: $domain_name"
    fi
    
    # Configurar email para Let's Encrypt
    read -p "Digite o email para Let's Encrypt: " letsencrypt_email
    if [ -n "$letsencrypt_email" ]; then
        sed -i "s/LETSENCRYPT_EMAIL=.*/LETSENCRYPT_EMAIL=$letsencrypt_email/g" .env
        log "Email configurado: $letsencrypt_email"
    fi
}

# Configurar SSL com Let's Encrypt
setup_ssl() {
    info "Configurando SSL com Let's Encrypt..."
    
    # Carregar variáveis de ambiente
    source .env
    
    if [ -z "$DOMAIN_NAME" ] || [ "$DOMAIN_NAME" = "pacs.radiweb.com.br" ]; then
        warn "Domínio não configurado. Usando certificados self-signed."
        
        # Criar certificados self-signed
        mkdir -p ssl
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout ssl/private.key \
            -out ssl/certificate.crt \
            -subj "/C=BR/ST=SP/L=São Paulo/O=Radiweb/OU=PACS/CN=localhost"
        
        log "Certificados self-signed criados ✓"
        return 0
    fi
    
    # Verificar se domínio resolve para este servidor
    local server_ip=$(curl -s ifconfig.me)
    local domain_ip=$(dig +short $DOMAIN_NAME)
    
    if [ "$server_ip" != "$domain_ip" ]; then
        warn "Domínio $DOMAIN_NAME não resolve para este servidor ($server_ip vs $domain_ip)"
        warn "Configure o DNS antes de continuar com Let's Encrypt"
        
        read -p "Continuar com certificados self-signed? (y/n): " use_selfsigned
        if [ "$use_selfsigned" = "y" ]; then
            mkdir -p ssl
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout ssl/private.key \
                -out ssl/certificate.crt \
                -subj "/C=BR/ST=SP/L=São Paulo/O=Radiweb/OU=PACS/CN=$DOMAIN_NAME"
            log "Certificados self-signed criados ✓"
        fi
        return 0
    fi
    
    # Iniciar serviços para obter certificado
    log "Iniciando serviços temporários para Let's Encrypt..."
    docker-compose -f docker-compose.vps.yml up -d nginx
    sleep 10
    
    # Obter certificado Let's Encrypt
    log "Obtendo certificado Let's Encrypt para $DOMAIN_NAME..."
    docker-compose -f docker-compose.vps.yml --profile certbot run --rm certbot \
        certbot certonly --webroot --webroot-path=/var/www/certbot \
        -d $DOMAIN_NAME --email $LETSENCRYPT_EMAIL \
        --agree-tos --no-eff-email --force-renewal
    
    if [ $? -eq 0 ]; then
        log "Certificado Let's Encrypt obtido com sucesso ✓"
        
        # Configurar renovação automática
        (crontab -l 2>/dev/null; echo "0 12 * * * docker-compose -f $(pwd)/docker-compose.vps.yml --profile certbot run --rm certbot renew --quiet && docker-compose -f $(pwd)/docker-compose.vps.yml restart nginx") | crontab -
        log "Renovação automática configurada ✓"
    else
        error "Falha ao obter certificado Let's Encrypt"
        warn "Usando certificados self-signed como fallback"
        
        mkdir -p ssl
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout ssl/private.key \
            -out ssl/certificate.crt \
            -subj "/C=BR/ST=SP/L=São Paulo/O=Radiweb/OU=PACS/CN=$DOMAIN_NAME"
    fi
}

# Deploy da aplicação
deploy_application() {
    info "Fazendo deploy da aplicação..."
    
    # Parar serviços existentes
    docker-compose -f docker-compose.vps.yml down 2>/dev/null || true
    
    # Criar diretórios necessários
    mkdir -p data/orthanc data/postgres logs/nginx backups
    
    # Configurar permissões
    sudo chown -R $USER:$USER data/ logs/ backups/
    chmod 755 data/orthanc data/postgres
    
    # Iniciar serviços
    log "Iniciando serviços..."
    docker-compose -f docker-compose.vps.yml up -d
    
    # Aguardar serviços ficarem prontos
    info "Aguardando serviços ficarem prontos..."
    sleep 30
    
    # Verificar status
    docker-compose -f docker-compose.vps.yml ps
    
    log "Deploy concluído ✓"
}

# Configurar backup automático
setup_backup() {
    info "Configurando backup automático..."
    
    # Adicionar cron job para backup
    (crontab -l 2>/dev/null; echo "0 2 * * * cd $(pwd) && docker-compose -f docker-compose.vps.yml --profile backup exec backup /scripts/backup.sh") | crontab -
    
    log "Backup automático configurado (diário às 2h) ✓"
}

# Configurar monitoramento
setup_monitoring() {
    read -p "Deseja configurar monitoramento (Prometheus/Grafana)? (y/n): " setup_mon
    
    if [ "$setup_mon" = "y" ]; then
        info "Configurando monitoramento..."
        
        # Criar configuração do Prometheus
        mkdir -p monitoring
        cat > monitoring/prometheus.yml << EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'orthanc'
    static_configs:
      - targets: ['orthanc:8042']
  
  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx:80']
  
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:5432']
EOF
        
        # Iniciar serviços de monitoramento
        docker-compose -f docker-compose.vps.yml --profile monitoring up -d
        
        log "Monitoramento configurado ✓"
        info "Grafana: http://$(curl -s ifconfig.me):3000 (admin/senha_do_env)"
        info "Prometheus: http://$(curl -s ifconfig.me):9090"
    fi
}

# Verificar saúde da aplicação
check_health() {
    info "Verificando saúde da aplicação..."
    
    local server_ip=$(curl -s ifconfig.me)
    source .env
    
    # Aguardar aplicação ficar pronta
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost/health" > /dev/null 2>&1; then
            log "Aplicação está saudável ✓"
            break
        fi
        
        echo -n "."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "Aplicação não respondeu no tempo esperado"
        warn "Verifique os logs: docker-compose -f docker-compose.vps.yml logs"
        return 1
    fi
    
    # Testar endpoints
    echo ""
    info "Testando endpoints..."
    
    if curl -s "http://localhost/system" > /dev/null 2>&1; then
        log "✓ Sistema Orthanc"
    else
        warn "✗ Sistema Orthanc não responde"
    fi
    
    if curl -s "http://localhost/stone-webviewer/" > /dev/null 2>&1; then
        log "✓ Stone Web Viewer"
    else
        warn "✗ Stone Web Viewer não responde"
    fi
}

# Mostrar resumo final
show_summary() {
    local server_ip=$(curl -s ifconfig.me)
    source .env
    
    echo ""
    echo "🎉 Deploy VPS Concluído!"
    echo "========================"
    echo ""
    echo "📋 Informações do Servidor:"
    echo "  IP: $server_ip"
    echo "  Domínio: ${DOMAIN_NAME:-localhost}"
    echo "  OS: $OS $VER"
    echo ""
    echo "🔐 Credenciais (arquivo .env):"
    echo "  Admin: admin / $(grep ADMIN_PASSWORD .env | cut -d'=' -f2)"
    echo "  Viewer: viewer / $(grep VIEWER_PASSWORD .env | cut -d'=' -f2)"
    echo "  API: api / $(grep API_PASSWORD .env | cut -d'=' -f2)"
    echo ""
    echo "🌐 URLs de Acesso:"
    if [ "$DOMAIN_NAME" != "localhost" ]; then
        echo "  HTTPS: https://$DOMAIN_NAME"
        echo "  Stone Viewer: https://$DOMAIN_NAME/stone-webviewer/"
        echo "  Health: https://$DOMAIN_NAME/health"
    fi
    echo "  HTTP: http://$server_ip"
    echo "  Stone Viewer: http://$server_ip/stone-webviewer/"
    echo "  Health: http://$server_ip/health"
    echo ""
    echo "🔧 Configuração DICOM:"
    echo "  AE Title: RADIWEB_PACS"
    echo "  Host: $server_ip"
    echo "  Porta: 4242"
    echo ""
    echo "📊 Comandos Úteis:"
    echo "  Status: docker-compose -f docker-compose.vps.yml ps"
    echo "  Logs: docker-compose -f docker-compose.vps.yml logs -f"
    echo "  Restart: docker-compose -f docker-compose.vps.yml restart"
    echo "  Backup: docker-compose -f docker-compose.vps.yml --profile backup exec backup /scripts/backup.sh"
    echo ""
    echo "🛡️  Segurança:"
    echo "  Firewall: sudo ufw status"
    echo "  Fail2ban: sudo fail2ban-client status"
    echo "  SSL: $([ -f /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem ] && echo "Let's Encrypt" || echo "Self-signed")"
    echo ""
}

# Menu principal
main_menu() {
    echo "Escolha uma opção:"
    echo "1. Deploy completo (recomendado)"
    echo "2. Apenas instalar dependências"
    echo "3. Apenas configurar ambiente"
    echo "4. Apenas configurar SSL"
    echo "5. Apenas fazer deploy"
    echo "6. Verificar status"
    echo "7. Ver logs"
    echo "8. Sair"
    echo ""
    read -p "Opção [1-8]: " choice
    
    case $choice in
        1)
            check_root
            check_os
            install_dependencies
            configure_firewall
            configure_fail2ban
            setup_environment
            setup_ssl
            deploy_application
            setup_backup
            setup_monitoring
            check_health
            show_summary
            ;;
        2)
            install_dependencies
            ;;
        3)
            setup_environment
            ;;
        4)
            setup_ssl
            ;;
        5)
            deploy_application
            ;;
        6)
            docker-compose -f docker-compose.vps.yml ps
            ;;
        7)
            docker-compose -f docker-compose.vps.yml logs -f
            ;;
        8)
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
            check_root
            check_os
            install_dependencies
            configure_firewall
            configure_fail2ban
            setup_environment
            setup_ssl
            deploy_application
            setup_backup
            setup_monitoring
            check_health
            show_summary
            ;;
        "status")
            docker-compose -f docker-compose.vps.yml ps
            ;;
        "logs")
            docker-compose -f docker-compose.vps.yml logs -f
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

