# Deploy no Railway - Orthanc PACS Radiweb

Guia completo para fazer deploy do Orthanc PACS no Railway.

## 🚂 Pré-requisitos

1. Conta no [Railway](https://railway.app)
2. Repositório Git com o código
3. Domínio personalizado (opcional)

## 📋 Configuração Inicial

### 1. Preparar o Repositório

```bash
# Clone o projeto
git clone <repository-url> orthanc-pacs-radiweb
cd orthanc-pacs-radiweb

# Adicione ao seu repositório Git
git remote add origin <seu-repositorio>
git push -u origin main
```

### 2. Configurar Railway

1. Acesse [Railway](https://railway.app)
2. Clique em "New Project"
3. Selecione "Deploy from GitHub repo"
4. Escolha seu repositório

## ⚙️ Configuração de Variáveis

No painel do Railway, configure as seguintes variáveis de ambiente:

### Variáveis Obrigatórias

```env
# Database (Railway PostgreSQL)
POSTGRES_PASSWORD=sua_senha_segura_postgres
DATABASE_URL=postgresql://user:pass@host:port/db

# Autenticação
ADMIN_PASSWORD=sua_senha_admin_segura
VIEWER_PASSWORD=sua_senha_viewer_segura
API_PASSWORD=sua_senha_api_segura

# Configuração do Orthanc
ORTHANC_NAME=RADIWEB_PACS
DICOM_AET=RADIWEB_PACS

# Domínio (se usando domínio personalizado)
DOMAIN_NAME=pacs.seudominio.com.br
ENABLE_HTTPS=true

# Email para certificados
LETSENCRYPT_EMAIL=admin@seudominio.com.br
```

### Variáveis Opcionais

```env
# Performance
CONCURRENT_JOBS=4
MAX_STORAGE_SIZE=50GB
STORAGE_COMPRESSION=false

# Logging
LOG_LEVEL=default
DEBUG_MODE=false

# Webhook
WEBHOOK_URL=https://api.seudominio.com.br/webhook/dicom
WEBHOOK_SECRET=seu_webhook_secret

# Backup
BACKUP_ENABLED=true
BACKUP_SCHEDULE=0 2 * * *
```

## 🗄️ Configurar PostgreSQL

### Opção 1: PostgreSQL do Railway (Recomendado)

1. No projeto Railway, clique em "Add Service"
2. Selecione "PostgreSQL"
3. Aguarde a criação do banco
4. Copie a `DATABASE_URL` para as variáveis de ambiente

### Opção 2: PostgreSQL Externo

Configure a `DATABASE_URL` com seu banco externo:
```env
DATABASE_URL=postgresql://usuario:senha@host:porta/database
```

## 🌐 Configurar Domínio

### Domínio Railway (Gratuito)

O Railway fornece um domínio automático:
```
https://seu-projeto.up.railway.app
```

### Domínio Personalizado

1. No painel Railway, vá em "Settings"
2. Clique em "Domains"
3. Adicione seu domínio: `pacs.seudominio.com.br`
4. Configure o DNS:
   ```
   CNAME pacs seu-projeto.up.railway.app
   ```

## 🔒 Configurar HTTPS

### Certificados Automáticos

O Railway fornece certificados SSL automáticos para domínios personalizados.

### Let's Encrypt (Manual)

Para configuração manual:

```bash
# No seu servidor/local
certbot certonly --manual --preferred-challenges dns \
  -d pacs.seudominio.com.br

# Upload dos certificados para Railway via variáveis
SSL_CERTIFICATE="-----BEGIN CERTIFICATE-----..."
SSL_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----..."
```

## 🚀 Deploy

### Deploy Automático

1. Push para o repositório:
   ```bash
   git add .
   git commit -m "Deploy Orthanc PACS"
   git push origin main
   ```

2. Railway detecta automaticamente e faz o deploy

### Deploy Manual

1. No painel Railway, clique em "Deploy"
2. Selecione a branch desejada
3. Aguarde o build e deploy

## 📊 Monitoramento

### Logs

No painel Railway:
1. Clique no seu serviço
2. Vá na aba "Logs"
3. Monitore os logs em tempo real

### Health Check

Configure health check no Railway:
```json
{
  "healthcheck": {
    "path": "/health",
    "interval": 30,
    "timeout": 10,
    "retries": 3
  }
}
```

### Métricas

Railway fornece métricas automáticas:
- CPU usage
- Memory usage
- Network traffic
- Response times

## 🔧 Configurações Avançadas

### Scaling

Configure auto-scaling no Railway:
```json
{
  "scaling": {
    "minReplicas": 1,
    "maxReplicas": 3,
    "targetCPU": 70
  }
}
```

### Volumes Persistentes

Para dados persistentes:
```json
{
  "volumes": [
    {
      "mountPath": "/var/lib/orthanc/db",
      "size": "10GB"
    }
  ]
}
```

## 🔐 Segurança

### Firewall

Configure regras de firewall:
- Porta 80/443: Aberta (HTTP/HTTPS)
- Porta 4242: Restrita (apenas IPs confiáveis)
- Porta 8042: Fechada (apenas interno)

### Autenticação

Configure autenticação forte:
```env
ADMIN_PASSWORD=$(openssl rand -base64 32)
VIEWER_PASSWORD=$(openssl rand -base64 24)
API_PASSWORD=$(openssl rand -base64 24)
```

### Rate Limiting

Configure no Nginx (já incluído):
- API: 10 req/s
- Login: 1 req/s
- Geral: 20 req/s burst

## 📱 Acesso

### URLs de Acesso

```
# Interface principal
https://pacs.seudominio.com.br

# Stone Web Viewer
https://pacs.seudominio.com.br/stone-webviewer/

# API REST
https://pacs.seudominio.com.br/studies

# Health Check
https://pacs.seudominio.com.br/health
```

### Credenciais

```
Admin: admin / [ADMIN_PASSWORD]
Viewer: viewer / [VIEWER_PASSWORD]
API: api / [API_PASSWORD]
```

## 🔄 Backup

### Backup Automático

Configure backup automático via webhook:

```javascript
// Função serverless para backup
export default async function handler(req, res) {
  if (req.method === 'POST') {
    // Trigger backup
    const backup = await createBackup();
    res.json({ success: true, backup });
  }
}
```

### Backup Manual

```bash
# Via Railway CLI
railway run pg_dump $DATABASE_URL > backup.sql

# Via API
curl -X POST -u admin:senha \
  https://pacs.seudominio.com.br/tools/create-archive \
  -d '{"Synchronous": true}'
```

## 🐛 Troubleshooting

### Problemas Comuns

1. **Build falha**
   ```bash
   # Verificar logs de build
   railway logs --service orthanc
   ```

2. **Banco não conecta**
   ```bash
   # Verificar DATABASE_URL
   railway variables
   ```

3. **Domínio não resolve**
   ```bash
   # Verificar DNS
   nslookup pacs.seudominio.com.br
   ```

4. **SSL não funciona**
   ```bash
   # Verificar certificados
   openssl s_client -connect pacs.seudominio.com.br:443
   ```

### Logs Importantes

```bash
# Logs do Orthanc
railway logs --filter "orthanc"

# Logs do Nginx
railway logs --filter "nginx"

# Logs de erro
railway logs --filter "ERROR"
```

## 💰 Custos

### Railway Pricing

- **Hobby Plan**: $5/mês
  - 512MB RAM
  - 1GB storage
  - Adequado para desenvolvimento

- **Pro Plan**: $20/mês
  - 8GB RAM
  - 100GB storage
  - Adequado para produção pequena

- **Team Plan**: $20/usuário/mês
  - Recursos ilimitados
  - Adequado para produção

### Estimativa de Custos

```
Desenvolvimento: $5-10/mês
Produção Pequena: $20-50/mês
Produção Média: $50-100/mês
Enterprise: $100+/mês
```

## 📞 Suporte

### Railway Support

- [Documentação](https://docs.railway.app)
- [Discord](https://discord.gg/railway)
- [GitHub](https://github.com/railwayapp)

### Orthanc Support

- [Documentação](https://book.orthanc-server.com)
- [Forum](https://discourse.orthanc-server.org)
- [GitHub](https://github.com/jodogne/Orthanc)

---

**Deploy realizado com sucesso!** 🎉

Seu Orthanc PACS está agora rodando no Railway com:
- ✅ Stone Web Viewer ativado
- ✅ HTTPS configurado
- ✅ PostgreSQL conectado
- ✅ CORS habilitado
- ✅ Backup configurado
- ✅ Monitoramento ativo

