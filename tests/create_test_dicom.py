#!/usr/bin/env python3
"""
Script para criar imagens DICOM de teste para o Orthanc PACS Radiweb
Autor: Manus AI
Data: 2024-01-01
"""

import os
import sys
import numpy as np
from datetime import datetime
import argparse

try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import ExplicitVRLittleEndian, generate_uid
    from pydicom.uid import CTImageStorage, MRImageStorage, USImageStorage
except ImportError:
    print("❌ pydicom não está instalado. Instale com: pip install pydicom")
    sys.exit(1)

def create_test_image(rows=512, cols=512, pattern='gradient'):
    """Criar imagem de teste com diferentes padrões"""
    image = np.zeros((rows, cols), dtype=np.uint16)
    
    if pattern == 'gradient':
        # Gradiente diagonal
        for i in range(rows):
            for j in range(cols):
                image[i, j] = int((i + j) * 65535 / (rows + cols))
    
    elif pattern == 'checkerboard':
        # Padrão xadrez
        square_size = 32
        for i in range(rows):
            for j in range(cols):
                if ((i // square_size) + (j // square_size)) % 2:
                    image[i, j] = 65535
    
    elif pattern == 'circles':
        # Círculos concêntricos
        center_x, center_y = rows // 2, cols // 2
        for i in range(rows):
            for j in range(cols):
                distance = np.sqrt((i - center_x)**2 + (j - center_y)**2)
                image[i, j] = int((np.sin(distance / 20) + 1) * 32767)
    
    elif pattern == 'noise':
        # Ruído aleatório
        image = np.random.randint(0, 65536, (rows, cols), dtype=np.uint16)
    
    return image

def create_dicom_dataset(patient_name, patient_id, modality='CT', pattern='gradient'):
    """Criar dataset DICOM completo"""
    
    # Dataset principal
    ds = Dataset()
    
    # Metadados do paciente
    ds.PatientName = patient_name
    ds.PatientID = patient_id
    ds.PatientBirthDate = "19900101"
    ds.PatientSex = "M"
    ds.PatientAge = "034Y"
    ds.PatientWeight = "70"
    
    # Metadados do estudo
    ds.StudyInstanceUID = generate_uid()
    ds.StudyDate = datetime.now().strftime("%Y%m%d")
    ds.StudyTime = datetime.now().strftime("%H%M%S")
    ds.StudyDescription = f"Teste Radiweb PACS - {modality}"
    ds.AccessionNumber = f"ACC{datetime.now().strftime('%Y%m%d%H%M%S')}"
    ds.StudyID = "1"
    ds.ReferringPhysicianName = "Dr. Teste Radiweb"
    
    # Metadados da série
    ds.SeriesInstanceUID = generate_uid()
    ds.SeriesNumber = "1"
    ds.SeriesDescription = f"Teste Stone Viewer - {pattern}"
    ds.Modality = modality
    ds.SeriesDate = ds.StudyDate
    ds.SeriesTime = ds.StudyTime
    
    # Metadados da instância
    ds.SOPInstanceUID = generate_uid()
    ds.InstanceNumber = "1"
    ds.ImagePositionPatient = [0, 0, 0]
    ds.ImageOrientationPatient = [1, 0, 0, 0, 1, 0]
    ds.SliceThickness = "5.0"
    ds.SliceLocation = "0.0"
    
    # Configurar SOP Class baseado na modalidade
    if modality == 'CT':
        ds.SOPClassUID = CTImageStorage
        ds.KVP = "120"
        ds.XRayTubeCurrent = "200"
        ds.ExposureTime = "1000"
        ds.ConvolutionKernel = "STANDARD"
    elif modality == 'MR':
        ds.SOPClassUID = MRImageStorage
        ds.MagneticFieldStrength = "1.5"
        ds.EchoTime = "10"
        ds.RepetitionTime = "500"
        ds.FlipAngle = "90"
        ds.SequenceName = "T1_SE"
    elif modality == 'US':
        ds.SOPClassUID = USImageStorage
        ds.TransducerFrequency = "5.0"
        ds.MechanicalIndex = "0.5"
        ds.ThermalIndex = "0.3"
    else:
        ds.SOPClassUID = CTImageStorage  # Default
    
    # Dados da imagem
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"
    ds.Rows = 512
    ds.Columns = 512
    ds.BitsAllocated = 16
    ds.BitsStored = 16
    ds.HighBit = 15
    ds.PixelRepresentation = 0
    ds.PixelSpacing = [0.5, 0.5]
    ds.WindowCenter = "32768"
    ds.WindowWidth = "65536"
    
    # Criar imagem de teste
    image = create_test_image(512, 512, pattern)
    ds.PixelData = image.tobytes()
    
    return ds

def save_dicom_file(ds, filename):
    """Salvar dataset como arquivo DICOM"""
    
    # Metadados do arquivo
    file_meta = Dataset()
    file_meta.MediaStorageSOPClassUID = ds.SOPClassUID
    file_meta.MediaStorageSOPInstanceUID = ds.SOPInstanceUID
    file_meta.ImplementationClassUID = generate_uid()
    file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
    
    # Criar FileDataset
    file_ds = FileDataset(filename, ds, file_meta=file_meta, preamble=b"\0" * 128)
    
    # Salvar arquivo
    file_ds.save_as(filename)
    return filename

def create_test_series(patient_name, patient_id, modality='CT', num_images=5, pattern='gradient'):
    """Criar série de imagens DICOM de teste"""
    
    series_uid = generate_uid()
    study_uid = generate_uid()
    filenames = []
    
    for i in range(num_images):
        # Criar dataset
        ds = create_dicom_dataset(patient_name, patient_id, modality, pattern)
        
        # Usar mesmos UIDs para a série
        ds.StudyInstanceUID = study_uid
        ds.SeriesInstanceUID = series_uid
        ds.InstanceNumber = str(i + 1)
        ds.SOPInstanceUID = generate_uid()
        
        # Ajustar posição da fatia
        ds.SliceLocation = str(i * 5.0)
        ds.ImagePositionPatient = [0, 0, i * 5.0]
        
        # Criar imagem com variação
        if pattern == 'gradient':
            image = create_test_image(512, 512, 'gradient')
            # Adicionar variação por fatia
            image = image + (i * 5000)
            image = np.clip(image, 0, 65535).astype(np.uint16)
        else:
            image = create_test_image(512, 512, pattern)
        
        ds.PixelData = image.tobytes()
        
        # Salvar arquivo
        filename = f"test_{modality.lower()}_{patient_id}_slice_{i+1:03d}.dcm"
        save_dicom_file(ds, filename)
        filenames.append(filename)
        
        print(f"✅ Criado: {filename}")
    
    return filenames

def main():
    parser = argparse.ArgumentParser(description='Criar imagens DICOM de teste')
    parser.add_argument('--patient-name', default='TESTE^RADIWEB', 
                       help='Nome do paciente (formato: SOBRENOME^NOME)')
    parser.add_argument('--patient-id', default='TEST001', 
                       help='ID do paciente')
    parser.add_argument('--modality', choices=['CT', 'MR', 'US'], default='CT',
                       help='Modalidade DICOM')
    parser.add_argument('--pattern', choices=['gradient', 'checkerboard', 'circles', 'noise'], 
                       default='gradient', help='Padrão da imagem')
    parser.add_argument('--num-images', type=int, default=1,
                       help='Número de imagens na série')
    parser.add_argument('--output-dir', default='.',
                       help='Diretório de saída')
    
    args = parser.parse_args()
    
    # Criar diretório de saída
    os.makedirs(args.output_dir, exist_ok=True)
    os.chdir(args.output_dir)
    
    print(f"🏥 Criando imagens DICOM de teste...")
    print(f"   Paciente: {args.patient_name} ({args.patient_id})")
    print(f"   Modalidade: {args.modality}")
    print(f"   Padrão: {args.pattern}")
    print(f"   Número de imagens: {args.num_images}")
    print(f"   Diretório: {args.output_dir}")
    print()
    
    if args.num_images == 1:
        # Criar imagem única
        ds = create_dicom_dataset(args.patient_name, args.patient_id, 
                                args.modality, args.pattern)
        filename = f"test_{args.modality.lower()}_{args.patient_id}.dcm"
        save_dicom_file(ds, filename)
        print(f"✅ Criado: {filename}")
        
        # Mostrar informações
        print(f"\n📋 Informações do arquivo:")
        print(f"   Study UID: {ds.StudyInstanceUID}")
        print(f"   Series UID: {ds.SeriesInstanceUID}")
        print(f"   SOP Instance UID: {ds.SOPInstanceUID}")
        
    else:
        # Criar série de imagens
        filenames = create_test_series(args.patient_name, args.patient_id,
                                     args.modality, args.num_images, args.pattern)
        
        print(f"\n✅ Série criada com {len(filenames)} imagens")
    
    print(f"\n🚀 Para enviar ao Orthanc:")
    print(f"   curl -X POST -u admin:admin \\")
    print(f"     -H 'Content-Type: application/dicom' \\")
    print(f"     --data-binary @{filename if args.num_images == 1 else filenames[0]} \\")
    print(f"     https://pacs.radiweb.com.br/instances")

if __name__ == "__main__":
    main()

