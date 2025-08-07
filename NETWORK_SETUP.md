# Configuração de Rede e Domínio - Orthanc PACS Radiweb

Guia completo para configurar rede, domínio personalizado e certificados SSL para o Orthanc PACS.

## 🌐 Configuração de Domínio

### 1. Registrar Domínio

Recomendações para o domínio:
- **Sugestão**: `pacs.radiweb.com.br`
- **Alternativas**: `dicom.radiweb.com.br`, `orthanc.radiweb.com.br`

### 2. Configurar DNS

#### Para Railway:
```dns
# Tipo: CNAME
# Nome: pacs
# Valor: seu-projeto.up.railway.app
# TTL: 300 (5 minutos)

CNAME pacs seu-projeto.up.railway.app
```

#### Para VPS/Servidor Dedicado:
```dns
# Tipo: A
# Nome: pacs
# Valor: IP_DO_SERVIDOR
# TTL: 300 (5 minutos)

A pacs 203.0.113.10
```

#### Para Google Cloud:
```dns
# Tipo: CNAME
# Nome: pacs
# Valor: ghs.googlehosted.com
# TTL: 300 (5 minutos)

CNAME pacs ghs.googlehosted.com
```

### 3. Verificar Propagação DNS

```bash
# Verificar se DNS está propagado
nslookup pacs.radiweb.com.br

# Verificar de diferentes locais
dig @8.8.8.8 pacs.radiweb.com.br
dig @1.1.1.1 pacs.radiweb.com.br

# Ferramenta online
# https://dnschecker.org
```

## 🔒 Configuração SSL/TLS

### Opção 1: Let's Encrypt (Recomendado para VPS)

#### Configuração Automática:
```bash
# Usando o script de deploy VPS
./deploy-vps.sh

# Ou manualmente com certbot
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d pacs.radiweb.com.br
```

#### Renovação Automática:
```bash
# Adicionar ao crontab
0 12 * * * /usr/bin/certbot renew --quiet
```

### Opção 2: Certificados Comerciais

#### Instalar Certificado:
```bash
# Copiar certificados para o diretório SSL
cp certificado.crt ssl/certificate.crt
cp chave-privada.key ssl/private.key
cp cadeia.crt ssl/ca-bundle.crt

# Combinar certificados
cat ssl/certificate.crt ssl/ca-bundle.crt > ssl/certificate.pem
```

### Opção 3: Cloudflare (Gratuito)

1. Adicionar domínio ao Cloudflare
2. Configurar DNS no Cloudflare
3. Ativar SSL/TLS "Full (strict)"
4. Configurar Origin Certificates

## 🔌 Configuração de Portas

### Portas Necessárias:

| Porta | Protocolo | Serviço | Acesso |
|-------|-----------|---------|--------|
| 80 | HTTP | Nginx (redirect) | Público |
| 443 | HTTPS | Nginx (SSL) | Público |
| 4242 | DICOM | Orthanc DICOM | Restrito |
| 8042 | HTTP | Orthanc Web | Interno |
| 5432 | PostgreSQL | Database | Interno |

### Configuração Firewall (VPS):

```bash
# UFW (Ubuntu/Debian)
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 4242/tcp  # DICOM
sudo ufw enable

# iptables (manual)
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 4242 -j ACCEPT
```

### Configuração Cloud (Railway/GCP):

```yaml
# Railway - automático
# Portas 80/443 são expostas automaticamente
# Porta 4242 precisa ser configurada manualmente

# Google Cloud Run
ports:
  - containerPort: 8042
    protocol: TCP
```

## 🏥 Configuração DICOM

### Configuração de Equipamentos:

```
# Configurações para equipamentos DICOM
AE Title: RADIWEB_PACS
Host: pacs.radiweb.com.br
Porta: 4242
Timeout: 30 segundos
```

### Teste de Conectividade DICOM:

```bash
# Usando dcmtk (instalar: apt install dcmtk)
echoscu -aec RADIWEB_PACS pacs.radiweb.com.br 4242

# Usando Python (pydicom)
from pynetdicom import AE
ae = AE()
assoc = ae.associate('pacs.radiweb.com.br', 4242, ae_title='RADIWEB_PACS')
if assoc.is_established:
    print("Conexão DICOM estabelecida!")
    assoc.release()
```

## 🔧 Configuração de Rede Avançada

### Load Balancer (Para Alta Disponibilidade):

```nginx
# nginx.conf
upstream orthanc_cluster {
    server orthanc1:8042 weight=3;
    server orthanc2:8042 weight=2;
    server orthanc3:8042 weight=1;
    
    # Health check
    keepalive 32;
}

server {
    location / {
        proxy_pass http://orthanc_cluster;
        proxy_next_upstream error timeout invalid_header http_500;
    }
}
```

### CDN Configuration (Cloudflare):

```javascript
// Cloudflare Workers para cache inteligente
addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  const url = new URL(request.url)
  
  // Cache static assets
  if (url.pathname.match(/\.(js|css|png|jpg|jpeg|gif|ico|svg)$/)) {
    return fetch(request, {
      cf: {
        cacheTtl: 86400, // 24 hours
        cacheEverything: true
      }
    })
  }
  
  // Don't cache DICOM data
  if (url.pathname.startsWith('/dicom-web/') || 
      url.pathname.startsWith('/studies/')) {
    return fetch(request, {
      cf: { cacheTtl: 0 }
    })
  }
  
  return fetch(request)
}
```

### VPN para Acesso Seguro:

```bash
# OpenVPN Server (opcional para acesso administrativo)
sudo apt install openvpn easy-rsa

# WireGuard (alternativa moderna)
sudo apt install wireguard

# Configuração básica WireGuard
wg genkey | tee privatekey | wg pubkey > publickey
```

## 📊 Monitoramento de Rede

### Configuração Prometheus:

```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'orthanc'
    static_configs:
      - targets: ['pacs.radiweb.com.br:8042']
    metrics_path: '/statistics'
    
  - job_name: 'nginx'
    static_configs:
      - targets: ['pacs.radiweb.com.br:80']
    metrics_path: '/nginx_status'
```

### Alertas de Conectividade:

```yaml
# alertmanager.yml
groups:
  - name: orthanc
    rules:
      - alert: OrthancDown
        expr: up{job="orthanc"} == 0
        for: 5m
        annotations:
          summary: "Orthanc PACS está offline"
          
      - alert: DicomPortDown
        expr: probe_success{instance="pacs.radiweb.com.br:4242"} == 0
        for: 2m
        annotations:
          summary: "Porta DICOM não está respondendo"
```

## 🔍 Testes de Conectividade

### Script de Teste Completo:

```bash
#!/bin/bash
# test-connectivity.sh

DOMAIN="pacs.radiweb.com.br"
DICOM_PORT="4242"
HTTP_PORT="80"
HTTPS_PORT="443"

echo "🔍 Testando conectividade do Orthanc PACS..."

# Teste DNS
echo "📡 Testando DNS..."
if nslookup $DOMAIN > /dev/null 2>&1; then
    echo "✅ DNS OK"
else
    echo "❌ DNS falhou"
    exit 1
fi

# Teste HTTP
echo "🌐 Testando HTTP..."
if curl -s -o /dev/null -w "%{http_code}" http://$DOMAIN/health | grep -q "200"; then
    echo "✅ HTTP OK"
else
    echo "❌ HTTP falhou"
fi

# Teste HTTPS
echo "🔒 Testando HTTPS..."
if curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN/health | grep -q "200"; then
    echo "✅ HTTPS OK"
else
    echo "❌ HTTPS falhou"
fi

# Teste DICOM
echo "🏥 Testando DICOM..."
if nc -z $DOMAIN $DICOM_PORT; then
    echo "✅ DICOM porta OK"
else
    echo "❌ DICOM porta falhou"
fi

# Teste Stone Web Viewer
echo "👁️ Testando Stone Web Viewer..."
if curl -s https://$DOMAIN/stone-webviewer/ | grep -q "Stone"; then
    echo "✅ Stone Web Viewer OK"
else
    echo "❌ Stone Web Viewer falhou"
fi

# Teste API
echo "🔌 Testando API..."
if curl -s -u admin:senha https://$DOMAIN/system | grep -q "Name"; then
    echo "✅ API OK"
else
    echo "❌ API falhou (verifique credenciais)"
fi

echo "✅ Testes concluídos!"
```

## 🚨 Troubleshooting

### Problemas Comuns:

#### 1. DNS não resolve:
```bash
# Verificar configuração DNS
dig pacs.radiweb.com.br
nslookup pacs.radiweb.com.br 8.8.8.8

# Aguardar propagação (até 48h)
# Usar ferramentas online: dnschecker.org
```

#### 2. SSL não funciona:
```bash
# Verificar certificado
openssl s_client -connect pacs.radiweb.com.br:443

# Verificar configuração Nginx
nginx -t
systemctl status nginx
```

#### 3. DICOM não conecta:
```bash
# Verificar porta
telnet pacs.radiweb.com.br 4242
nc -zv pacs.radiweb.com.br 4242

# Verificar firewall
sudo ufw status
sudo iptables -L
```

#### 4. Performance lenta:
```bash
# Teste de velocidade
curl -w "@curl-format.txt" -o /dev/null -s https://pacs.radiweb.com.br/health

# Onde curl-format.txt contém:
#     time_namelookup:  %{time_namelookup}\n
#        time_connect:  %{time_connect}\n
#     time_appconnect:  %{time_appconnect}\n
#    time_pretransfer:  %{time_pretransfer}\n
#       time_redirect:  %{time_redirect}\n
#  time_starttransfer:  %{time_starttransfer}\n
#                     ----------\n
#          time_total:  %{time_total}\n
```

## 📋 Checklist de Configuração

### Pré-Deploy:
- [ ] Domínio registrado
- [ ] DNS configurado
- [ ] Firewall configurado
- [ ] Certificados SSL prontos

### Pós-Deploy:
- [ ] DNS propagado
- [ ] HTTPS funcionando
- [ ] Porta DICOM acessível
- [ ] Stone Web Viewer carregando
- [ ] API respondendo
- [ ] Backup configurado
- [ ] Monitoramento ativo

### Testes Finais:
- [ ] Envio de imagem DICOM teste
- [ ] Visualização no Stone Viewer
- [ ] Autenticação funcionando
- [ ] Webhook recebendo notificações
- [ ] Performance adequada

---

**Configuração de rede concluída!** 🎉

Seu Orthanc PACS está agora acessível via:
- **HTTPS**: https://pacs.radiweb.com.br
- **DICOM**: pacs.radiweb.com.br:4242
- **Stone Viewer**: https://pacs.radiweb.com.br/stone-webviewer/

