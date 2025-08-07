#!/bin/bash

# Script de Teste de Conectividade - Orthanc PACS Radiweb
# Autor: Manus AI
# Data: $(date +%Y-%m-%d)

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configurações padrão
DOMAIN="${DOMAIN:-pacs.radiweb.com.br}"
DICOM_PORT="${DICOM_PORT:-4242}"
HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-443}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin}"

# Funções de log
log() {
    echo -e "${GREEN}[TEST]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

error() {
    echo -e "${RED}[TEST]${NC} $1"
}

info() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

success() {
    echo -e "${GREEN}✅${NC} $1"
}

fail() {
    echo -e "${RED}❌${NC} $1"
}

# Banner
echo ""
echo "🔍 Teste de Conectividade - Orthanc PACS Radiweb"
echo "==============================================="
echo ""
echo "Domínio: $DOMAIN"
echo "Porta DICOM: $DICOM_PORT"
echo ""

# Carregar configurações do .env se existir
if [ -f .env ]; then
    source .env
    DOMAIN="${DOMAIN_NAME:-$DOMAIN}"
    ADMIN_PASS="${ADMIN_PASSWORD:-$ADMIN_PASS}"
    info "Configurações carregadas do .env"
fi

# Teste 1: DNS Resolution
test_dns() {
    info "📡 Testando resolução DNS..."
    
    if nslookup $DOMAIN > /dev/null 2>&1; then
        local ip=$(nslookup $DOMAIN | grep -A1 "Name:" | tail -1 | awk '{print $2}')
        success "DNS OK - $DOMAIN resolve para $ip"
        return 0
    else
        fail "DNS falhou - $DOMAIN não resolve"
        return 1
    fi
}

# Teste 2: Ping
test_ping() {
    info "🏓 Testando conectividade básica..."
    
    if ping -c 3 $DOMAIN > /dev/null 2>&1; then
        success "Ping OK - Servidor responde"
        return 0
    else
        fail "Ping falhou - Servidor não responde"
        return 1
    fi
}

# Teste 3: HTTP
test_http() {
    info "🌐 Testando HTTP..."
    
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://$DOMAIN/health 2>/dev/null || echo "000")
    
    if [ "$http_code" = "200" ]; then
        success "HTTP OK - Status 200"
        return 0
    elif [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
        success "HTTP OK - Redirecionamento para HTTPS (Status $http_code)"
        return 0
    else
        fail "HTTP falhou - Status $http_code"
        return 1
    fi
}

# Teste 4: HTTPS
test_https() {
    info "🔒 Testando HTTPS..."
    
    local https_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 https://$DOMAIN/health 2>/dev/null || echo "000")
    
    if [ "$https_code" = "200" ]; then
        success "HTTPS OK - Status 200"
        
        # Verificar certificado SSL
        local cert_info=$(echo | openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
        if [ $? -eq 0 ]; then
            local expiry=$(echo "$cert_info" | grep "notAfter" | cut -d= -f2)
            success "Certificado SSL válido - Expira em: $expiry"
        fi
        return 0
    else
        fail "HTTPS falhou - Status $https_code"
        return 1
    fi
}

# Teste 5: Porta DICOM
test_dicom_port() {
    info "🏥 Testando porta DICOM..."
    
    if command -v nc > /dev/null 2>&1; then
        if nc -z -w5 $DOMAIN $DICOM_PORT 2>/dev/null; then
            success "Porta DICOM OK - $DICOM_PORT está aberta"
            return 0
        else
            fail "Porta DICOM falhou - $DICOM_PORT não está acessível"
            return 1
        fi
    else
        warn "netcat não disponível - instalando..."
        if command -v apt > /dev/null 2>&1; then
            sudo apt update && sudo apt install -y netcat
            test_dicom_port
        else
            warn "Não foi possível instalar netcat - pulando teste de porta DICOM"
            return 0
        fi
    fi
}

# Teste 6: Stone Web Viewer
test_stone_viewer() {
    info "👁️ Testando Stone Web Viewer..."
    
    local response=$(curl -s --max-time 10 https://$DOMAIN/stone-webviewer/ 2>/dev/null || echo "")
    
    if echo "$response" | grep -q -i "stone\|viewer\|orthanc"; then
        success "Stone Web Viewer OK - Interface carregando"
        return 0
    else
        fail "Stone Web Viewer falhou - Interface não carrega"
        return 1
    fi
}

# Teste 7: API Orthanc
test_api() {
    info "🔌 Testando API Orthanc..."
    
    # Teste sem autenticação primeiro
    local response=$(curl -s --max-time 10 https://$DOMAIN/system 2>/dev/null || echo "")
    
    if echo "$response" | grep -q "Name\|Version"; then
        success "API OK - Acesso público funcionando"
        return 0
    fi
    
    # Teste com autenticação
    local auth_response=$(curl -s --max-time 10 -u "$ADMIN_USER:$ADMIN_PASS" https://$DOMAIN/system 2>/dev/null || echo "")
    
    if echo "$auth_response" | grep -q "Name\|Version"; then
        success "API OK - Autenticação funcionando"
        return 0
    else
        fail "API falhou - Verifique credenciais ($ADMIN_USER:***)"
        return 1
    fi
}

# Teste 8: DICOMweb
test_dicomweb() {
    info "🔬 Testando DICOMweb..."
    
    local dicomweb_response=$(curl -s --max-time 10 https://$DOMAIN/dicom-web/studies 2>/dev/null || echo "")
    
    if [ $? -eq 0 ]; then
        success "DICOMweb OK - Endpoint acessível"
        return 0
    else
        fail "DICOMweb falhou - Endpoint não acessível"
        return 1
    fi
}

# Teste 9: Performance
test_performance() {
    info "⚡ Testando performance..."
    
    # Criar arquivo de formato para curl
    cat > /tmp/curl-format.txt << 'EOF'
     time_namelookup:  %{time_namelookup}\n
        time_connect:  %{time_connect}\n
     time_appconnect:  %{time_appconnect}\n
    time_pretransfer:  %{time_pretransfer}\n
       time_redirect:  %{time_redirect}\n
  time_starttransfer:  %{time_starttransfer}\n
                     ----------\n
          time_total:  %{time_total}\n
EOF
    
    local timing=$(curl -w "@/tmp/curl-format.txt" -o /dev/null -s https://$DOMAIN/health 2>/dev/null)
    local total_time=$(echo "$timing" | grep "time_total" | awk '{print $2}')
    
    if [ -n "$total_time" ]; then
        if (( $(echo "$total_time < 2.0" | bc -l) )); then
            success "Performance OK - Tempo de resposta: ${total_time}s"
        elif (( $(echo "$total_time < 5.0" | bc -l) )); then
            warn "Performance aceitável - Tempo de resposta: ${total_time}s"
        else
            fail "Performance ruim - Tempo de resposta: ${total_time}s"
        fi
        
        echo "$timing" | sed 's/^/    /'
    else
        warn "Não foi possível medir performance"
    fi
    
    rm -f /tmp/curl-format.txt
}

# Teste 10: Verificação de Segurança
test_security() {
    info "🛡️ Testando configurações de segurança..."
    
    # Verificar headers de segurança
    local headers=$(curl -s -I https://$DOMAIN/ 2>/dev/null || echo "")
    
    if echo "$headers" | grep -q "Strict-Transport-Security"; then
        success "HSTS configurado"
    else
        warn "HSTS não configurado"
    fi
    
    if echo "$headers" | grep -q "X-Frame-Options"; then
        success "X-Frame-Options configurado"
    else
        warn "X-Frame-Options não configurado"
    fi
    
    if echo "$headers" | grep -q "X-Content-Type-Options"; then
        success "X-Content-Type-Options configurado"
    else
        warn "X-Content-Type-Options não configurado"
    fi
}

# Função principal de teste
run_all_tests() {
    local total_tests=0
    local passed_tests=0
    
    echo "🚀 Iniciando testes de conectividade..."
    echo ""
    
    # Lista de testes
    tests=(
        "test_dns"
        "test_ping"
        "test_http"
        "test_https"
        "test_dicom_port"
        "test_stone_viewer"
        "test_api"
        "test_dicomweb"
        "test_performance"
        "test_security"
    )
    
    # Executar testes
    for test in "${tests[@]}"; do
        total_tests=$((total_tests + 1))
        if $test; then
            passed_tests=$((passed_tests + 1))
        fi
        echo ""
    done
    
    # Resumo
    echo "📊 Resumo dos Testes"
    echo "===================="
    echo "Total: $total_tests"
    echo "Passou: $passed_tests"
    echo "Falhou: $((total_tests - passed_tests))"
    echo ""
    
    if [ $passed_tests -eq $total_tests ]; then
        success "Todos os testes passaram! 🎉"
        echo ""
        echo "✅ Seu Orthanc PACS está funcionando perfeitamente!"
        echo ""
        echo "🌐 URLs de acesso:"
        echo "  Interface: https://$DOMAIN"
        echo "  Stone Viewer: https://$DOMAIN/stone-webviewer/"
        echo "  API: https://$DOMAIN/system"
        echo ""
        echo "🏥 Configuração DICOM:"
        echo "  AE Title: RADIWEB_PACS"
        echo "  Host: $DOMAIN"
        echo "  Porta: $DICOM_PORT"
        echo ""
        return 0
    else
        error "Alguns testes falharam. Verifique a configuração."
        return 1
    fi
}

# Função para teste específico
run_specific_test() {
    local test_name="$1"
    
    case $test_name in
        "dns")
            test_dns
            ;;
        "ping")
            test_ping
            ;;
        "http")
            test_http
            ;;
        "https")
            test_https
            ;;
        "dicom")
            test_dicom_port
            ;;
        "stone")
            test_stone_viewer
            ;;
        "api")
            test_api
            ;;
        "dicomweb")
            test_dicomweb
            ;;
        "performance")
            test_performance
            ;;
        "security")
            test_security
            ;;
        *)
            error "Teste inválido: $test_name"
            echo "Testes disponíveis: dns, ping, http, https, dicom, stone, api, dicomweb, performance, security"
            return 1
            ;;
    esac
}

# Menu de ajuda
show_help() {
    echo "Uso: $0 [opções] [teste]"
    echo ""
    echo "Opções:"
    echo "  -d, --domain DOMAIN    Domínio a testar (padrão: pacs.radiweb.com.br)"
    echo "  -p, --port PORT        Porta DICOM (padrão: 4242)"
    echo "  -u, --user USER        Usuário admin (padrão: admin)"
    echo "  -P, --password PASS    Senha admin"
    echo "  -h, --help             Mostrar esta ajuda"
    echo ""
    echo "Testes disponíveis:"
    echo "  dns          Resolução DNS"
    echo "  ping         Conectividade básica"
    echo "  http         Acesso HTTP"
    echo "  https        Acesso HTTPS"
    echo "  dicom        Porta DICOM"
    echo "  stone        Stone Web Viewer"
    echo "  api          API Orthanc"
    echo "  dicomweb     DICOMweb"
    echo "  performance  Teste de performance"
    echo "  security     Configurações de segurança"
    echo ""
    echo "Exemplos:"
    echo "  $0                           # Executar todos os testes"
    echo "  $0 https                     # Testar apenas HTTPS"
    echo "  $0 -d meu.dominio.com api    # Testar API em domínio específico"
}

# Processar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -p|--port)
            DICOM_PORT="$2"
            shift 2
            ;;
        -u|--user)
            ADMIN_USER="$2"
            shift 2
            ;;
        -P|--password)
            ADMIN_PASS="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [ -z "$TEST_NAME" ]; then
                TEST_NAME="$1"
            else
                error "Argumento inválido: $1"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Executar testes
if [ -n "$TEST_NAME" ]; then
    run_specific_test "$TEST_NAME"
else
    run_all_tests
fi

