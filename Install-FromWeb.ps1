#Requires -Version 5.1
<#
.SYNOPSIS
    Baixa o Hardware Test Kit da internet e executa com permissoes elevadas.

.PARAMETER RepoUrl
    URL base do repositorio (GitHub raw ou seu servidor).
    Exemplo: https://raw.githubusercontent.com/SEU_USUARIO/HardwareTest/main

.PARAMETER InstalarApenas
    So baixa os arquivos, nao executa o teste.

.EXAMPLE
    # Depois de hospedar no GitHub, rode como Administrador:
    irm https://raw.githubusercontent.com/SEU_USUARIO/HardwareTest/main/Install-FromWeb.ps1 | iex

.EXAMPLE
    .\Install-FromWeb.ps1 -RepoUrl "https://raw.githubusercontent.com/SEU_USUARIO/HardwareTest/main"
#>

[CmdletBinding()]
param(
    [string]$RepoUrl = 'https://raw.githubusercontent.com/jooaovictorr/HardwareTest/main',
    [string]$InstallDir = "$env:USERPROFILE\HardwareTest",
    [switch]$InstalarApenas,
    [ValidateSet('Auto', 'GPU', 'Notebook', 'Completo', 'Rapido')]
    [string]$Modo = 'Auto',
    [switch]$InstalarApps
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Msg) { Write-Host "[>>] $Msg" -ForegroundColor Cyan }
function Write-Ok([string]$Msg)   { Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Err([string]$Msg)  { Write-Host "[XX] $Msg" -ForegroundColor Red }

# ── 1. Verificar Administrador ──────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Err 'Este script precisa rodar como ADMINISTRADOR.'
    Write-Host ''
    Write-Host 'Opcoes:' -ForegroundColor Yellow
    Write-Host '  1. Clique direito no PowerShell > Executar como administrador'
    Write-Host '  2. Cole o comando abaixo num PowerShell ADMIN:'
    Write-Host ''
    $self = $MyInvocation.MyCommand.Path
    if ($self) {
        Write-Host "  Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File `"$self`"'" -ForegroundColor White
    } else {
        Write-Host '  irm URL_DO_INSTALL.ps1 | iex' -ForegroundColor White
    }
    exit 1
}

Write-Ok 'Executando como Administrador'

# ── 2. Politica de execucao (sessao atual) ───────────────────────────
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null
Write-Ok 'ExecutionPolicy Bypass ativo nesta sessao'

# ── 3. Lista de arquivos para baixar ────────────────────────────────
$files = @(
    'config.psd1'
    'Testar-Equipamento.ps1'
    'Testar-Equipamento.bat'
    'Testar-Teclado.bat'
    'lib\Core.ps1'
    'lib\Tests-System.ps1'
    'lib\Tests-GPU.ps1'
    'lib\Tests-Hardware.ps1'
    'lib\Tests-Notebook.ps1'
    'lib\Tests-Keyboard.ps1'
    'lib/Report.ps1'
)

Write-Step "Baixando de: $RepoUrl"
Write-Step "Instalando em: $InstallDir"

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'lib') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'reports') | Out-Null

$failed = @()
foreach ($file in $files) {
    $url  = "$RepoUrl/$file"
    $dest = Join-Path $InstallDir ($file -replace '/', '\')
    $parent = Split-Path $dest -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }

    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        Write-Ok $file
    } catch {
        Write-Err "Falha: $file - $($_.Exception.Message)"
        $failed += $file
    }
}

if ($failed.Count -gt 0) {
    Write-Err "$($failed.Count) arquivo(s) falharam. Verifique a URL do repositorio."
    Write-Host ''
    Write-Host 'A URL padrao ainda aponta para SEU_USUARIO - edite apos criar o repo no GitHub.' -ForegroundColor Yellow
    exit 1
}

Write-Ok 'Download concluido!'

# Atalho na area de trabalho
$desktop = [Environment]::GetFolderPath('Desktop')
$WshShell = New-Object -ComObject WScript.Shell
$lnk = $WshShell.CreateShortcut("$desktop\Hardware Test Kit.lnk")
$lnk.TargetPath = Join-Path $InstallDir 'Testar-Equipamento.bat'
$lnk.WorkingDirectory = $InstallDir
$lnk.Save()
Write-Ok "Atalho criado na area de trabalho"

if ($InstalarApenas) {
    Write-Host "`nInstalado em: $InstallDir" -ForegroundColor Green
    exit 0
}

# ── 4. Executar testes ──────────────────────────────────────────────
Write-Step 'Iniciando Hardware Test Kit...'
$args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $InstallDir 'Testar-Equipamento.ps1'), '-Modo', $Modo)
if ($InstalarApps) { $args += '-InstalarApps' }

& powershell.exe @args
