#!/usr/bin/env python3
"""
Script para testar conectividade DICOM com o Orthanc PACS Radiweb
Autor: Manus AI
Data: 2024-01-01
"""

import sys
import time
import argparse
from datetime import datetime

try:
    from pynetdicom import AE, debug_logger
    from pynetdicom.sop_class import (
        VerificationSOPClass, 
        CTImageStorage, 
        MRImageStorage,
        StudyRootQueryRetrieveInformationModelFind,
        StudyRootQueryRetrieveInformationModelMove
    )
    from pydicom.dataset import Dataset
except ImportError:
    print("❌ pynetdicom não está instalado. Instale com: pip install pynetdicom")
    sys.exit(1)

class DicomTester:
    def __init__(self, host, port, ae_title, calling_ae='TEST_AE'):
        self.host = host
        self.port = port
        self.ae_title = ae_title
        self.calling_ae = calling_ae
        self.ae = AE(ae_title=calling_ae)
        
        # Configurar contextos
        self.ae.add_requested_context(VerificationSOPClass)
        self.ae.add_requested_context(CTImageStorage)
        self.ae.add_requested_context(MRImageStorage)
        self.ae.add_requested_context(StudyRootQueryRetrieveInformationModelFind)
        self.ae.add_requested_context(StudyRootQueryRetrieveInformationModelMove)
    
    def test_echo(self):
        """Testar C-ECHO (verificação de conectividade)"""
        print("🔍 Testando C-ECHO...")
        
        try:
            # Estabelecer associação
            assoc = self.ae.associate(self.host, self.port, ae_title=self.ae_title)
            
            if assoc.is_established:
                print(f"✅ Associação estabelecida com {self.host}:{self.port}")
                
                # Enviar C-ECHO
                status = assoc.send_c_echo()
                
                if status:
                    print(f"✅ C-ECHO bem-sucedido - Status: {status}")
                    result = True
                else:
                    print("❌ C-ECHO falhou")
                    result = False
                
                # Liberar associação
                assoc.release()
                
            else:
                print(f"❌ Não foi possível estabelecer associação com {self.host}:{self.port}")
                result = False
                
        except Exception as e:
            print(f"❌ Erro no C-ECHO: {e}")
            result = False
        
        return result
    
    def test_store(self, dicom_file):
        """Testar C-STORE (envio de imagem)"""
        print(f"📤 Testando C-STORE com {dicom_file}...")
        
        try:
            from pydicom import dcmread
            
            # Ler arquivo DICOM
            ds = dcmread(dicom_file)
            print(f"   Paciente: {ds.PatientName}")
            print(f"   Modalidade: {ds.Modality}")
            print(f"   Study UID: {ds.StudyInstanceUID}")
            
            # Estabelecer associação
            assoc = self.ae.associate(self.host, self.port, ae_title=self.ae_title)
            
            if assoc.is_established:
                # Enviar C-STORE
                status = assoc.send_c_store(ds)
                
                if status:
                    print(f"✅ C-STORE bem-sucedido - Status: {status}")
                    result = True
                else:
                    print("❌ C-STORE falhou")
                    result = False
                
                assoc.release()
                
            else:
                print("❌ Não foi possível estabelecer associação")
                result = False
                
        except FileNotFoundError:
            print(f"❌ Arquivo não encontrado: {dicom_file}")
            result = False
        except Exception as e:
            print(f"❌ Erro no C-STORE: {e}")
            result = False
        
        return result
    
    def test_find(self, patient_id=None):
        """Testar C-FIND (busca de estudos)"""
        print("🔍 Testando C-FIND...")
        
        try:
            # Criar dataset de busca
            ds = Dataset()
            ds.QueryRetrieveLevel = 'STUDY'
            ds.StudyInstanceUID = ''
            ds.PatientName = ''
            ds.PatientID = patient_id or ''
            ds.StudyDate = ''
            ds.StudyDescription = ''
            ds.Modality = ''
            
            # Estabelecer associação
            assoc = self.ae.associate(self.host, self.port, ae_title=self.ae_title)
            
            if assoc.is_established:
                # Enviar C-FIND
                responses = assoc.send_c_find(ds, StudyRootQueryRetrieveInformationModelFind)
                
                studies_found = 0
                for (status, identifier) in responses:
                    if status:
                        if identifier:
                            studies_found += 1
                            print(f"   📋 Estudo {studies_found}:")
                            print(f"      Paciente: {identifier.get('PatientName', 'N/A')}")
                            print(f"      ID: {identifier.get('PatientID', 'N/A')}")
                            print(f"      Data: {identifier.get('StudyDate', 'N/A')}")
                            print(f"      Descrição: {identifier.get('StudyDescription', 'N/A')}")
                            print(f"      UID: {identifier.get('StudyInstanceUID', 'N/A')}")
                    else:
                        print(f"❌ Erro na busca: {status}")
                
                if studies_found > 0:
                    print(f"✅ C-FIND bem-sucedido - {studies_found} estudos encontrados")
                    result = True
                else:
                    print("⚠️ C-FIND executado, mas nenhum estudo encontrado")
                    result = True  # Tecnicamente bem-sucedido
                
                assoc.release()
                
            else:
                print("❌ Não foi possível estabelecer associação")
                result = False
                
        except Exception as e:
            print(f"❌ Erro no C-FIND: {e}")
            result = False
        
        return result
    
    def test_connection_speed(self, iterations=5):
        """Testar velocidade de conexão"""
        print(f"⚡ Testando velocidade de conexão ({iterations} iterações)...")
        
        times = []
        successful = 0
        
        for i in range(iterations):
            start_time = time.time()
            
            try:
                assoc = self.ae.associate(self.host, self.port, ae_title=self.ae_title)
                
                if assoc.is_established:
                    status = assoc.send_c_echo()
                    assoc.release()
                    
                    if status:
                        end_time = time.time()
                        connection_time = end_time - start_time
                        times.append(connection_time)
                        successful += 1
                        print(f"   Teste {i+1}: {connection_time:.3f}s")
                    
            except Exception as e:
                print(f"   Teste {i+1}: Falhou - {e}")
        
        if times:
            avg_time = sum(times) / len(times)
            min_time = min(times)
            max_time = max(times)
            
            print(f"✅ Velocidade de conexão:")
            print(f"   Sucessos: {successful}/{iterations}")
            print(f"   Tempo médio: {avg_time:.3f}s")
            print(f"   Tempo mínimo: {min_time:.3f}s")
            print(f"   Tempo máximo: {max_time:.3f}s")
            
            return avg_time < 2.0  # Considerado bom se < 2s
        else:
            print("❌ Nenhuma conexão bem-sucedida")
            return False
    
    def run_all_tests(self, dicom_file=None):
        """Executar todos os testes"""
        print(f"🏥 Iniciando testes DICOM para {self.host}:{self.port}")
        print(f"   AE Title: {self.ae_title}")
        print(f"   Calling AE: {self.calling_ae}")
        print(f"   Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 60)
        
        results = {}
        
        # Teste 1: C-ECHO
        results['echo'] = self.test_echo()
        print()
        
        # Teste 2: C-FIND
        results['find'] = self.test_find()
        print()
        
        # Teste 3: C-STORE (se arquivo fornecido)
        if dicom_file:
            results['store'] = self.test_store(dicom_file)
            print()
        
        # Teste 4: Velocidade
        results['speed'] = self.test_connection_speed()
        print()
        
        # Resumo
        print("📊 Resumo dos Testes")
        print("=" * 60)
        
        total_tests = len(results)
        passed_tests = sum(1 for result in results.values() if result)
        
        for test_name, result in results.items():
            status = "✅ PASSOU" if result else "❌ FALHOU"
            print(f"   {test_name.upper()}: {status}")
        
        print(f"\n🎯 Resultado Final: {passed_tests}/{total_tests} testes passaram")
        
        if passed_tests == total_tests:
            print("🎉 Todos os testes passaram! DICOM está funcionando perfeitamente.")
        elif passed_tests > 0:
            print("⚠️ Alguns testes falharam. Verifique a configuração.")
        else:
            print("❌ Todos os testes falharam. Verifique conectividade e configuração.")
        
        return passed_tests == total_tests

def main():
    parser = argparse.ArgumentParser(description='Testar conectividade DICOM')
    parser.add_argument('--host', default='pacs.radiweb.com.br',
                       help='Hostname do servidor DICOM')
    parser.add_argument('--port', type=int, default=4242,
                       help='Porta do servidor DICOM')
    parser.add_argument('--ae-title', default='RADIWEB_PACS',
                       help='AE Title do servidor')
    parser.add_argument('--calling-ae', default='TEST_AE',
                       help='AE Title do cliente')
    parser.add_argument('--dicom-file',
                       help='Arquivo DICOM para teste de C-STORE')
    parser.add_argument('--patient-id',
                       help='ID do paciente para busca C-FIND')
    parser.add_argument('--verbose', action='store_true',
                       help='Ativar logs detalhados')
    parser.add_argument('--test', choices=['echo', 'find', 'store', 'speed', 'all'],
                       default='all', help='Tipo de teste a executar')
    
    args = parser.parse_args()
    
    # Ativar logs se solicitado
    if args.verbose:
        debug_logger()
    
    # Criar testador
    tester = DicomTester(args.host, args.port, args.ae_title, args.calling_ae)
    
    # Executar testes
    if args.test == 'all':
        success = tester.run_all_tests(args.dicom_file)
    elif args.test == 'echo':
        success = tester.test_echo()
    elif args.test == 'find':
        success = tester.test_find(args.patient_id)
    elif args.test == 'store':
        if not args.dicom_file:
            print("❌ Arquivo DICOM necessário para teste de C-STORE")
            sys.exit(1)
        success = tester.test_store(args.dicom_file)
    elif args.test == 'speed':
        success = tester.test_connection_speed()
    
    # Código de saída
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()

