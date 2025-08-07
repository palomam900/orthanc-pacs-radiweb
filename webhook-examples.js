// Exemplos de Webhook para Integração Radiweb
// Autor: Manus AI
// Data: 2024-01-01

// ============================================================================
// 1. WEBHOOK PARA RECEBER NOTIFICAÇÕES DE NOVOS ESTUDOS DICOM
// ============================================================================

/**
 * Endpoint para receber notificações quando novos estudos DICOM chegam
 * URL: https://api.radiweb.com.br/webhook/dicom/study-received
 */
async function handleStudyReceived(req, res) {
  try {
    const { 
      event, 
      study_id, 
      patient_id, 
      patient_name,
      study_date,
      modality,
      timestamp 
    } = req.body;

    // Validar webhook secret
    const receivedSecret = req.headers['x-webhook-secret'];
    if (receivedSecret !== process.env.WEBHOOK_SECRET) {
      return res.status(401).json({ error: 'Invalid webhook secret' });
    }

    console.log(`📥 Novo estudo DICOM recebido: ${study_id}`);

    // 1. Salvar informações do estudo no banco Radiweb
    await saveStudyToDatabase({
      orthancStudyId: study_id,
      patientId: patient_id,
      patientName: patient_name,
      studyDate: study_date,
      modality: modality,
      receivedAt: new Date(timestamp),
      status: 'received'
    });

    // 2. Buscar exame correspondente no sistema Radiweb
    const exam = await findExamByPatientId(patient_id);
    
    if (exam) {
      // 3. Associar estudo DICOM ao exame
      await linkStudyToExam(exam.id, study_id);
      
      // 4. Gerar link de compartilhamento Stone Viewer
      const viewerUrl = await generateStoneViewerLink(study_id);
      
      // 5. Atualizar status do exame
      await updateExamStatus(exam.id, 'images_received', {
        orthancStudyId: study_id,
        viewerUrl: viewerUrl
      });

      // 6. Notificar médico responsável
      await notifyDoctor(exam.doctorId, {
        examId: exam.id,
        patientName: patient_name,
        viewerUrl: viewerUrl,
        message: 'Imagens DICOM recebidas e prontas para visualização'
      });

      console.log(`✅ Estudo ${study_id} associado ao exame ${exam.id}`);
    } else {
      console.log(`⚠️  Exame não encontrado para paciente ${patient_id}`);
      
      // Marcar como não associado para revisão manual
      await markStudyAsUnassociated(study_id, patient_id);
    }

    res.json({ 
      success: true, 
      message: 'Study processed successfully',
      study_id: study_id 
    });

  } catch (error) {
    console.error('Erro ao processar webhook:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
}

// ============================================================================
// 2. GERAÇÃO DE LINKS DO STONE WEB VIEWER
// ============================================================================

/**
 * Gerar link seguro para Stone Web Viewer
 */
async function generateStoneViewerLink(studyId) {
  const baseUrl = process.env.ORTHANC_BASE_URL || 'https://pacs.radiweb.com.br';
  
  // Opção 1: Link direto (requer autenticação)
  const directUrl = `${baseUrl}/stone-webviewer/index.html?study=${studyId}`;
  
  // Opção 2: Link com token de acesso temporário
  const accessToken = await generateTemporaryAccessToken(studyId);
  const tokenUrl = `${baseUrl}/stone-webviewer/index.html?study=${studyId}&token=${accessToken}`;
  
  return tokenUrl;
}

/**
 * Gerar token de acesso temporário para visualização
 */
async function generateTemporaryAccessToken(studyId, expiresIn = '24h') {
  const jwt = require('jsonwebtoken');
  
  const payload = {
    study_id: studyId,
    access_type: 'viewer',
    generated_at: new Date().toISOString()
  };
  
  const token = jwt.sign(payload, process.env.JWT_SECRET, { 
    expiresIn: expiresIn 
  });
  
  // Salvar token no banco para validação
  await saveAccessToken(token, studyId, expiresIn);
  
  return token;
}

// ============================================================================
// 3. WEBHOOK PARA BACKUP E MONITORAMENTO
// ============================================================================

/**
 * Webhook para notificações de backup
 */
async function handleBackupNotification(req, res) {
  try {
    const { 
      event, 
      backup_file, 
      backup_size, 
      timestamp,
      status 
    } = req.body;

    if (event === 'backup_completed' && status === 'success') {
      console.log(`💾 Backup concluído: ${backup_file} (${backup_size})`);
      
      // Registrar backup no sistema
      await registerBackup({
        filename: backup_file,
        size: backup_size,
        completedAt: new Date(timestamp),
        status: 'completed'
      });
      
      // Notificar administradores
      await notifyAdmins('backup_completed', {
        filename: backup_file,
        size: backup_size,
        timestamp: timestamp
      });
      
    } else if (status === 'failed') {
      console.error(`❌ Falha no backup: ${backup_file}`);
      
      // Alertar administradores sobre falha
      await alertAdmins('backup_failed', {
        filename: backup_file,
        timestamp: timestamp,
        error: req.body.error
      });
    }

    res.json({ success: true });

  } catch (error) {
    console.error('Erro ao processar notificação de backup:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
}

// ============================================================================
// 4. INTEGRAÇÃO COM FRONTEND RADIWEB
// ============================================================================

/**
 * API para buscar estudos DICOM de um paciente
 */
async function getPatientStudies(req, res) {
  try {
    const { patientId } = req.params;
    
    // Buscar estudos no banco Radiweb
    const studies = await getStudiesByPatientId(patientId);
    
    // Para cada estudo, buscar informações detalhadas do Orthanc
    const detailedStudies = await Promise.all(
      studies.map(async (study) => {
        const orthancData = await fetchFromOrthanc(`/studies/${study.orthancStudyId}`);
        
        return {
          id: study.id,
          orthancStudyId: study.orthancStudyId,
          patientName: orthancData.PatientMainDicomTags.PatientName,
          studyDate: orthancData.MainDicomTags.StudyDate,
          studyDescription: orthancData.MainDicomTags.StudyDescription,
          modality: orthancData.MainDicomTags.Modality,
          viewerUrl: await generateStoneViewerLink(study.orthancStudyId),
          seriesCount: orthancData.Series.length,
          instancesCount: orthancData.Instances.length
        };
      })
    );
    
    res.json(detailedStudies);

  } catch (error) {
    console.error('Erro ao buscar estudos:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
}

/**
 * Função auxiliar para fazer requisições ao Orthanc
 */
async function fetchFromOrthanc(endpoint) {
  const axios = require('axios');
  
  const response = await axios.get(`${process.env.ORTHANC_BASE_URL}${endpoint}`, {
    auth: {
      username: process.env.ORTHANC_USERNAME,
      password: process.env.ORTHANC_PASSWORD
    }
  });
  
  return response.data;
}

// ============================================================================
// 5. CONFIGURAÇÃO EXPRESS.JS
// ============================================================================

const express = require('express');
const app = express();

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Rotas de webhook
app.post('/webhook/dicom/study-received', handleStudyReceived);
app.post('/webhook/backup', handleBackupNotification);

// Rotas da API
app.get('/api/patients/:patientId/studies', getPatientStudies);

// Middleware de autenticação para rotas da API
app.use('/api', (req, res, next) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  
  if (!token) {
    return res.status(401).json({ error: 'Token required' });
  }
  
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded;
    next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid token' });
  }
});

// ============================================================================
// 6. EXEMPLO DE CONFIGURAÇÃO ORTHANC LUA SCRIPT
// ============================================================================

/*
-- Script Lua para Orthanc (salvar como webhook.lua)
-- Configurar no orthanc.json: "LuaScripts": ["/path/to/webhook.lua"]

function OnStoredInstance(instanceId, tags, metadata, origin)
    -- Extrair informações do estudo
    local studyId = tags['StudyInstanceUID']
    local patientId = tags['PatientID']
    local patientName = tags['PatientName']
    local studyDate = tags['StudyDate']
    local modality = tags['Modality']
    
    -- Preparar payload do webhook
    local payload = {
        event = 'study_received',
        study_id = studyId,
        patient_id = patientId,
        patient_name = patientName,
        study_date = studyDate,
        modality = modality,
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        instance_id = instanceId,
        origin = origin
    }
    
    -- Enviar webhook
    local webhookUrl = 'https://api.radiweb.com.br/webhook/dicom/study-received'
    local headers = {
        ['Content-Type'] = 'application/json',
        ['X-Webhook-Secret'] = 'seu_webhook_secret_aqui'
    }
    
    RestApiPost(webhookUrl, DumpJson(payload), false, headers)
    
    print('Webhook enviado para estudo: ' .. studyId)
end
*/

// ============================================================================
// 7. EXEMPLO DE CONFIGURAÇÃO DOCKER-COMPOSE COM WEBHOOK
// ============================================================================

/*
# Adicionar ao docker-compose.yml

services:
  webhook-service:
    build: ./webhook-service
    container_name: radiweb-webhook
    restart: unless-stopped
    environment:
      - NODE_ENV=production
      - WEBHOOK_SECRET=${WEBHOOK_SECRET}
      - JWT_SECRET=${JWT_SECRET}
      - ORTHANC_BASE_URL=http://orthanc:8042
      - ORTHANC_USERNAME=admin
      - ORTHANC_PASSWORD=${ADMIN_PASSWORD}
      - DATABASE_URL=${DATABASE_URL}
    ports:
      - "3000:3000"
    networks:
      - orthanc-network
    depends_on:
      - orthanc
      - postgres
*/

module.exports = {
  handleStudyReceived,
  handleBackupNotification,
  getPatientStudies,
  generateStoneViewerLink,
  generateTemporaryAccessToken
};

