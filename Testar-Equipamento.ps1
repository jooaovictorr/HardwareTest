#Requires -Version 5.1
<#
.SYNOPSIS
    Kit completo de testes de hardware para compra de notebooks e placas de video usadas.

.DESCRIPTION
    Modos:
      GPU      - Testa placa de video no PC de testes (FurMark, diagnostico, VRAM)
      Notebook - Testes completos de notebook (bateria, disco, rede, termico, etc.)
      Completo - Todos os testes aplicaveis
      Rapido   - Inventario + testes basicos sem stress longo
      Auto     - Detecta o tipo de maquina e escolhe o modo

.EXAMPLE
    .\Testar-Equipamento.ps1
    .\Testar-Equipamento.ps1 -Modo GPU -GpuStressMinutos 5
    .\Testar-Equipamento.ps1 -Modo Notebook -InstalarApps
    .\Testar-Equipamento.ps1 -Modo Completo -InstalarApps -SemStress
#>

[CmdletBinding()]
param(
    [ValidateSet('Auto', 'GPU', 'Notebook', 'Completo', 'Rapido')]
    [string]$Modo = 'Auto',

    [switch]$InstalarApps,
    [switch]$SemStress,
    [switch]$IncluirVram,
    [switch]$SkipKeyboard,
    [int]$GpuStressMinutos = 5,
    [switch]$AbrirRelatorio
)

$ErrorActionPreference = 'Continue'
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptRoot 'config.psd1'

if (-not (Test-Path $ConfigPath)) {
    Write-Host '[XX] config.psd1 nao encontrado em $ScriptRoot' -ForegroundColor Red
    exit 1
}

$Config = Import-PowerShellDataFile $ConfigPath
$ReportsDir = Join-Path $ScriptRoot $Config.ReportsSubDir

# Carregar modulos
. (Join-Path $ScriptRoot 'lib\Core.ps1')
. (Join-Path $ScriptRoot 'lib\Tests-System.ps1')
. (Join-Path $ScriptRoot 'lib\Tests-GPU.ps1')
. (Join-Path $ScriptRoot 'lib\Tests-Hardware.ps1')
. (Join-Path $ScriptRoot 'lib\Tests-Notebook.ps1')
. (Join-Path $ScriptRoot 'lib\Tests-Keyboard.ps1')
. (Join-Path $ScriptRoot 'lib/Report.ps1')

Clear-Host
Write-Host ''
Write-Host '  ======================================================' -ForegroundColor Cyan
Write-Host '     HARDWARE TEST KIT - Compra de Usados' -ForegroundColor Cyan
Write-Host '     Notebooks + Placas de Video' -ForegroundColor Cyan
Write-Host '  ======================================================' -ForegroundColor Cyan
Write-Host ''

# Menu interativo se executado sem parametros explicitos de linha de comando
$explicitMode = $PSBoundParameters.ContainsKey('Modo')
if (-not $explicitMode) {
    Write-Host "  Selecione o modo de teste:`n"
    Write-Host "  [1] GPU       - Placa de video no PC de testes (FurMark $GpuStressMinutos min)"
    Write-Host "  [2] Notebook  - Notebook completo (bateria, disco, rede, termico...)"
    Write-Host "  [3] Completo  - Todos os testes"
    Write-Host "  [4] Rapido    - Inventario + diagnostico basico (sem stress longo)"
    Write-Host "  [5] Auto      - Detectar automaticamente`n"
    $choice = Read-Host '  Opcao (1-5, Enter=Auto)'
    $Modo = switch ($choice) {
        '1' { 'GPU' }
        '2' { 'Notebook' }
        '3' { 'Completo' }
        '4' { 'Rapido' }
        default { 'Auto' }
    }

    $inst = Read-Host '  Instalar apps faltantes via winget? (S/n)'
    if ($inst -notmatch '^[Nn]') { $InstalarApps = $true }

    if ($Modo -in 'GPU', 'Completo') {
        $mins = Read-Host "  Minutos de stress GPU (Enter=$GpuStressMinutos)"
        if ($mins -match '^\d+$') { $GpuStressMinutos = [int]$mins }
    }
}

# Auto-detectar
if ($Modo -eq 'Auto') {
    $Modo = if (Test-IsNotebook) { 'Notebook' } else { 'GPU' }
    Write-TestLog "Modo automatico: $Modo" -Level Step
}

$gpuSeconds = $GpuStressMinutos * 60
$isNotebook = Test-IsNotebook
$isGpuMode  = $Modo -in 'GPU', 'Completo'

Write-TestLog "Modo: $Modo | Maquina: $(if ($isNotebook) { 'Notebook' } else { 'Desktop' })" -Level Title

# Instalar ferramentas
if ($InstalarApps) {
    $toolModes = @($Modo)
    if ($Modo -eq 'Completo') { $toolModes = @('GPU', 'Notebook') }
    Ensure-TestTools -Config $Config -Mode $toolModes | Out-Null
} elseif ($isGpuMode) {
    $fm = Test-Path -LiteralPath $Config.FurMarkPath
    if (-not $fm) {
        Write-TestLog 'FurMark nao encontrado. Use -InstalarApps ou instale: winget install Geeks3D.FurMark.2' -Level Warn
    }
}

# ─── EXECUCAO DOS TESTES ───────────────────────────────────────────

Invoke-InventoryTest
Invoke-DeviceHealthTest
Invoke-EventLogTest
Invoke-ReliabilityTest
Invoke-DisplayTest
Invoke-AudioUsbTest
Invoke-NetworkTest
Invoke-WindowsHealthTest

if ($Modo -in 'Notebook', 'Completo') {
    Invoke-NotebookFullTest -Config $Config -SkipKeyboard:$SkipKeyboard
}

Invoke-CpuTest
Invoke-RamTest
Invoke-DiskTest -TestSizeMB $Config.DiskTestSizeMB

if ($isGpuMode) {
    if ($SemStress -or $Modo -eq 'Rapido') {
        Invoke-GpuInfoTest | Out-Null
        if (-not $SemStress -and $Modo -eq 'Rapido') {
            Invoke-GpuFurMarkTest -Config $Config -Quick
        }
    } else {
        Invoke-GpuFullTest -Config $Config -StressSeconds $gpuSeconds -IncludeVram:$IncluirVram
    }
} elseif ($Modo -eq 'Notebook') {
    # Notebook: testar GPU integrada/dedicada se existir
    $gpu = Get-CimInstance Win32_VideoController | Where-Object {
        $_.Status -eq 'OK' -and $_.Name -notmatch 'Microsoft Basic'
    } | Select-Object -First 1
    if ($gpu) {
        Invoke-GpuInfoTest | Out-Null
        if (-not $SemStress) {
            Write-TestLog 'Stress GPU em notebook: teste rapido 60s (use PC de testes para stress completo)' -Level Warn
            Invoke-GpuFurMarkTest -Config $Config -Seconds 60
        }
    }
}

# ─── RELATORIO ─────────────────────────────────────────────────────

Write-TestLog 'Gerando relatorio' -Level Title
$result = Export-TestReport -OutputDir $ReportsDir -KitRoot $ScriptRoot -Mode $Modo

Write-Host ''
Write-Host '  ==========================================' -ForegroundColor White
Write-Host ("  RESULTADO: {0}" -f $result.Verdict) -ForegroundColor $(switch ($result.Verdict) {
    'APROVADO' { 'Green' }; 'ATENCAO' { 'Yellow' }; default { 'Red' }
})
Write-Host '  ------------------------------------------' -ForegroundColor White
Write-Host ("  Passou:   {0}" -f $Script:Report.Summary.Passed) -ForegroundColor Green
Write-Host ("  Falhou:   {0}" -f $Script:Report.Summary.Failed) -ForegroundColor Red
Write-Host ("  Alertas:  {0}" -f $Script:Report.Summary.Warn) -ForegroundColor Yellow
Write-Host '  ==========================================' -ForegroundColor White
Write-Host ''
Write-Host ("  Relatorio completo: {0}" -f $result.Html) -ForegroundColor Cyan
Write-Host ("  Ultimo laudo (pasta): {0}" -f $result.Latest) -ForegroundColor Cyan
Write-Host ''

if ($AbrirRelatorio -or (-not $explicitMode)) {
    $open = Read-Host '  Abrir ultimo laudo no navegador? (S/n)'
    if ($open -notmatch '^[Nn]') {
        Start-Process $result.Latest
    }
}
