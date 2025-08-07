# Multi-stage Dockerfile para Orthanc PACS Radiweb
# Baseado na imagem oficial do Orthanc Team

FROM orthancteam/orthanc:24.5.0 as orthanc-base

# Instalar dependências adicionais
USER root
RUN apt-get update && apt-get install -y \
    nginx \
    postgresql-client \
    curl \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Configurar Nginx
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

# Criar diretórios necessários
RUN mkdir -p /var/lib/orthanc/db \
    /etc/nginx/ssl \
    /var/log/nginx \
    && chown -R orthanc:orthanc /var/lib/orthanc

# Copiar configuração do Orthanc
COPY config/orthanc.json /etc/orthanc/orthanc.json

# Gerar certificados SSL self-signed
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/private.key \
    -out /etc/nginx/ssl/certificate.crt \
    -subj "/C=BR/ST=SP/L=São Paulo/O=Radiweb/OU=PACS/CN=pacs.radiweb.com.br" \
    && cat /etc/nginx/ssl/private.key /etc/nginx/ssl/certificate.crt > /etc/nginx/ssl/certificate.pem \
    && chmod 600 /etc/nginx/ssl/private.key /etc/nginx/ssl/certificate.pem \
    && chmod 644 /etc/nginx/ssl/certificate.crt

# Script de inicialização
COPY <<EOF /usr/local/bin/start-services.sh
#!/bin/bash
set -e

echo "🏥 Iniciando Orthanc PACS Radiweb..."

# Configurar variáveis de ambiente padrão se não definidas
export ORTHANC_NAME=\${ORTHANC_NAME:-"RADIWEB_PACS"}
export DICOM_AET=\${DICOM_AET:-"RADIWEB_PACS"}
export ADMIN_PASSWORD=\${ADMIN_PASSWORD:-"admin"}
export VIEWER_PASSWORD=\${VIEWER_PASSWORD:-"viewer123"}

# Atualizar configuração do Orthanc com variáveis de ambiente
sed -i "s/\"RADIWEB_PACS\"/\"\$ORTHANC_NAME\"/g" /etc/orthanc/orthanc.json
sed -i "s/\"admin\"/\"\$ADMIN_PASSWORD\"/g" /etc/orthanc/orthanc.json
sed -i "s/\"viewer123\"/\"\$VIEWER_PASSWORD\"/g" /etc/orthanc/orthanc.json

# Iniciar Nginx em background
echo "🌐 Iniciando Nginx..."
nginx -g "daemon off;" &
NGINX_PID=\$!

# Aguardar um pouco para Nginx inicializar
sleep 2

# Iniciar Orthanc
echo "🏥 Iniciando Orthanc..."
exec /usr/local/bin/Orthanc /etc/orthanc/orthanc.json --verbose

# Cleanup function
cleanup() {
    echo "🛑 Parando serviços..."
    kill \$NGINX_PID 2>/dev/null || true
    exit 0
}

# Trap signals
trap cleanup SIGTERM SIGINT

# Wait for background processes
wait
EOF

RUN chmod +x /usr/local/bin/start-services.sh

# Configurar usuário
USER orthanc

# Expor portas
EXPOSE 80 443 4242 8042

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8042/system || exit 1

# Comando de inicialização
CMD ["/usr/local/bin/start-services.sh"]

# Labels
LABEL maintainer="Radiweb <admin@radiweb.com.br>"
LABEL description="Orthanc PACS with Stone Web Viewer for Radiweb"
LABEL version="1.0.0"

