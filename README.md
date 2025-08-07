# Orthanc PACS Radiweb

Sistema PACS completo baseado em Orthanc com Stone Web Viewer, configurado para deploy em produção com Docker.

## 🏥 Características

- **Orthanc PACS Server** com Stone Web Viewer integrado
- **PostgreSQL** para armazenamento de índices DICOM
- **Nginx** como reverse proxy com HTTPS
- **CORS** habilitado para integração com frontend
- **Autenticação** configurada com usuários admin e viewer
- **SSL/TLS** com certificados self-signed ou Let's Encrypt
- **Docker Compose** para deploy simplificado
- **Backup** e monitoramento configurados

## 📋 Pré-requisitos

- Docker 20.10+
- Docker Compose 2.0+
- Porta 80, 443 e 4242 disponíveis
- Mínimo 2GB RAM e 10GB storage

## 🚀 Instalação Rápida

```bash
# 1. Clone ou baixe o projeto
git clone <repository-url> orthanc-pacs-radiweb
cd orthanc-pacs-radiweb

# 2. Execute o setup automático
./setup.sh setup

# 3. Acesse o sistema
# HTTP: http://localhost
# HTTPS: https://localhost (certificado self-signed)
# Stone Viewer: http://localhost/stone-webviewer/
```

## 📁 Estrutura do Projeto

```
orthanc-pacs-radiweb/
├── docker-compose.yml          # Configuração principal dos serviços
├── .env.example               # Exemplo de variáveis de ambiente
├── setup.sh                   # Script de configuração automática
├── README.md                  # Esta documentação
├── config/
│   └── orthanc.json          # Configuração do Orthanc
├── nginx/
│   ├── nginx.conf            # Configuração principal do Nginx
│   └── default.conf          # Configuração do servidor virtual
├── ssl/                      # Certificados SSL
├── data/
│   ├── orthanc/             # Dados do Orthanc (DICOM)
│   └── postgres/            # Dados do PostgreSQL
└── logs/                    # Logs dos serviços
```

## ⚙️ Configuração

### Variáveis de Ambiente

Copie `.env.example` para `.env` e ajuste as configurações:

```bash
cp .env.example .env
```

Principais variáveis:

```env
# Senhas (geradas automaticamente pelo setup.sh)
POSTGRES_PASSWORD=senha_segura_postgres
ADMIN_PASSWORD=senha_admin
VIEWER_PASSWORD=senha_viewer

# Domínio
DOMAIN_NAME=pacs.radiweb.com.br
ENABLE_HTTPS=true

# Email para Let's Encrypt
LETSENCRYPT_EMAIL=admin@radiweb.com.br

# Webhook para notificações
WEBHOOK_URL=https://api.radiweb.com.br/webhook/dicom
```

### Configuração do Orthanc

O arquivo `config/orthanc.json` contém todas as configurações do Orthanc:

- **Stone Web Viewer** habilitado
- **DICOMweb** configurado
- **CORS** habilitado para integração
- **Autenticação** com usuários admin/viewer
- **Segurança** otimizada para produção

### Configuração do Nginx

- **Reverse proxy** para Orthanc
- **CORS** configurado
- **Rate limiting** implementado
- **SSL/TLS** com certificados
- **Compressão gzip** habilitada

## 🔐 Segurança

### Autenticação

- **Admin**: Acesso completo ao sistema
- **Viewer**: Acesso somente leitura

### Configurações de Segurança

- WebDAV desabilitado
- Execução de Lua desabilitada
- Escrita no filesystem desabilitada
- Rate limiting configurado
- Headers de segurança implementados

### Certificados SSL

Para desenvolvimento:
```bash
# Certificados self-signed (criados automaticamente)
./setup.sh
```

Para produção com Let's Encrypt:
```bash
# Configure DOMAIN_NAME e LETSENCRYPT_EMAIL no .env
# Use certbot ou similar para obter certificados válidos
```

## 🌐 Deploy em Produção

### Railway

1. Conecte seu repositório ao Railway
2. Configure as variáveis de ambiente
3. Deploy automático via Git

### VPS/Cloud

```bash
# 1. Configurar servidor
sudo apt update && sudo apt install docker.io docker-compose

# 2. Clonar projeto
git clone <repository-url> orthanc-pacs-radiweb
cd orthanc-pacs-radiweb

# 3. Configurar domínio no .env
echo "DOMAIN_NAME=pacs.seudominio.com.br" >> .env
echo "ENABLE_HTTPS=true" >> .env

# 4. Setup e deploy
./setup.sh setup
```

### AWS ECS (usando CDK)

Para deploy em AWS, use o projeto oficial:
```bash
git clone https://github.com/aws-samples/orthanc-cdk-deployment
```

## 📊 Monitoramento

### Status dos Serviços

```bash
# Status geral
./setup.sh status

# Logs em tempo real
docker-compose logs -f

# Health checks
curl http://localhost/health
curl http://localhost/system
```

### Endpoints Importantes

- **Sistema**: `/system` - Informações do sistema
- **Estudos**: `/studies` - Lista de estudos DICOM
- **Stone Viewer**: `/stone-webviewer/` - Interface do visualizador
- **DICOMweb**: `/dicom-web/` - API DICOMweb
- **Health**: `/health` - Status de saúde

## 🔧 Comandos Úteis

```bash
# Iniciar serviços
docker-compose up -d

# Parar serviços
docker-compose down

# Reiniciar serviços
docker-compose restart

# Ver logs
docker-compose logs -f orthanc
docker-compose logs -f nginx
docker-compose logs -f postgres

# Backup dos dados
docker-compose exec postgres pg_dump -U orthanc orthanc > backup.sql

# Restaurar backup
docker-compose exec -T postgres psql -U orthanc orthanc < backup.sql

# Atualizar imagens
docker-compose pull
docker-compose up -d
```

## 🩺 Uso do Sistema

### Envio de Imagens DICOM

Configure seu equipamento DICOM com:
- **AE Title**: RADIWEB_PACS
- **Host**: IP do servidor
- **Porta**: 4242

### Visualização

1. Acesse `http://seu-dominio`
2. Faça login com admin/senha
3. Navegue pelos estudos
4. Clique em "Stone Web Viewer" para visualizar

### API REST

```bash
# Listar estudos
curl -u admin:senha http://localhost/studies

# Informações do sistema
curl -u admin:senha http://localhost/system

# Upload DICOM via API
curl -X POST -u admin:senha \
  -H "Content-Type: application/dicom" \
  --data-binary @arquivo.dcm \
  http://localhost/instances
```

## 🔗 Integração com Frontend

### CORS Configurado

O sistema está configurado para aceitar requisições de qualquer origem:

```javascript
// Exemplo de integração JavaScript
const response = await fetch('http://pacs.radiweb.com.br/studies', {
  headers: {
    'Authorization': 'Basic ' + btoa('admin:senha'),
    'Content-Type': 'application/json'
  }
});
const studies = await response.json();
```

### Webhook para Notificações

Configure `WEBHOOK_URL` no `.env` para receber notificações de novos estudos:

```json
{
  "event": "study_received",
  "study_id": "1.2.3.4.5",
  "patient_id": "12345",
  "timestamp": "2024-01-01T10:00:00Z"
}
```

## 🛠️ Troubleshooting

### Problemas Comuns

1. **Porta 80/443 em uso**
   ```bash
   sudo netstat -tlnp | grep :80
   sudo systemctl stop apache2  # ou nginx
   ```

2. **Permissões de arquivo**
   ```bash
   sudo chown -R $USER:$USER data/
   chmod 755 data/orthanc data/postgres
   ```

3. **Certificados SSL**
   ```bash
   # Recriar certificados
   rm -rf ssl/
   ./setup.sh
   ```

4. **PostgreSQL não inicia**
   ```bash
   # Verificar logs
   docker-compose logs postgres
   
   # Limpar dados (CUIDADO!)
   docker-compose down -v
   ```

### Logs Importantes

```bash
# Orthanc
docker-compose logs orthanc | grep ERROR

# Nginx
docker-compose logs nginx | grep error

# PostgreSQL
docker-compose logs postgres | grep ERROR
```

## 📈 Performance

### Otimizações

- **PostgreSQL** como banco de dados (mais rápido que SQLite)
- **Nginx** com compressão gzip
- **Rate limiting** para proteger contra sobrecarga
- **Keep-alive** habilitado
- **Buffering** otimizado

### Escalabilidade

Para alta demanda:
1. Use múltiplas instâncias Orthanc
2. Configure load balancer
3. Use PostgreSQL em cluster
4. Implemente cache Redis

## 🔄 Backup e Recuperação

### Backup Automático

```bash
# Script de backup (adicionar ao cron)
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
docker-compose exec -T postgres pg_dump -U orthanc orthanc > backup_$DATE.sql
tar -czf backup_$DATE.tar.gz data/ backup_$DATE.sql
```

### Recuperação

```bash
# Restaurar PostgreSQL
docker-compose exec -T postgres psql -U orthanc orthanc < backup.sql

# Restaurar dados DICOM
tar -xzf backup.tar.gz
docker-compose down
cp -r data/ ./
docker-compose up -d
```

## 📞 Suporte

Para suporte técnico:
- Verifique os logs: `docker-compose logs`
- Consulte a documentação oficial do Orthanc
- Abra uma issue no repositório

## 📄 Licença

Este projeto é baseado no Orthanc (GPL v3+) e componentes open source.

## 🤝 Contribuição

1. Fork o projeto
2. Crie uma branch para sua feature
3. Commit suas mudanças
4. Push para a branch
5. Abra um Pull Request

---

**Desenvolvido para Radiweb** - Sistema PACS profissional com Stone Web Viewer

