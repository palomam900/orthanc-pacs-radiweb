#!/usr/bin/env python3
"""
Script principal para executar todos os testes do Orthanc PACS Radiweb
Autor: Manus AI
Data: 2024-01-01
"""

import os
import sys
import subprocess
import argparse
from datetime import datetime

def run_command(command, description):
    """Executar comando e capturar resultado"""
    print(f"\n{'='*60}")
    print(f"🔍 {description}")
    print(f"{'='*60}")
    
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True)
        
        # Mostrar output
        if result.stdout:
            print(result.stdout)
        if result.stderr:
            print(result.stderr)
        
        success = result.returncode == 0
        
        if success:
            print(f"✅ {description} - SUCESSO")
        else:
            print(f"❌ {description} - FALHOU (código: {result.returncode})")
        
        return success
        
    except Exception as e:
        print(f"❌ Erro ao executar {description}: {e}")
        return False

def check_dependencies():
    """Verificar dependências necessárias"""
    print("🔍 Verificando dependências...")
    
    dependencies = {
        'python3': 'Python 3',
        'pip3': 'pip3',
        'curl': 'curl',
        'nc': 'netcat'
    }
    
    missing = []
    
    for cmd, name in dependencies.items():
        try:
            subprocess.run([cmd, '--version'], capture_output=True, check=True)
            print(f"   ✅ {name}")
        except (subprocess.CalledProcessError, FileNotFoundError):
            print(f"   ❌ {name} não encontrado")
            missing.append(name)
    
    # Verificar módulos Python
    python_modules = ['requests', 'pydicom', 'pynetdicom']
    
    for module in python_modules:
        try:
            __import__(module)
            print(f"   ✅ {module}")
        except ImportError:
            print(f"   ❌ {module} não encontrado")
            missing.append(f"python3-{module}")
    
    if missing:
        print(f"\n⚠️ Dependências faltando: {', '.join(missing)}")
        print("Instale com:")
        print("   sudo apt update && sudo apt install -y curl netcat")
        print("   pip3 install requests pydicom pynetdicom")
        return False
    else:
        print("✅ Todas as dependências estão disponíveis")
        return True

def create_test_data(output_dir):
    """Criar dados de teste DICOM"""
    print("🏥 Criando dados de teste DICOM...")
    
    script_path = os.path.join(os.path.dirname(__file__), 'create_test_dicom.py')
    
    if not os.path.exists(script_path):
        print(f"❌ Script não encontrado: {script_path}")
        return False
    
    # Criar diferentes tipos de imagens de teste
    test_cases = [
        {
            'patient_name': 'TESTE^RADIWEB^CT',
            'patient_id': 'TEST_CT_001',
            'modality': 'CT',
            'pattern': 'gradient',
            'filename': 'test_ct_gradient.dcm'
        },
        {
            'patient_name': 'TESTE^RADIWEB^MR',
            'patient_id': 'TEST_MR_001',
            'modality': 'MR',
            'pattern': 'circles',
            'filename': 'test_mr_circles.dcm'
        },
        {
            'patient_name': 'TESTE^RADIWEB^US',
            'patient_id': 'TEST_US_001',
            'modality': 'US',
            'pattern': 'noise',
            'filename': 'test_us_noise.dcm'
        }
    ]
    
    created_files = []
    
    for test_case in test_cases:
        cmd = f"python3 {script_path} " \
              f"--patient-name '{test_case['patient_name']}' " \
              f"--patient-id {test_case['patient_id']} " \
              f"--modality {test_case['modality']} " \
              f"--pattern {test_case['pattern']} " \
              f"--output-dir {output_dir}"
        
        if run_command(cmd, f"Criando {test_case['filename']}"):
            expected_file = os.path.join(output_dir, f"test_{test_case['modality'].lower()}_{test_case['patient_id']}.dcm")
            if os.path.exists(expected_file):
                created_files.append(expected_file)
    
    return created_files

def main():
    parser = argparse.ArgumentParser(description='Executar todos os testes do Orthanc PACS')
    parser.add_argument('--host', default='pacs.radiweb.com.br',
                       help='Hostname do servidor')
    parser.add_argument('--dicom-port', type=int, default=4242,
                       help='Porta DICOM')
    parser.add_argument('--http-url', default='https://pacs.radiweb.com.br',
                       help='URL HTTP/HTTPS')
    parser.add_argument('--username', default='admin',
                       help='Nome de usuário')
    parser.add_argument('--password', default='admin',
                       help='Senha')
    parser.add_argument('--ae-title', default='RADIWEB_PACS',
                       help='AE Title do servidor')
    parser.add_argument('--skip-deps', action='store_true',
                       help='Pular verificação de dependências')
    parser.add_argument('--skip-create', action='store_true',
                       help='Pular criação de dados de teste')
    parser.add_argument('--test-dir', default='./test_data',
                       help='Diretório para dados de teste')
    
    args = parser.parse_args()
    
    # Banner
    print("🏥 Orthanc PACS Radiweb - Suite de Testes Completa")
    print("=" * 60)
    print(f"Servidor: {args.host}:{args.dicom_port}")
    print(f"URL: {args.http_url}")
    print(f"Usuário: {args.username}")
    print(f"AE Title: {args.ae_title}")
    print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)
    
    # Verificar dependências
    if not args.skip_deps:
        if not check_dependencies():
            print("\n❌ Dependências faltando. Use --skip-deps para pular esta verificação.")
            sys.exit(1)
    
    # Criar diretório de teste
    os.makedirs(args.test_dir, exist_ok=True)
    
    # Criar dados de teste
    test_files = []
    if not args.skip_create:
        test_files = create_test_data(args.test_dir)
        if not test_files:
            print("⚠️ Nenhum arquivo de teste criado. Continuando sem dados de teste.")
    
    # Lista de testes a executar
    tests = []
    
    # 1. Teste de conectividade básica
    tests.append({
        'command': f"./test-connectivity.sh -d {args.host}",
        'description': 'Teste de Conectividade Básica'
    })
    
    # 2. Teste DICOM
    dicom_cmd = f"python3 tests/test_dicom_connectivity.py " \
                f"--host {args.host} " \
                f"--port {args.dicom_port} " \
                f"--ae-title {args.ae_title}"
    
    if test_files:
        dicom_cmd += f" --dicom-file {test_files[0]}"
    
    tests.append({
        'command': dicom_cmd,
        'description': 'Teste de Conectividade DICOM'
    })
    
    # 3. Teste API REST
    api_cmd = f"python3 tests/test_api.py " \
              f"--url {args.http_url} " \
              f"--username {args.username} " \
              f"--password {args.password}"
    
    if test_files:
        api_cmd += f" --dicom-file {test_files[0]}"
    
    tests.append({
        'command': api_cmd,
        'description': 'Teste da API REST'
    })
    
    # 4. Teste de upload de múltiplos arquivos
    if len(test_files) > 1:
        for i, test_file in enumerate(test_files[1:], 2):
            upload_cmd = f"curl -X POST -u {args.username}:{args.password} " \
                        f"-H 'Content-Type: application/dicom' " \
                        f"--data-binary @{test_file} " \
                        f"{args.http_url}/instances"
            
            tests.append({
                'command': upload_cmd,
                'description': f'Upload DICOM {i} via REST'
            })
    
    # Executar todos os testes
    results = []
    
    for test in tests:
        success = run_command(test['command'], test['description'])
        results.append({
            'name': test['description'],
            'success': success
        })
    
    # Resumo final
    print(f"\n{'='*60}")
    print("📊 RESUMO FINAL DOS TESTES")
    print(f"{'='*60}")
    
    total_tests = len(results)
    passed_tests = sum(1 for result in results if result['success'])
    
    for result in results:
        status = "✅ PASSOU" if result['success'] else "❌ FALHOU"
        print(f"   {result['name']}: {status}")
    
    print(f"\n🎯 Resultado Geral: {passed_tests}/{total_tests} testes passaram")
    
    if passed_tests == total_tests:
        print("🎉 TODOS OS TESTES PASSARAM!")
        print("   Seu Orthanc PACS está funcionando perfeitamente!")
        print(f"\n🌐 Acesse o sistema:")
        print(f"   Interface: {args.http_url}")
        print(f"   Stone Viewer: {args.http_url}/stone-webviewer/")
        print(f"\n🏥 Configuração DICOM:")
        print(f"   AE Title: {args.ae_title}")
        print(f"   Host: {args.host}")
        print(f"   Porta: {args.dicom_port}")
        
        exit_code = 0
        
    elif passed_tests > 0:
        print("⚠️ ALGUNS TESTES FALHARAM")
        print("   Verifique a configuração e tente novamente.")
        exit_code = 1
        
    else:
        print("❌ TODOS OS TESTES FALHARAM")
        print("   Verifique se o servidor está rodando e acessível.")
        exit_code = 2
    
    # Limpeza
    if test_files and not args.skip_create:
        print(f"\n🧹 Limpando arquivos de teste...")
        for test_file in test_files:
            try:
                os.remove(test_file)
                print(f"   Removido: {test_file}")
            except:
                pass
    
    print(f"\n✅ Testes concluídos em {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    sys.exit(exit_code)

if __name__ == "__main__":
    main()

