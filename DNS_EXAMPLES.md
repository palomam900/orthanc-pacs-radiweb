# Exemplos de Configuração DNS - Orthanc PACS Radiweb

Guia com exemplos de configuração DNS para diferentes provedores e cenários.

## 🌐 Provedores de DNS Populares

### 1. Cloudflare (Recomendado)

#### Configuração Básica:
```dns
# Tipo: CNAME
# Nome: pacs
# Conteúdo: seu-projeto.up.railway.app (ou IP do VPS)
# Proxy: Ativado (nuvem laranja)
# TTL: Auto

CNAME pacs seu-projeto.up.railway.app
```

#### Configuração Avançada:
```dns
# Registro principal
CNAME pacs seu-projeto.up.railway.app

# Subdomínios adicionais
CNAME dicom seu-projeto.up.railway.app
CNAME viewer seu-projeto.up.railway.app
CNAME api seu-projeto.up.railway.app

# Registro MX para email (opcional)
MX @ mail.radiweb.com.br (prioridade: 10)

# Registro TXT para verificação
TXT @ "v=spf1 include:_spf.google.com ~all"
```

#### Page Rules (Cloudflare):
```
# Cache para assets estáticos
pacs.radiweb.com.br/stone-webviewer/assets/*
- Cache Level: Cache Everything
- Edge Cache TTL: 1 month

# Bypass cache para API DICOM
pacs.radiweb.com.br/dicom-web/*
- Cache Level: Bypass

# Redirect HTTP para HTTPS
http://pacs.radiweb.com.br/*
- Always Use HTTPS: On
```

### 2. Google Cloud DNS

#### Configuração via Console:
```dns
# Zona: radiweb.com.br
# Tipo: CNAME
# Nome: pacs
# Dados: seu-projeto.up.railway.app.
# TTL: 300

gcloud dns record-sets transaction start --zone=radiweb-zone
gcloud dns record-sets transaction add seu-projeto.up.railway.app. \
    --name=pacs.radiweb.com.br. --ttl=300 --type=CNAME --zone=radiweb-zone
gcloud dns record-sets transaction execute --zone=radiweb-zone
```

#### Configuração via Terraform:
```hcl
resource "google_dns_record_set" "pacs" {
  name = "pacs.radiweb.com.br."
  type = "CNAME"
  ttl  = 300

  managed_zone = google_dns_managed_zone.radiweb.name

  rrdatas = ["seu-projeto.up.railway.app."]
}
```

### 3. AWS Route 53

#### Configuração via CLI:
```bash
# Criar registro CNAME
aws route53 change-resource-record-sets \
    --hosted-zone-id Z123456789 \
    --change-batch '{
        "Changes": [{
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "pacs.radiweb.com.br",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [{"Value": "seu-projeto.up.railway.app"}]
            }
        }]
    }'
```

#### Configuração via Terraform:
```hcl
resource "aws_route53_record" "pacs" {
  zone_id = aws_route53_zone.radiweb.zone_id
  name    = "pacs.radiweb.com.br"
  type    = "CNAME"
  ttl     = 300
  records = ["seu-projeto.up.railway.app"]
}
```

### 4. Registro.br (Domínios .br)

#### Via Painel Web:
```
1. Acesse o painel do Registro.br
2. Vá em "DNS" > "Gerenciar DNS"
3. Adicione registro:
   - Tipo: CNAME
   - Nome: pacs
   - Valor: seu-projeto.up.railway.app
   - TTL: 3600
```

#### Via API:
```bash
# Usando a API do Registro.br
curl -X POST "https://registro.br/api/dns" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "radiweb.com.br",
    "records": [{
      "type": "CNAME",
      "name": "pacs",
      "content": "seu-projeto.up.railway.app",
      "ttl": 3600
    }]
  }'
```

## 🏗️ Cenários de Deploy

### Cenário 1: Railway + Cloudflare

```dns
# Cloudflare DNS
CNAME pacs seu-projeto.up.railway.app

# Cloudflare Settings
- SSL/TLS: Full (strict)
- Always Use HTTPS: On
- HSTS: Enabled
- Minify: CSS, JS, HTML
```

### Cenário 2: VPS + Let's Encrypt

```dns
# DNS Provider (qualquer)
A pacs 203.0.113.10

# Configuração no servidor
server {
    server_name pacs.radiweb.com.br;
    # Configuração SSL automática via certbot
}
```

### Cenário 3: Google Cloud Run

```dns
# Google Cloud DNS
CNAME pacs ghs.googlehosted.com

# Cloud Run Domain Mapping
gcloud run domain-mappings create \
    --service orthanc-pacs \
    --domain pacs.radiweb.com.br \
    --region us-central1
```

### Cenário 4: AWS ECS + ALB

```dns
# Route 53
CNAME pacs orthanc-alb-123456789.us-east-1.elb.amazonaws.com

# Application Load Balancer
- Target Group: ECS Service
- Health Check: /health
- SSL Certificate: ACM
```

## 🔧 Configurações Avançadas

### Load Balancing (Multi-Region)

```dns
# Cloudflare Load Balancer
Pool 1 (Primary):
- Origin: us-east.pacs.radiweb.com.br
- Health Check: https://us-east.pacs.radiweb.com.br/health

Pool 2 (Backup):
- Origin: us-west.pacs.radiweb.com.br
- Health Check: https://us-west.pacs.radiweb.com.br/health

Load Balancer:
- Hostname: pacs.radiweb.com.br
- Fallback Pool: Pool 2
- Default Pool: Pool 1
```

### Geo-Location Routing

```dns
# AWS Route 53 Geo-Location
Record 1:
- Name: pacs.radiweb.com.br
- Type: CNAME
- Value: us-orthanc.radiweb.com.br
- Location: North America

Record 2:
- Name: pacs.radiweb.com.br
- Type: CNAME
- Value: eu-orthanc.radiweb.com.br
- Location: Europe

Record 3:
- Name: pacs.radiweb.com.br
- Type: CNAME
- Value: sa-orthanc.radiweb.com.br
- Location: South America
```

### CDN Configuration

```dns
# Cloudflare
CNAME pacs seu-projeto.up.railway.app
CNAME assets-pacs assets.radiweb.com.br

# AWS CloudFront
CNAME pacs d123456789.cloudfront.net
CNAME static-pacs d987654321.cloudfront.net
```

## 🔍 Verificação e Testes

### Comandos de Verificação:

```bash
# Verificar propagação DNS
dig pacs.radiweb.com.br
nslookup pacs.radiweb.com.br
host pacs.radiweb.com.br

# Verificar de diferentes servidores DNS
dig @8.8.8.8 pacs.radiweb.com.br
dig @1.1.1.1 pacs.radiweb.com.br
dig @208.67.222.222 pacs.radiweb.com.br

# Verificar TTL
dig +noall +answer pacs.radiweb.com.br

# Verificar CNAME chain
dig +trace pacs.radiweb.com.br
```

### Ferramentas Online:

```
# Verificação de propagação
https://dnschecker.org
https://www.whatsmydns.net
https://dns.google/query?name=pacs.radiweb.com.br

# Teste de performance
https://tools.pingdom.com
https://gtmetrix.com
https://developers.google.com/speed/pagespeed/insights
```

## 🚨 Troubleshooting DNS

### Problemas Comuns:

#### 1. DNS não propaga:
```bash
# Verificar configuração
dig pacs.radiweb.com.br

# Aguardar TTL expirar
# TTL baixo (300s) = propagação rápida
# TTL alto (86400s) = propagação lenta

# Limpar cache local
sudo systemctl flush-dns  # Linux
ipconfig /flushdns         # Windows
sudo dscacheutil -flushcache  # macOS
```

#### 2. CNAME loop:
```bash
# Verificar chain CNAME
dig +trace pacs.radiweb.com.br

# Evitar:
# pacs.radiweb.com.br -> app.radiweb.com.br -> pacs.radiweb.com.br
```

#### 3. SSL não funciona:
```bash
# Verificar se DNS aponta para proxy Cloudflare
dig pacs.radiweb.com.br

# Se usar Cloudflare, ativar proxy (nuvem laranja)
# Se usar VPS, aguardar Let's Encrypt
```

#### 4. Performance lenta:
```bash
# Verificar TTL
dig +noall +answer pacs.radiweb.com.br

# Reduzir TTL para 300s durante mudanças
# Aumentar TTL para 3600s em produção estável
```

## 📋 Checklist DNS

### Pré-Configuração:
- [ ] Domínio registrado
- [ ] Acesso ao painel DNS
- [ ] IP/hostname do servidor conhecido
- [ ] TTL definido (300s para testes, 3600s para produção)

### Configuração:
- [ ] Registro CNAME/A criado
- [ ] Subdomínios configurados (se necessário)
- [ ] Registros MX configurados (se usar email)
- [ ] Registros TXT configurados (SPF, DKIM, etc.)

### Pós-Configuração:
- [ ] DNS propagado globalmente
- [ ] HTTPS funcionando
- [ ] Redirecionamento HTTP→HTTPS ativo
- [ ] Performance testada
- [ ] Monitoramento configurado

### Produção:
- [ ] TTL aumentado para 3600s+
- [ ] Backup DNS configurado
- [ ] Alertas de downtime ativos
- [ ] Documentação atualizada

---

**Configuração DNS concluída!** 🎉

Seu domínio `pacs.radiweb.com.br` está agora configurado e apontando para o Orthanc PACS.

**Próximos passos:**
1. Aguardar propagação DNS (até 48h)
2. Testar conectividade: `./test-connectivity.sh`
3. Configurar SSL/HTTPS
4. Realizar testes funcionais

