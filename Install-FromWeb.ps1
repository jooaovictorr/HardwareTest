#Requires -Version 5.1
<#
.SYNOPSIS
    Baixa o Hardware Test Kit para a Area de Trabalho e executa os testes.

.EXAMPLE
    irm https://raw.githubusercontent.com/jooaovictorr/HardwareTest/main/Install-FromWeb.ps1 | iex
#>

[CmdletBinding()]
param(
    [string]$RepoUrl = 'https://raw.githubusercontent.com/jooaovictorr/HardwareTest/main',
    [string]$InstallDir = '',
    [switch]$InstalarApenas,
    [ValidateSet('Auto', 'GPU', 'Notebook', 'Completo', 'Rapido')]
    [string]$Modo = 'Auto',
    [switch]$SemInstalarApps,
    [switch]$SemStress
)

$ErrorActionPreference = 'Stop'
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force | Out-Null

function Write-Step([string]$Msg) { Write-Host "[>>] $Msg" -ForegroundColor Cyan }
function Write-Ok([string]$Msg)   { Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Err([string]$Msg)  { Write-Host "[XX] $Msg" -ForegroundColor Red }

$InstallScriptUrl = 'https://raw.githubusercontent.com/jooaovictorr/HardwareTest/main/Install-FromWeb.ps1'
$Desktop = [Environment]::GetFolderPath('Desktop')
if (-not $InstallDir) { $InstallDir = Join-Path $Desktop 'HardwareTest' }

# ── 1. Auto-elevar para Administrador ───────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Step 'Solicitando permissao de Administrador...'
    $elevate = "Set-ExecutionPolicy Bypass -Scope Process -Force; irm '$InstallScriptUrl' | iex"
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $elevate
    ) | Out-Null
    exit 0
}

Write-Ok 'Executando como Administrador'

# ── 2. Baixar arquivos do GitHub ──────────────────────────────────────
$files = @(
    'config.psd1', 'Testar-Equipamento.ps1', 'Testar-Equipamento.bat', 'Testar-Teclado.bat',
    'lib/Core.ps1', 'lib/Report.ps1', 'lib/Tests-System.ps1', 'lib/Tests-GPU.ps1',
    'lib/Tests-Hardware.ps1', 'lib/Tests-Notebook.ps1', 'lib/Tests-Keyboard.ps1'
)

Write-Step "Baixando de: $RepoUrl"
Write-Step "Pasta na Area de Trabalho: $InstallDir"

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'lib') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'reports') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir 'Ferramentas') | Out-Null

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

if ($failed.Count -gt 0) { exit 1 }
Write-Ok 'Download concluido!'

# ── 3. Atalhos na Area de Trabalho ────────────────────────────────────
$WshShell = New-Object -ComObject WScript.Shell

$shortcuts = @{
    'Hardware Test Kit.lnk'       = @{ Target = 'Testar-Equipamento.bat'; Desc = 'Suite completa de testes' }
    'Testar GPU.lnk'              = @{ Target = 'Testar-Equipamento.ps1'; Args = '-Modo GPU -GpuStressMinutos 5'; Desc = 'Teste de placa de video 5min' }
    'Testar Teclado.lnk'          = @{ Target = 'Testar-Teclado.bat'; Desc = 'Teste de teclado notebook' }
    'Abrir Ultimo Relatorio.lnk'  = @{ Target = 'Ultimo-Relatorio.html'; Desc = 'Ultimo laudo tecnico'; IsFile = $true }
}

foreach ($name in $shortcuts.Keys) {
    $info = $shortcuts[$name]
    $lnk = $WshShell.CreateShortcut((Join-Path $Desktop $name))
    if ($info.IsFile) {
        $lnk.TargetPath = Join-Path $InstallDir $info.Target
    } elseif ($info.Target -like '*.bat') {
        $lnk.TargetPath = Join-Path $InstallDir $info.Target
    } else {
        $lnk.TargetPath = 'powershell.exe'
        $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $InstallDir $info.Target)`" $($info.Args)"
    }
    $lnk.WorkingDirectory = $InstallDir
    $lnk.Description = $info.Desc
    $lnk.IconLocation = 'powershell.exe,0'
    $lnk.Save()
    Write-Ok "Atalho: $name"
}

# ── 4. Instalar ferramentas (winget) + atalhos em Ferramentas\ ────────
if (-not $SemInstalarApps) {
    Write-Step 'Instalando ferramentas de teste (FurMark, GPU-Z, OCCT, CrystalDiskInfo)...'
    . (Join-Path $InstallDir 'lib\Core.ps1')
    $Config = Import-PowerShellDataFile (Join-Path $InstallDir 'config.psd1')
    $toolsDir = Join-Path $InstallDir 'Ferramentas'

    foreach ($toolName in $Config.Tools.Keys) {
        $tool = $Config.Tools[$toolName]
        $exe = Find-ToolExe -Paths $tool.ExePaths
        if (-not $exe) {
            Write-Step "Instalando $toolName via winget..."
            if (Install-TestTool -WingetId $tool.Id -Name $toolName) {
                $exe = Find-ToolExe -Paths $tool.ExePaths
            }
        }
        if ($exe) {
            $tl = $WshShell.CreateShortcut((Join-Path $toolsDir "$toolName.lnk"))
            $tl.TargetPath = $exe
            $tl.WorkingDirectory = Split-Path $exe -Parent
            $tl.Description = $toolName
            $tl.Save()
            Write-Ok "$toolName -> Ferramentas\$toolName.lnk"
        } else {
            Write-Err "$toolName nao instalado"
        }
    }
}

if ($InstalarApenas) {
    Write-Host "`nInstalado em: $InstallDir" -ForegroundColor Green
    exit 0
}

# ── 5. Executar testes ────────────────────────────────────────────────
Write-Step 'Iniciando Hardware Test Kit...'
$testArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $InstallDir 'Testar-Equipamento.ps1'), '-Modo', $Modo)
if (-not $SemInstalarApps) { $testArgs += '-InstalarApps' }
if ($SemStress) { $testArgs += '-SemStress' }

& powershell.exe @testArgs
