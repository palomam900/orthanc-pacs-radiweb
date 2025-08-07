# Guia de Integração - Orthanc PACS com Sistema Radiweb

Guia específico para integrar o Orthanc PACS com o sistema de laudos radiológicos Radiweb.

---

## 🎯 Visão Geral da Integração

O Orthanc PACS foi configurado especificamente para integrar com o sistema Radiweb, oferecendo:

- **Recepção automática** de exames DICOM dos equipamentos
- **Visualização integrada** com Stone Web Viewer
- **Notificações em tempo real** via webhook
- **API REST** para integração programática
- **Interface personalizada** para radiologistas

### Fluxo de Trabalho Integrado

```
1. Equipamento → Envia DICOM → Orthanc PACS
2. Orthanc → Processa → Armazena no PostgreSQL
3. Orthanc → Webhook → Sistema Radiweb
4. Radiweb → Notifica → Radiologista
5. Radiologista → Acessa → Stone Web Viewer
6. Radiologista → Lauda → Sistema Radiweb
```

---

## 🔗 Configuração do Webhook

### 1. Endpoint do Webhook

Configure no arquivo `.env`:

```bash
WEBHOOK_URL=https://api.radiweb.com.br/webhook/dicom
WEBHOOK_SECRET=sua_chave_secreta_webhook
```

### 2. Payload do Webhook

Quando um novo estudo é recebido, o Orthanc envia:

```json
{
  "event": "study_received",
  "timestamp": "2024-01-01T10:30:00Z",
  "orthanc_url": "https://pacs.radiweb.com.br",
  "study": {
    "orthanc_id": "12345678-1234-1234-1234-123456789012",
    "study_uid": "1.2.826.0.1.3680043.8.498.12345678901234567890",
    "study_date": "20240101",
    "study_time": "103000",
    "study_description": "TC ABDOME TOTAL",
    "accession_number": "ACC20240101001",
    "referring_physician": "Dr. João Silva",
    "modality": "CT",
    "series_count": 3,
    "instance_count": 150
  },
  "patient": {
    "patient_id": "12345",
    "patient_name": "SILVA^JOAO^CARLOS",
    "patient_birth_date": "19800515",
    "patient_sex": "M",
    "patient_age": "043Y"
  },
  "urls": {
    "stone_viewer": "https://pacs.radiweb.com.br/stone-webviewer/app/index.html?study=12345678-1234-1234-1234-123456789012",
    "dicom_web": "https://pacs.radiweb.com.br/dicom-web/studies/1.2.826.0.1.3680043.8.498.12345678901234567890",
    "rest_api": "https://pacs.radiweb.com.br/studies/12345678-1234-1234-1234-123456789012"
  }
}
```

### 3. Implementação no Sistema Radiweb

```python
# webhook_handler.py
from flask import Flask, request, jsonify
import hmac
import hashlib
import json

app = Flask(__name__)
WEBHOOK_SECRET = "sua_chave_secreta_webhook"

@app.route('/webhook/dicom', methods=['POST'])
def handle_dicom_webhook():
    # Verificar assinatura
    signature = request.headers.get('X-Webhook-Signature')
    if not verify_signature(request.data, signature):
        return jsonify({'error': 'Invalid signature'}), 401
    
    # Processar payload
    data = request.json
    
    if data['event'] == 'study_received':
        # Criar novo exame no sistema Radiweb
        exam = create_exam_from_dicom(data)
        
        # Notificar radiologista
        notify_radiologist(exam)
        
        # Retornar sucesso
        return jsonify({
            'status': 'success',
            'exam_id': exam.id,
            'message': 'Exame criado com sucesso'
        })
    
    return jsonify({'status': 'ignored'})

def verify_signature(payload, signature):
    """Verificar assinatura do webhook"""
    expected = hmac.new(
        WEBHOOK_SECRET.encode(),
        payload,
        hashlib.sha256
    ).hexdigest()
    
    return hmac.compare_digest(f"sha256={expected}", signature)

def create_exam_from_dicom(data):
    """Criar exame no sistema Radiweb a partir dos dados DICOM"""
    study = data['study']
    patient = data['patient']
    
    # Criar ou atualizar paciente
    patient_obj = Patient.get_or_create(
        patient_id=patient['patient_id'],
        defaults={
            'name': patient['patient_name'],
            'birth_date': patient['patient_birth_date'],
            'sex': patient['patient_sex']
        }
    )
    
    # Criar exame
    exam = Exam.create(
        patient=patient_obj,
        study_uid=study['study_uid'],
        orthanc_id=study['orthanc_id'],
        study_date=study['study_date'],
        study_time=study['study_time'],
        description=study['study_description'],
        accession_number=study['accession_number'],
        referring_physician=study['referring_physician'],
        modality=study['modality'],
        series_count=study['series_count'],
        instance_count=study['instance_count'],
        stone_viewer_url=data['urls']['stone_viewer'],
        status='pending'
    )
    
    return exam

def notify_radiologist(exam):
    """Notificar radiologista sobre novo exame"""
    # Enviar email, SMS, push notification, etc.
    pass
```

---

## 🖥️ Interface do Sistema Radiweb

### 1. Lista de Exames

```html
<!-- exams_list.html -->
<div class="exams-container">
    <h2>Exames Pendentes</h2>
    
    <div class="exam-card" data-exam-id="{{ exam.id }}">
        <div class="exam-header">
            <h3>{{ exam.patient.name }}</h3>
            <span class="exam-date">{{ exam.study_date }}</span>
        </div>
        
        <div class="exam-details">
            <p><strong>Modalidade:</strong> {{ exam.modality }}</p>
            <p><strong>Descrição:</strong> {{ exam.description }}</p>
            <p><strong>Médico:</strong> {{ exam.referring_physician }}</p>
            <p><strong>Séries:</strong> {{ exam.series_count }}</p>
        </div>
        
        <div class="exam-actions">
            <button onclick="openViewer('{{ exam.stone_viewer_url }}')" 
                    class="btn btn-primary">
                Visualizar Imagens
            </button>
            <button onclick="startReport({{ exam.id }})" 
                    class="btn btn-success">
                Iniciar Laudo
            </button>
        </div>
    </div>
</div>

<script>
function openViewer(url) {
    // Abrir Stone Web Viewer em nova aba
    window.open(url, '_blank', 'width=1200,height=800');
}

function startReport(examId) {
    // Redirecionar para tela de laudo
    window.location.href = `/laudos/novo/${examId}`;
}
</script>
```

### 2. Tela de Laudo Integrada

```html
<!-- report_editor.html -->
<div class="report-container">
    <div class="report-header">
        <h2>Laudo Radiológico</h2>
        <div class="patient-info">
            <p><strong>Paciente:</strong> {{ exam.patient.name }}</p>
            <p><strong>Exame:</strong> {{ exam.description }}</p>
            <p><strong>Data:</strong> {{ exam.study_date }}</p>
        </div>
    </div>
    
    <div class="report-content">
        <div class="viewer-panel">
            <iframe src="{{ exam.stone_viewer_url }}" 
                    width="100%" height="600px" 
                    frameborder="0">
            </iframe>
        </div>
        
        <div class="report-panel">
            <form id="report-form">
                <div class="form-group">
                    <label>Técnica:</label>
                    <textarea name="technique" rows="3">{{ report.technique }}</textarea>
                </div>
                
                <div class="form-group">
                    <label>Achados:</label>
                    <textarea name="findings" rows="8">{{ report.findings }}</textarea>
                    
                    <!-- Sugestões de texto baseadas no banco de frases -->
                    <div class="suggestions">
                        <button type="button" onclick="insertText('findings', 'Exame dentro dos limites da normalidade.')">
                            Normal
                        </button>
                        <button type="button" onclick="insertText('findings', 'Não há evidências de alterações significativas.')">
                            Sem alterações
                        </button>
                    </div>
                </div>
                
                <div class="form-group">
                    <label>Conclusão:</label>
                    <textarea name="conclusion" rows="4">{{ report.conclusion }}</textarea>
                </div>
                
                <div class="form-actions">
                    <button type="button" onclick="saveReport()" class="btn btn-secondary">
                        Salvar Rascunho
                    </button>
                    <button type="button" onclick="finalizeReport()" class="btn btn-success">
                        Finalizar Laudo
                    </button>
                </div>
            </form>
        </div>
    </div>
</div>

<script>
function insertText(fieldName, text) {
    const field = document.querySelector(`textarea[name="${fieldName}"]`);
    const cursorPos = field.selectionStart;
    const textBefore = field.value.substring(0, cursorPos);
    const textAfter = field.value.substring(field.selectionEnd);
    
    field.value = textBefore + text + textAfter;
    field.focus();
    field.setSelectionRange(cursorPos + text.length, cursorPos + text.length);
}

function saveReport() {
    const formData = new FormData(document.getElementById('report-form'));
    
    fetch(`/api/reports/{{ exam.id }}/save`, {
        method: 'POST',
        body: formData
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            showNotification('Rascunho salvo com sucesso', 'success');
        }
    });
}

function finalizeReport() {
    if (confirm('Tem certeza que deseja finalizar este laudo?')) {
        const formData = new FormData(document.getElementById('report-form'));
        
        fetch(`/api/reports/{{ exam.id }}/finalize`, {
            method: 'POST',
            body: formData
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                showNotification('Laudo finalizado com sucesso', 'success');
                window.location.href = '/exames';
            }
        });
    }
}
</script>
```

---

## 🔌 API de Integração

### 1. Cliente Python para Orthanc

```python
# radiweb_pacs_client.py
import requests
from typing import List, Dict, Optional
import json

class RadiwebPACSClient:
    def __init__(self, base_url: str, username: str, password: str):
        self.base_url = base_url.rstrip('/')
        self.auth = (username, password)
        self.session = requests.Session()
        self.session.auth = self.auth
    
    def get_studies(self, patient_id: Optional[str] = None) -> List[Dict]:
        """Buscar estudos, opcionalmente filtrados por paciente"""
        url = f"{self.base_url}/studies"
        
        if patient_id:
            # Buscar via DICOM Find
            return self._find_studies_by_patient(patient_id)
        
        response = self.session.get(url)
        response.raise_for_status()
        
        studies = []
        for study_id in response.json():
            study_info = self.get_study_info(study_id)
            studies.append(study_info)
        
        return studies
    
    def get_study_info(self, study_id: str) -> Dict:
        """Obter informações detalhadas de um estudo"""
        url = f"{self.base_url}/studies/{study_id}"
        response = self.session.get(url)
        response.raise_for_status()
        
        study = response.json()
        
        # Obter informações do paciente
        patient_url = f"{self.base_url}/patients/{study['ParentPatient']}"
        patient_response = self.session.get(patient_url)
        patient_info = patient_response.json()
        
        return {
            'orthanc_id': study_id,
            'study_uid': study['MainDicomTags']['StudyInstanceUID'],
            'study_date': study['MainDicomTags'].get('StudyDate', ''),
            'study_time': study['MainDicomTags'].get('StudyTime', ''),
            'study_description': study['MainDicomTags'].get('StudyDescription', ''),
            'accession_number': study['MainDicomTags'].get('AccessionNumber', ''),
            'patient_id': patient_info['MainDicomTags']['PatientID'],
            'patient_name': patient_info['MainDicomTags']['PatientName'],
            'patient_birth_date': patient_info['MainDicomTags'].get('PatientBirthDate', ''),
            'patient_sex': patient_info['MainDicomTags'].get('PatientSex', ''),
            'series_count': len(study['Series']),
            'stone_viewer_url': self.get_stone_viewer_url(study_id)
        }
    
    def get_stone_viewer_url(self, study_id: str) -> str:
        """Obter URL do Stone Web Viewer para um estudo"""
        return f"{self.base_url}/stone-webviewer/app/index.html?study={study_id}"
    
    def download_study_zip(self, study_id: str) -> bytes:
        """Download de estudo completo em ZIP"""
        url = f"{self.base_url}/studies/{study_id}/archive"
        response = self.session.get(url)
        response.raise_for_status()
        return response.content
    
    def get_study_statistics(self, study_id: str) -> Dict:
        """Obter estatísticas de um estudo"""
        url = f"{self.base_url}/studies/{study_id}/statistics"
        response = self.session.get(url)
        response.raise_for_status()
        return response.json()
    
    def search_studies(self, criteria: Dict) -> List[Dict]:
        """Buscar estudos com critérios específicos"""
        # Implementar busca via DICOMweb QIDO-RS
        url = f"{self.base_url}/dicom-web/studies"
        
        params = {}
        if 'patient_id' in criteria:
            params['PatientID'] = criteria['patient_id']
        if 'study_date' in criteria:
            params['StudyDate'] = criteria['study_date']
        if 'modality' in criteria:
            params['ModalitiesInStudy'] = criteria['modality']
        
        response = self.session.get(url, params=params)
        response.raise_for_status()
        
        return response.json()

# Exemplo de uso
pacs = RadiwebPACSClient(
    "https://pacs.radiweb.com.br",
    "api",
    "senha_api"
)

# Buscar estudos de um paciente
studies = pacs.get_studies(patient_id="12345")

# Obter URL do viewer
viewer_url = pacs.get_stone_viewer_url(studies[0]['orthanc_id'])
```

### 2. Integração com Django/Flask

```python
# models.py (Django)
from django.db import models

class Patient(models.Model):
    patient_id = models.CharField(max_length=64, unique=True)
    name = models.CharField(max_length=255)
    birth_date = models.DateField(null=True, blank=True)
    sex = models.CharField(max_length=1, choices=[('M', 'Masculino'), ('F', 'Feminino')])
    created_at = models.DateTimeField(auto_now_add=True)

class Exam(models.Model):
    STATUS_CHOICES = [
        ('pending', 'Pendente'),
        ('in_progress', 'Em andamento'),
        ('completed', 'Concluído'),
        ('cancelled', 'Cancelado')
    ]
    
    patient = models.ForeignKey(Patient, on_delete=models.CASCADE)
    study_uid = models.CharField(max_length=255, unique=True)
    orthanc_id = models.CharField(max_length=255, unique=True)
    study_date = models.DateField()
    study_time = models.TimeField(null=True, blank=True)
    description = models.CharField(max_length=255)
    accession_number = models.CharField(max_length=64, blank=True)
    referring_physician = models.CharField(max_length=255, blank=True)
    modality = models.CharField(max_length=16)
    series_count = models.IntegerField(default=0)
    instance_count = models.IntegerField(default=0)
    stone_viewer_url = models.URLField()
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class Report(models.Model):
    exam = models.OneToOneField(Exam, on_delete=models.CASCADE)
    radiologist = models.ForeignKey('auth.User', on_delete=models.CASCADE)
    technique = models.TextField(blank=True)
    findings = models.TextField(blank=True)
    conclusion = models.TextField(blank=True)
    is_final = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    finalized_at = models.DateTimeField(null=True, blank=True)

# views.py (Django)
from django.shortcuts import render, get_object_or_404
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.utils.decorators import method_decorator
from django.views import View
import json

@method_decorator(csrf_exempt, name='dispatch')
class DicomWebhookView(View):
    def post(self, request):
        try:
            data = json.loads(request.body)
            
            if data['event'] == 'study_received':
                # Criar ou atualizar paciente
                patient, created = Patient.objects.get_or_create(
                    patient_id=data['patient']['patient_id'],
                    defaults={
                        'name': data['patient']['patient_name'],
                        'birth_date': data['patient']['patient_birth_date'],
                        'sex': data['patient']['patient_sex']
                    }
                )
                
                # Criar exame
                exam, created = Exam.objects.get_or_create(
                    study_uid=data['study']['study_uid'],
                    defaults={
                        'patient': patient,
                        'orthanc_id': data['study']['orthanc_id'],
                        'study_date': data['study']['study_date'],
                        'study_time': data['study']['study_time'],
                        'description': data['study']['study_description'],
                        'accession_number': data['study']['accession_number'],
                        'referring_physician': data['study']['referring_physician'],
                        'modality': data['study']['modality'],
                        'series_count': data['study']['series_count'],
                        'instance_count': data['study']['instance_count'],
                        'stone_viewer_url': data['urls']['stone_viewer']
                    }
                )
                
                return JsonResponse({
                    'status': 'success',
                    'exam_id': exam.id,
                    'created': created
                })
                
        except Exception as e:
            return JsonResponse({'error': str(e)}, status=400)
        
        return JsonResponse({'status': 'ignored'})

def exam_list(request):
    exams = Exam.objects.filter(status='pending').order_by('-created_at')
    return render(request, 'exams/list.html', {'exams': exams})

def exam_report(request, exam_id):
    exam = get_object_or_404(Exam, id=exam_id)
    report, created = Report.objects.get_or_create(
        exam=exam,
        defaults={'radiologist': request.user}
    )
    return render(request, 'exams/report.html', {
        'exam': exam,
        'report': report
    })
```

---

## 📱 Interface Mobile (Opcional)

### 1. App React Native

```javascript
// ExamList.js
import React, { useState, useEffect } from 'react';
import { View, Text, FlatList, TouchableOpacity, StyleSheet } from 'react-native';

const ExamList = ({ navigation }) => {
  const [exams, setExams] = useState([]);
  
  useEffect(() => {
    fetchExams();
  }, []);
  
  const fetchExams = async () => {
    try {
      const response = await fetch('https://api.radiweb.com.br/exams/pending');
      const data = await response.json();
      setExams(data);
    } catch (error) {
      console.error('Erro ao buscar exames:', error);
    }
  };
  
  const renderExam = ({ item }) => (
    <TouchableOpacity 
      style={styles.examCard}
      onPress={() => navigation.navigate('ExamViewer', { exam: item })}
    >
      <Text style={styles.patientName}>{item.patient.name}</Text>
      <Text style={styles.examDescription}>{item.description}</Text>
      <Text style={styles.examDate}>{item.study_date}</Text>
      <Text style={styles.modality}>{item.modality}</Text>
    </TouchableOpacity>
  );
  
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Exames Pendentes</Text>
      <FlatList
        data={exams}
        renderItem={renderExam}
        keyExtractor={item => item.id.toString()}
        refreshing={false}
        onRefresh={fetchExams}
      />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 16,
    backgroundColor: '#f5f5f5'
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 16
  },
  examCard: {
    backgroundColor: 'white',
    padding: 16,
    marginBottom: 8,
    borderRadius: 8,
    elevation: 2
  },
  patientName: {
    fontSize: 18,
    fontWeight: 'bold'
  },
  examDescription: {
    fontSize: 14,
    color: '#666',
    marginTop: 4
  },
  examDate: {
    fontSize: 12,
    color: '#999',
    marginTop: 4
  },
  modality: {
    fontSize: 12,
    backgroundColor: '#007bff',
    color: 'white',
    padding: 4,
    borderRadius: 4,
    alignSelf: 'flex-start',
    marginTop: 8
  }
});

export default ExamList;
```

---

## 🔧 Configuração de Equipamentos

### 1. Configuração Geral

Para configurar qualquer equipamento DICOM para enviar ao PACS:

```
Nome do Servidor: RADIWEB_PACS
Endereço IP/Host: pacs.radiweb.com.br
Porta: 4242
AE Title Local: [NOME_DO_EQUIPAMENTO]
AE Title Remoto: RADIWEB_PACS
Timeout: 30 segundos
```

### 2. Equipamentos Específicos

#### Tomógrafo (CT)
```
Modalidade: CT
Compressão: Sem compressão (recomendado)
Transfer Syntax: Explicit VR Little Endian
Auto-send: Habilitado
```

#### Ressonância (MR)
```
Modalidade: MR
Compressão: JPEG Lossless (opcional)
Transfer Syntax: Explicit VR Little Endian
Auto-send: Habilitado
```

#### Ultrassom (US)
```
Modalidade: US
Compressão: JPEG Lossy (aceitável)
Transfer Syntax: Explicit VR Little Endian
Auto-send: Habilitado
```

### 3. Teste de Conectividade

```bash
# Testar conectividade do equipamento
echoscu -aec RADIWEB_PACS pacs.radiweb.com.br 4242

# Enviar imagem de teste
storescu -aec RADIWEB_PACS pacs.radiweb.com.br 4242 test_image.dcm
```

---

## 📊 Relatórios e Analytics

### 1. Dashboard de Métricas

```python
# dashboard_metrics.py
from django.db.models import Count, Q
from datetime import datetime, timedelta

def get_dashboard_metrics():
    today = datetime.now().date()
    week_ago = today - timedelta(days=7)
    month_ago = today - timedelta(days=30)
    
    metrics = {
        'exams_today': Exam.objects.filter(created_at__date=today).count(),
        'exams_week': Exam.objects.filter(created_at__date__gte=week_ago).count(),
        'exams_month': Exam.objects.filter(created_at__date__gte=month_ago).count(),
        
        'pending_exams': Exam.objects.filter(status='pending').count(),
        'completed_exams': Exam.objects.filter(status='completed').count(),
        
        'exams_by_modality': Exam.objects.values('modality').annotate(
            count=Count('id')
        ).order_by('-count'),
        
        'avg_report_time': Report.objects.filter(
            is_final=True,
            finalized_at__isnull=False
        ).aggregate(
            avg_time=Avg(
                Extract('epoch', F('finalized_at') - F('created_at')) / 3600
            )
        )['avg_time']
    }
    
    return metrics
```

### 2. Relatório de Produtividade

```python
# productivity_report.py
def generate_productivity_report(radiologist_id, start_date, end_date):
    reports = Report.objects.filter(
        radiologist_id=radiologist_id,
        finalized_at__date__range=[start_date, end_date],
        is_final=True
    )
    
    return {
        'total_reports': reports.count(),
        'reports_by_modality': reports.values('exam__modality').annotate(
            count=Count('id')
        ),
        'avg_time_per_report': reports.aggregate(
            avg_time=Avg(
                Extract('epoch', F('finalized_at') - F('created_at')) / 60
            )
        )['avg_time'],
        'reports_by_day': reports.extra(
            select={'day': 'date(finalized_at)'}
        ).values('day').annotate(count=Count('id')).order_by('day')
    }
```

---

## 🔒 Segurança e Compliance

### 1. LGPD/GDPR Compliance

```python
# privacy_manager.py
class PrivacyManager:
    @staticmethod
    def anonymize_patient_data(patient_id):
        """Anonimizar dados do paciente"""
        patient = Patient.objects.get(patient_id=patient_id)
        
        # Anonimizar dados pessoais
        patient.name = f"ANONIMO_{patient.id}"
        patient.birth_date = None
        patient.save()
        
        # Anonimizar dados DICOM no Orthanc
        pacs = RadiwebPACSClient(settings.PACS_URL, settings.PACS_USER, settings.PACS_PASS)
        studies = pacs.get_studies(patient_id=patient_id)
        
        for study in studies:
            pacs.anonymize_study(study['orthanc_id'])
    
    @staticmethod
    def delete_patient_data(patient_id):
        """Deletar completamente dados do paciente"""
        # Deletar do banco Radiweb
        Patient.objects.filter(patient_id=patient_id).delete()
        
        # Deletar do PACS
        pacs = RadiwebPACSClient(settings.PACS_URL, settings.PACS_USER, settings.PACS_PASS)
        studies = pacs.get_studies(patient_id=patient_id)
        
        for study in studies:
            pacs.delete_study(study['orthanc_id'])
```

### 2. Auditoria de Acesso

```python
# audit_log.py
class AuditLog(models.Model):
    user = models.ForeignKey('auth.User', on_delete=models.CASCADE)
    action = models.CharField(max_length=50)
    resource_type = models.CharField(max_length=50)
    resource_id = models.CharField(max_length=255)
    ip_address = models.GenericIPAddressField()
    user_agent = models.TextField()
    timestamp = models.DateTimeField(auto_now_add=True)
    
    @classmethod
    def log_access(cls, user, action, resource_type, resource_id, request):
        cls.objects.create(
            user=user,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            ip_address=get_client_ip(request),
            user_agent=request.META.get('HTTP_USER_AGENT', '')
        )

# Middleware para auditoria
class AuditMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response
    
    def __call__(self, request):
        response = self.get_response(request)
        
        # Log acessos a exames
        if request.path.startswith('/exams/') and request.user.is_authenticated:
            exam_id = request.resolver_match.kwargs.get('exam_id')
            if exam_id:
                AuditLog.log_access(
                    request.user,
                    'view_exam',
                    'exam',
                    exam_id,
                    request
                )
        
        return response
```

---

## ✅ Checklist de Integração

### Configuração Inicial
- [ ] Orthanc PACS deployado e funcionando
- [ ] Webhook configurado no Orthanc
- [ ] Endpoint webhook implementado no Radiweb
- [ ] Credenciais de API configuradas
- [ ] Testes de conectividade passando

### Integração Backend
- [ ] Modelos de dados criados (Patient, Exam, Report)
- [ ] API de integração implementada
- [ ] Webhook handler funcionando
- [ ] Cliente PACS configurado
- [ ] Testes automatizados criados

### Interface Frontend
- [ ] Lista de exames implementada
- [ ] Integração com Stone Web Viewer
- [ ] Tela de laudo criada
- [ ] Banco de frases configurado
- [ ] Notificações implementadas

### Equipamentos
- [ ] Equipamentos configurados para enviar ao PACS
- [ ] Testes de envio DICOM realizados
- [ ] Workflow de recepção validado
- [ ] Notificações funcionando

### Segurança e Compliance
- [ ] Auditoria de acesso implementada
- [ ] Políticas de privacidade configuradas
- [ ] Backup e recovery testados
- [ ] Monitoramento ativo

### Produção
- [ ] Sistema em produção
- [ ] Usuários treinados
- [ ] Documentação atualizada
- [ ] Suporte configurado

---

**🎉 Integração Concluída!**

O Orthanc PACS está agora totalmente integrado com o sistema Radiweb, oferecendo uma solução completa para recepção, armazenamento, visualização e laudagem de exames radiológicos.

*Guia de integração gerado pelo Manus AI - Janeiro 2024*

