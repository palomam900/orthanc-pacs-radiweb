# Guia de Testes Funcionais - Orthanc PACS Radiweb

Guia completo para testar todas as funcionalidades do Orthanc PACS com Stone Web Viewer.

## 🧪 Preparação para Testes

### 1. Deploy do Sistema

Primeiro, faça o deploy usando uma das opções:

```bash
# Opção 1: Railway (Recomendado)
./deploy-railway.sh deploy

# Opção 2: VPS
./deploy-vps.sh deploy

# Opção 3: Local (Desenvolvimento)
./setup.sh setup
```

### 2. Verificar Conectividade

```bash
# Testar conectividade básica
./test-connectivity.sh

# Testar domínio específico
./test-connectivity.sh -d pacs.radiweb.com.br
```

### 3. Obter Credenciais

```bash
# Verificar credenciais no arquivo .env
cat .env | grep PASSWORD

# Ou usar as credenciais padrão:
# Admin: admin / admin
# Viewer: viewer / viewer123
```

## 🏥 Testes DICOM

### Teste 1: Verificar Serviço DICOM

#### Usando dcmtk (Linux/macOS):
```bash
# Instalar dcmtk
sudo apt install dcmtk  # Ubuntu/Debian
brew install dcmtk      # macOS

# Testar echo DICOM
echoscu -aec RADIWEB_PACS pacs.radiweb.com.br 4242

# Resultado esperado:
# I: Association Request Acknowledged (Max Send PDV: 16372)
# I: Association Acknowledged (Max Send PDV: 16372)
# I: Sending Echo Request (MsgID 1)
# I: Received Echo Response (Success)
```

#### Usando Python (pydicom):
```python
# test_dicom_echo.py
from pynetdicom import AE
from pynetdicom.sop_class import VerificationSOPClass

# Configurar Application Entity
ae = AE()
ae.add_requested_context(VerificationSOPClass)

# Conectar ao Orthanc
assoc = ae.associate('pacs.radiweb.com.br', 4242, ae_title='RADIWEB_PACS')

if assoc.is_established:
    # Enviar C-ECHO
    status = assoc.send_c_echo()
    
    if status:
        print("✅ DICOM Echo bem-sucedido!")
        print(f"Status: {status}")
    else:
        print("❌ DICOM Echo falhou")
    
    # Liberar associação
    assoc.release()
else:
    print("❌ Não foi possível estabelecer associação DICOM")
```

### Teste 2: Enviar Imagem DICOM de Teste

#### Criar Imagem DICOM de Teste:
```python
# create_test_dicom.py
from pydicom.dataset import Dataset, FileDataset
from pydicom.uid import ExplicitVRLittleEndian, generate_uid
import numpy as np
from datetime import datetime
import os

def create_test_dicom():
    # Criar dataset básico
    ds = Dataset()
    
    # Metadados do paciente
    ds.PatientName = "TESTE^RADIWEB"
    ds.PatientID = "TEST001"
    ds.PatientBirthDate = "19900101"
    ds.PatientSex = "M"
    
    # Metadados do estudo
    ds.StudyInstanceUID = generate_uid()
    ds.StudyDate = datetime.now().strftime("%Y%m%d")
    ds.StudyTime = datetime.now().strftime("%H%M%S")
    ds.StudyDescription = "Teste Radiweb PACS"
    ds.AccessionNumber = "ACC001"
    
    # Metadados da série
    ds.SeriesInstanceUID = generate_uid()
    ds.SeriesNumber = "1"
    ds.SeriesDescription = "Teste Stone Viewer"
    ds.Modality = "CT"
    
    # Metadados da instância
    ds.SOPInstanceUID = generate_uid()
    ds.SOPClassUID = "1.2.840.10008.5.1.4.1.1.2"  # CT Image Storage
    ds.InstanceNumber = "1"
    
    # Dados da imagem
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"
    ds.Rows = 512
    ds.Columns = 512
    ds.BitsAllocated = 16
    ds.BitsStored = 16
    ds.HighBit = 15
    ds.PixelRepresentation = 0
    
    # Criar imagem de teste (gradiente)
    image = np.zeros((512, 512), dtype=np.uint16)
    for i in range(512):
        for j in range(512):
            image[i, j] = int((i + j) * 65535 / 1024)
    
    ds.PixelData = image.tobytes()
    
    # Criar FileDataset
    file_meta = Dataset()
    file_meta.MediaStorageSOPClassUID = ds.SOPClassUID
    file_meta.MediaStorageSOPInstanceUID = ds.SOPInstanceUID
    file_meta.ImplementationClassUID = generate_uid()
    file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
    
    filename = "test_image.dcm"
    file_ds = FileDataset(filename, ds, file_meta=file_meta, preamble=b"\0" * 128)
    
    # Salvar arquivo
    file_ds.save_as(filename)
    print(f"✅ Imagem DICOM de teste criada: {filename}")
    
    return filename

if __name__ == "__main__":
    create_test_dicom()
```

#### Enviar via C-STORE:
```python
# send_dicom.py
from pynetdicom import AE
from pynetdicom.sop_class import CTImageStorage
from pydicom import dcmread

def send_dicom_file(filename):
    # Ler arquivo DICOM
    ds = dcmread(filename)
    
    # Configurar AE
    ae = AE()
    ae.add_requested_context(CTImageStorage)
    
    # Conectar ao Orthanc
    assoc = ae.associate('pacs.radiweb.com.br', 4242, ae_title='RADIWEB_PACS')
    
    if assoc.is_established:
        # Enviar C-STORE
        status = assoc.send_c_store(ds)
        
        if status:
            print("✅ Imagem DICOM enviada com sucesso!")
            print(f"Status: {status}")
        else:
            print("❌ Falha ao enviar imagem DICOM")
        
        assoc.release()
    else:
        print("❌ Não foi possível estabelecer associação DICOM")

if __name__ == "__main__":
    send_dicom_file("test_image.dcm")
```

#### Enviar via REST API:
```bash
# Usando curl
curl -X POST \
  -u admin:admin \
  -H "Content-Type: application/dicom" \
  --data-binary @test_image.dcm \
  https://pacs.radiweb.com.br/instances

# Resultado esperado:
# {
#   "ID": "12345678-1234-1234-1234-123456789012",
#   "Path": "/instances/12345678-1234-1234-1234-123456789012",
#   "Status": "Success"
# }
```

### Teste 3: Verificar Recepção

```bash
# Listar estudos
curl -u admin:admin https://pacs.radiweb.com.br/studies

# Listar pacientes
curl -u admin:admin https://pacs.radiweb.com.br/patients

# Verificar estatísticas
curl -u admin:admin https://pacs.radiweb.com.br/statistics
```

## 👁️ Testes Stone Web Viewer

### Teste 1: Acessar Interface

1. Abra o navegador
2. Acesse: `https://pacs.radiweb.com.br`
3. Faça login com: `admin` / `senha_admin`
4. Clique em "Stone Web Viewer"

### Teste 2: Visualizar Estudo

1. Na interface do Stone Viewer
2. Selecione o estudo de teste enviado
3. Verifique se a imagem carrega corretamente
4. Teste as ferramentas:
   - Zoom (scroll do mouse)
   - Pan (arrastar)
   - Window/Level (Ctrl + arrastar)
   - Medições
   - Anotações

### Teste 3: Funcionalidades Avançadas

```javascript
// Testar via console do navegador
// Abrir DevTools (F12) e executar:

// Verificar se Stone está carregado
console.log(window.stone);

// Obter viewport ativo
const viewport = stone.getActiveViewport();
console.log(viewport);

// Obter informações do estudo
const study = stone.getCurrentStudy();
console.log(study);

// Testar ferramentas
stone.setActiveTool('zoom');
stone.setActiveTool('pan');
stone.setActiveTool('wwwc'); // Window/Level
```

## 🔌 Testes API REST

### Teste 1: Autenticação

```bash
# Teste sem autenticação (deve falhar)
curl https://pacs.radiweb.com.br/system

# Teste com autenticação
curl -u admin:admin https://pacs.radiweb.com.br/system
```

### Teste 2: Endpoints Principais

```bash
# Sistema
curl -u admin:admin https://pacs.radiweb.com.br/system

# Estatísticas
curl -u admin:admin https://pacs.radiweb.com.br/statistics

# Pacientes
curl -u admin:admin https://pacs.radiweb.com.br/patients

# Estudos
curl -u admin:admin https://pacs.radiweb.com.br/studies

# Mudanças
curl -u admin:admin https://pacs.radiweb.com.br/changes
```

### Teste 3: DICOMweb

```bash
# QIDO-RS (Query)
curl -u admin:admin https://pacs.radiweb.com.br/dicom-web/studies

# WADO-RS (Retrieve)
curl -u admin:admin https://pacs.radiweb.com.br/dicom-web/studies/{study-uid}

# STOW-RS (Store) - enviar DICOM
curl -X POST \
  -u admin:admin \
  -H "Content-Type: multipart/related; type=application/dicom" \
  --data-binary @test_image.dcm \
  https://pacs.radiweb.com.br/dicom-web/studies
```

## 🔗 Testes de Integração

### Teste 1: Webhook

```python
# test_webhook.py
import requests
import json

def test_webhook():
    webhook_url = "https://api.radiweb.com.br/webhook/dicom"
    
    # Simular notificação de novo estudo
    payload = {
        "event": "study_received",
        "study_id": "1.2.3.4.5.6.7.8.9",
        "patient_id": "TEST001",
        "patient_name": "TESTE^RADIWEB",
        "study_date": "20240101",
        "modality": "CT",
        "timestamp": "2024-01-01T10:00:00Z"
    }
    
    headers = {
        "Content-Type": "application/json",
        "X-Webhook-Secret": "webhook_secret_key"
    }
    
    response = requests.post(webhook_url, json=payload, headers=headers)
    
    if response.status_code == 200:
        print("✅ Webhook funcionando")
    else:
        print(f"❌ Webhook falhou: {response.status_code}")

if __name__ == "__main__":
    test_webhook()
```

### Teste 2: CORS

```javascript
// Testar CORS no navegador
fetch('https://pacs.radiweb.com.br/system', {
    method: 'GET',
    headers: {
        'Authorization': 'Basic ' + btoa('admin:admin')
    }
})
.then(response => response.json())
.then(data => console.log('✅ CORS funcionando:', data))
.catch(error => console.error('❌ CORS falhou:', error));
```

## 📊 Testes de Performance

### Teste 1: Tempo de Resposta

```bash
# Criar arquivo de formato para curl
cat > curl-format.txt << 'EOF'
     time_namelookup:  %{time_namelookup}\n
        time_connect:  %{time_connect}\n
     time_appconnect:  %{time_appconnect}\n
    time_pretransfer:  %{time_pretransfer}\n
       time_redirect:  %{time_redirect}\n
  time_starttransfer:  %{time_starttransfer}\n
                     ----------\n
          time_total:  %{time_total}\n
EOF

# Testar performance
curl -w "@curl-format.txt" -o /dev/null -s https://pacs.radiweb.com.br/health
```

### Teste 2: Carga de Trabalho

```python
# load_test.py
import concurrent.futures
import requests
import time

def test_endpoint(url, auth):
    start_time = time.time()
    response = requests.get(url, auth=auth)
    end_time = time.time()
    
    return {
        'status_code': response.status_code,
        'response_time': end_time - start_time
    }

def load_test():
    url = "https://pacs.radiweb.com.br/system"
    auth = ('admin', 'admin')
    num_requests = 50
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        futures = [executor.submit(test_endpoint, url, auth) for _ in range(num_requests)]
        results = [future.result() for future in concurrent.futures.as_completed(futures)]
    
    # Analisar resultados
    success_count = sum(1 for r in results if r['status_code'] == 200)
    avg_response_time = sum(r['response_time'] for r in results) / len(results)
    
    print(f"✅ Sucesso: {success_count}/{num_requests}")
    print(f"⏱️ Tempo médio: {avg_response_time:.2f}s")

if __name__ == "__main__":
    load_test()
```

## 🔍 Testes de Segurança

### Teste 1: Headers de Segurança

```bash
# Verificar headers HTTPS
curl -I https://pacs.radiweb.com.br/

# Verificar se contém:
# Strict-Transport-Security
# X-Frame-Options
# X-Content-Type-Options
# X-XSS-Protection
```

### Teste 2: Autenticação

```bash
# Testar acesso sem credenciais
curl https://pacs.radiweb.com.br/studies
# Deve retornar 401 Unauthorized

# Testar credenciais inválidas
curl -u admin:senha_errada https://pacs.radiweb.com.br/studies
# Deve retornar 401 Unauthorized

# Testar credenciais válidas
curl -u admin:admin https://pacs.radiweb.com.br/studies
# Deve retornar 200 OK
```

## 📋 Checklist de Testes

### Testes Básicos:
- [ ] Conectividade DICOM (porta 4242)
- [ ] Interface web acessível (HTTPS)
- [ ] Stone Web Viewer carrega
- [ ] Autenticação funcionando
- [ ] API REST responde

### Testes DICOM:
- [ ] C-ECHO bem-sucedido
- [ ] C-STORE funciona (envio de imagem)
- [ ] C-FIND funciona (busca)
- [ ] C-MOVE funciona (recuperação)
- [ ] DICOMweb endpoints ativos

### Testes Stone Viewer:
- [ ] Interface carrega corretamente
- [ ] Visualização de imagens
- [ ] Ferramentas funcionam (zoom, pan, etc.)
- [ ] Medições e anotações
- [ ] Performance adequada

### Testes de Integração:
- [ ] Webhook recebe notificações
- [ ] CORS configurado corretamente
- [ ] API acessível externamente
- [ ] Backup funcionando

### Testes de Performance:
- [ ] Tempo de resposta < 2s
- [ ] Suporta múltiplas conexões
- [ ] Stone Viewer responsivo
- [ ] Upload DICOM rápido

### Testes de Segurança:
- [ ] HTTPS obrigatório
- [ ] Headers de segurança
- [ ] Autenticação obrigatória
- [ ] Rate limiting ativo

## 🚨 Troubleshooting

### Problemas Comuns:

#### 1. DICOM não conecta:
```bash
# Verificar porta
telnet pacs.radiweb.com.br 4242

# Verificar firewall
sudo ufw status

# Verificar logs
docker-compose logs orthanc
```

#### 2. Stone Viewer não carrega:
```bash
# Verificar se plugin está ativo
curl -u admin:admin https://pacs.radiweb.com.br/plugins

# Verificar logs do navegador (F12)
# Verificar configuração CORS
```

#### 3. API não responde:
```bash
# Verificar autenticação
curl -u admin:admin https://pacs.radiweb.com.br/system

# Verificar logs
docker-compose logs nginx
docker-compose logs orthanc
```

---

**Testes concluídos!** 🎉

Seu Orthanc PACS está funcionando corretamente se todos os testes passaram.

**Próximos passos:**
1. Configurar equipamentos DICOM
2. Treinar usuários no Stone Viewer
3. Integrar com sistema Radiweb
4. Configurar monitoramento contínuo

