#!/usr/bin/env python3
"""
Script para testar API REST do Orthanc PACS Radiweb
Autor: Manus AI
Data: 2024-01-01
"""

import sys
import json
import time
import argparse
from datetime import datetime
import concurrent.futures

try:
    import requests
    from requests.auth import HTTPBasicAuth
except ImportError:
    print("❌ requests não está instalado. Instale com: pip install requests")
    sys.exit(1)

class OrthancAPITester:
    def __init__(self, base_url, username, password, timeout=30):
        self.base_url = base_url.rstrip('/')
        self.auth = HTTPBasicAuth(username, password)
        self.timeout = timeout
        self.session = requests.Session()
        self.session.auth = self.auth
        
    def test_connection(self):
        """Testar conectividade básica"""
        print("🔍 Testando conectividade básica...")
        
        try:
            response = self.session.get(f"{self.base_url}/system", timeout=self.timeout)
            
            if response.status_code == 200:
                data = response.json()
                print(f"✅ Conectividade OK")
                print(f"   Nome: {data.get('Name', 'N/A')}")
                print(f"   Versão: {data.get('Version', 'N/A')}")
                print(f"   API Versão: {data.get('ApiVersion', 'N/A')}")
                return True
            else:
                print(f"❌ Conectividade falhou - Status: {response.status_code}")
                return False
                
        except requests.exceptions.RequestException as e:
            print(f"❌ Erro de conexão: {e}")
            return False
    
    def test_authentication(self):
        """Testar autenticação"""
        print("🔐 Testando autenticação...")
        
        # Teste sem autenticação
        try:
            response = requests.get(f"{self.base_url}/system", timeout=self.timeout)
            if response.status_code == 401:
                print("✅ Autenticação obrigatória (sem credenciais = 401)")
            else:
                print(f"⚠️ Acesso sem autenticação permitido - Status: {response.status_code}")
        except:
            pass
        
        # Teste com credenciais inválidas
        try:
            invalid_auth = HTTPBasicAuth("invalid", "invalid")
            response = requests.get(f"{self.base_url}/system", auth=invalid_auth, timeout=self.timeout)
            if response.status_code == 401:
                print("✅ Credenciais inválidas rejeitadas (401)")
            else:
                print(f"⚠️ Credenciais inválidas aceitas - Status: {response.status_code}")
        except:
            pass
        
        # Teste com credenciais válidas
        try:
            response = self.session.get(f"{self.base_url}/system", timeout=self.timeout)
            if response.status_code == 200:
                print("✅ Credenciais válidas aceitas (200)")
                return True
            else:
                print(f"❌ Credenciais válidas rejeitadas - Status: {response.status_code}")
                return False
        except Exception as e:
            print(f"❌ Erro na autenticação: {e}")
            return False
    
    def test_endpoints(self):
        """Testar endpoints principais"""
        print("🔌 Testando endpoints principais...")
        
        endpoints = {
            '/system': 'Informações do sistema',
            '/statistics': 'Estatísticas',
            '/patients': 'Lista de pacientes',
            '/studies': 'Lista de estudos',
            '/series': 'Lista de séries',
            '/instances': 'Lista de instâncias',
            '/changes': 'Log de mudanças',
            '/plugins': 'Plugins instalados'
        }
        
        results = {}
        
        for endpoint, description in endpoints.items():
            try:
                response = self.session.get(f"{self.base_url}{endpoint}", timeout=self.timeout)
                
                if response.status_code == 200:
                    print(f"   ✅ {endpoint} - {description}")
                    results[endpoint] = True
                else:
                    print(f"   ❌ {endpoint} - Status: {response.status_code}")
                    results[endpoint] = False
                    
            except Exception as e:
                print(f"   ❌ {endpoint} - Erro: {e}")
                results[endpoint] = False
        
        successful = sum(1 for result in results.values() if result)
        total = len(results)
        
        print(f"📊 Endpoints: {successful}/{total} funcionando")
        return successful == total
    
    def test_dicomweb(self):
        """Testar endpoints DICOMweb"""
        print("🔬 Testando DICOMweb...")
        
        dicomweb_endpoints = {
            '/dicom-web/studies': 'QIDO-RS Studies',
            '/dicom-web/series': 'QIDO-RS Series',
            '/dicom-web/instances': 'QIDO-RS Instances'
        }
        
        results = {}
        
        for endpoint, description in dicomweb_endpoints.items():
            try:
                response = self.session.get(f"{self.base_url}{endpoint}", timeout=self.timeout)
                
                if response.status_code in [200, 204]:  # 204 = No Content (vazio)
                    print(f"   ✅ {endpoint} - {description}")
                    results[endpoint] = True
                else:
                    print(f"   ❌ {endpoint} - Status: {response.status_code}")
                    results[endpoint] = False
                    
            except Exception as e:
                print(f"   ❌ {endpoint} - Erro: {e}")
                results[endpoint] = False
        
        successful = sum(1 for result in results.values() if result)
        total = len(results)
        
        print(f"📊 DICOMweb: {successful}/{total} funcionando")
        return successful == total
    
    def test_stone_viewer(self):
        """Testar Stone Web Viewer"""
        print("👁️ Testando Stone Web Viewer...")
        
        try:
            response = self.session.get(f"{self.base_url}/stone-webviewer/", timeout=self.timeout)
            
            if response.status_code == 200:
                content = response.text.lower()
                
                if 'stone' in content or 'viewer' in content or 'orthanc' in content:
                    print("✅ Stone Web Viewer carregando")
                    return True
                else:
                    print("⚠️ Stone Web Viewer responde mas conteúdo suspeito")
                    return False
            else:
                print(f"❌ Stone Web Viewer não acessível - Status: {response.status_code}")
                return False
                
        except Exception as e:
            print(f"❌ Erro ao acessar Stone Web Viewer: {e}")
            return False
    
    def test_upload_dicom(self, dicom_file):
        """Testar upload de arquivo DICOM"""
        print(f"📤 Testando upload DICOM: {dicom_file}")
        
        try:
            with open(dicom_file, 'rb') as f:
                files = {'file': f}
                headers = {'Content-Type': 'application/dicom'}
                
                response = self.session.post(
                    f"{self.base_url}/instances",
                    data=f.read(),
                    headers=headers,
                    timeout=self.timeout
                )
            
            if response.status_code == 200:
                data = response.json()
                print(f"✅ Upload bem-sucedido")
                print(f"   ID: {data.get('ID', 'N/A')}")
                print(f"   Status: {data.get('Status', 'N/A')}")
                return True
            else:
                print(f"❌ Upload falhou - Status: {response.status_code}")
                print(f"   Resposta: {response.text}")
                return False
                
        except FileNotFoundError:
            print(f"❌ Arquivo não encontrado: {dicom_file}")
            return False
        except Exception as e:
            print(f"❌ Erro no upload: {e}")
            return False
    
    def test_performance(self, iterations=10):
        """Testar performance da API"""
        print(f"⚡ Testando performance ({iterations} requisições)...")
        
        def make_request():
            start_time = time.time()
            try:
                response = self.session.get(f"{self.base_url}/system", timeout=self.timeout)
                end_time = time.time()
                
                if response.status_code == 200:
                    return end_time - start_time
                else:
                    return None
            except:
                return None
        
        # Teste sequencial
        print("   📊 Teste sequencial...")
        sequential_times = []
        for i in range(iterations):
            response_time = make_request()
            if response_time:
                sequential_times.append(response_time)
        
        # Teste paralelo
        print("   📊 Teste paralelo...")
        parallel_times = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(make_request) for _ in range(iterations)]
            for future in concurrent.futures.as_completed(futures):
                response_time = future.result()
                if response_time:
                    parallel_times.append(response_time)
        
        # Análise dos resultados
        if sequential_times and parallel_times:
            seq_avg = sum(sequential_times) / len(sequential_times)
            par_avg = sum(parallel_times) / len(parallel_times)
            
            print(f"✅ Performance:")
            print(f"   Sequencial: {seq_avg:.3f}s (média)")
            print(f"   Paralelo: {par_avg:.3f}s (média)")
            print(f"   Sucessos: {len(sequential_times)}/{iterations} seq, {len(parallel_times)}/{iterations} par")
            
            return seq_avg < 2.0 and par_avg < 5.0  # Limites aceitáveis
        else:
            print("❌ Falha nos testes de performance")
            return False
    
    def test_cors(self):
        """Testar configuração CORS"""
        print("🌐 Testando CORS...")
        
        try:
            # Fazer requisição OPTIONS (preflight)
            response = self.session.options(f"{self.base_url}/system", timeout=self.timeout)
            
            headers = response.headers
            
            cors_headers = {
                'Access-Control-Allow-Origin': headers.get('Access-Control-Allow-Origin'),
                'Access-Control-Allow-Methods': headers.get('Access-Control-Allow-Methods'),
                'Access-Control-Allow-Headers': headers.get('Access-Control-Allow-Headers')
            }
            
            if any(cors_headers.values()):
                print("✅ CORS configurado")
                for header, value in cors_headers.items():
                    if value:
                        print(f"   {header}: {value}")
                return True
            else:
                print("⚠️ CORS não configurado ou não detectado")
                return False
                
        except Exception as e:
            print(f"❌ Erro ao testar CORS: {e}")
            return False
    
    def run_all_tests(self, dicom_file=None):
        """Executar todos os testes"""
        print(f"🔌 Iniciando testes da API REST")
        print(f"   URL: {self.base_url}")
        print(f"   Usuário: {self.auth.username}")
        print(f"   Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 60)
        
        results = {}
        
        # Teste 1: Conectividade
        results['connection'] = self.test_connection()
        print()
        
        # Teste 2: Autenticação
        results['authentication'] = self.test_authentication()
        print()
        
        # Teste 3: Endpoints
        results['endpoints'] = self.test_endpoints()
        print()
        
        # Teste 4: DICOMweb
        results['dicomweb'] = self.test_dicomweb()
        print()
        
        # Teste 5: Stone Viewer
        results['stone_viewer'] = self.test_stone_viewer()
        print()
        
        # Teste 6: Upload DICOM (se arquivo fornecido)
        if dicom_file:
            results['upload'] = self.test_upload_dicom(dicom_file)
            print()
        
        # Teste 7: Performance
        results['performance'] = self.test_performance()
        print()
        
        # Teste 8: CORS
        results['cors'] = self.test_cors()
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
            print("🎉 Todos os testes passaram! API REST está funcionando perfeitamente.")
        elif passed_tests > 0:
            print("⚠️ Alguns testes falharam. Verifique a configuração.")
        else:
            print("❌ Todos os testes falharam. Verifique conectividade e configuração.")
        
        return passed_tests == total_tests

def main():
    parser = argparse.ArgumentParser(description='Testar API REST do Orthanc')
    parser.add_argument('--url', default='https://pacs.radiweb.com.br',
                       help='URL base do Orthanc')
    parser.add_argument('--username', default='admin',
                       help='Nome de usuário')
    parser.add_argument('--password', default='admin',
                       help='Senha')
    parser.add_argument('--timeout', type=int, default=30,
                       help='Timeout das requisições (segundos)')
    parser.add_argument('--dicom-file',
                       help='Arquivo DICOM para teste de upload')
    parser.add_argument('--test', 
                       choices=['connection', 'auth', 'endpoints', 'dicomweb', 
                               'stone', 'upload', 'performance', 'cors', 'all'],
                       default='all', help='Tipo de teste a executar')
    
    args = parser.parse_args()
    
    # Criar testador
    tester = OrthancAPITester(args.url, args.username, args.password, args.timeout)
    
    # Executar testes
    if args.test == 'all':
        success = tester.run_all_tests(args.dicom_file)
    elif args.test == 'connection':
        success = tester.test_connection()
    elif args.test == 'auth':
        success = tester.test_authentication()
    elif args.test == 'endpoints':
        success = tester.test_endpoints()
    elif args.test == 'dicomweb':
        success = tester.test_dicomweb()
    elif args.test == 'stone':
        success = tester.test_stone_viewer()
    elif args.test == 'upload':
        if not args.dicom_file:
            print("❌ Arquivo DICOM necessário para teste de upload")
            sys.exit(1)
        success = tester.test_upload_dicom(args.dicom_file)
    elif args.test == 'performance':
        success = tester.test_performance()
    elif args.test == 'cors':
        success = tester.test_cors()
    
    # Código de saída
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()

