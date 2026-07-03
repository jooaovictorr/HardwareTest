# Testes especificos de notebook

function Invoke-BatteryTest {
  Write-TestLog 'Teste de bateria (notebook)' -Level Title

  $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
  if (-not $bat) {
    Add-TestResult -Category 'Bateria' -Name 'Deteccao' -Status 'SKIP' -Detail 'Nenhuma bateria detectada'
    return
  }

  $charge = $bat.EstimatedChargeRemaining
  $statusText = switch ($bat.BatteryStatus) {
    1 { 'Descarregando' }
    2 { 'AC - desconhecido' }
    3 { 'Carregada totalmente' }
    4 { 'Baixa' }
    6 { 'Carregando' }
    7 { 'Carregando alta' }
    8 { 'Carregando baixa' }
    9 { 'Critica' }
    default { "Codigo $($bat.BatteryStatus)" }
  }

  $chargeStatus = if ($charge -ge 20) { 'PASS' } elseif ($charge -ge 10) { 'WARN' } else { 'FAIL' }
  Add-TestResult -Category 'Bateria' -Name 'Carga atual' -Status $chargeStatus -Detail "${charge}% | $statusText"

  # Relatorio detalhado de bateria
  $reportDir = Join-Path $env:TEMP 'HardwareTest'
  New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
  $reportPath = Join-Path $reportDir 'battery-report.html'

  $proc = Start-Process -FilePath 'powercfg' -ArgumentList @('/batteryreport', "/output:$reportPath") -Wait -PassThru -NoNewWindow
  if ($proc.ExitCode -eq 0 -and (Test-Path $reportPath)) {
    Add-TestResult -Category 'Bateria' -Name 'Relatorio powercfg' -Status 'INFO' -Detail $reportPath

  # Parse design vs full capacity from report if possible
    $html = Get-Content $reportPath -Raw -ErrorAction SilentlyContinue
    if ($html -match 'DESIGN CAPACITY.*?(\d[\d,]+)\s*mWh') { $design = $Matches[1] }
    if ($html -match 'FULL CHARGE CAPACITY.*?(\d[\d,]+)\s*mWh') { $full = $Matches[1] }
    if ($design -and $full) {
      $designNum = [int]($design -replace ',', '')
      $fullNum   = [int]($full -replace ',', '')
      $healthPct = [math]::Round(($fullNum / $designNum) * 100, 1)
      $hStatus = if ($healthPct -ge 80) { 'PASS' } elseif ($healthPct -ge 60) { 'WARN' } else { 'FAIL' }
      Add-TestResult -Category 'Bateria' -Name 'Saude da bateria' -Status $hStatus `
        -Detail "${healthPct}% da capacidade original (${full} / ${design} mWh)"
    }
  } else {
    Add-TestResult -Category 'Bateria' -Name 'Relatorio powercfg' -Status 'WARN' -Detail 'Nao foi possivel gerar'
  }
}

function Invoke-ThermalTest {
  Write-TestLog 'Temperaturas do sistema' -Level Title

  $found = $false

  # GPU via contadores (se disponivel)
  try {
    $gpuCounters = Get-Counter -ListSet '*gpu*' -ErrorAction SilentlyContinue
    if ($gpuCounters) {
      $found = $true
      Add-TestResult -Category 'Termico' -Name 'Sensores GPU' -Status 'INFO' -Detail 'Contadores GPU disponiveis'
    }
  } catch {}

  # Thermal zones
  try {
    $zones = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace root/wmi -ErrorAction Stop
    foreach ($z in $zones) {
      $tempC = [math]::Round(($z.CurrentTemperature / 10) - 273.15, 1)
      $found = $true
      $st = if ($tempC -lt 80) { 'PASS' } elseif ($tempC -lt 95) { 'WARN' } else { 'FAIL' }
      Add-TestResult -Category 'Termico' -Name 'Zona termica' -Status $st -Detail "${tempC}C"
    }
  } catch {}

  if (-not $found) {
    Add-TestResult -Category 'Termico' -Name 'Sensores' -Status 'WARN' `
      -Detail 'Sensores limitados via WMI - use HWiNFO ou OCCT para leitura completa em notebook'
  }
}

function Invoke-NotebookFullTest {
  param(
    [hashtable]$Config,
    [switch]$SkipKeyboard
  )

  if (-not (Test-IsNotebook)) {
    Write-TestLog 'Maquina detectada como desktop - testes de notebook ignorados' -Level Warn
    return
  }

  Invoke-BatteryTest
  Invoke-ThermalTest
  Invoke-WebcamBluetoothTest
  if (-not $SkipKeyboard) {
    Invoke-KeyboardTest
  }
}

function Invoke-WindowsHealthTest {
  Write-TestLog 'Saude do Windows' -Level Title

  $os = Get-CimInstance Win32_OperatingSystem
  $lastBoot = $os.LastBootUpTime
  $uptime = (Get-Date) - $lastBoot
  Add-TestResult -Category 'Windows' -Name 'Uptime' -Status 'INFO' -Detail "$([math]::Round($uptime.TotalHours, 1)) horas desde $($lastBoot.ToString('dd/MM HH:mm'))"

  try {
    $wu = (New-Object -ComObject Microsoft.Update.AutoUpdate).Results
    Add-TestResult -Category 'Windows' -Name 'Windows Update' -Status 'INFO' -Detail "Ultimo resultado: $($wu)"
  } catch {
    Add-TestResult -Category 'Windows' -Name 'Windows Update' -Status 'SKIP' -Detail 'Nao consultado'
  }

  $activation = (Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue |
    Where-Object LicenseStatus -eq 1 | Select-Object -First 1)
  Add-TestResult -Category 'Windows' -Name 'Ativacao' -Status $(if ($activation) { 'PASS' } else { 'WARN' }) `
    -Detail $(if ($activation) { 'Windows ativado' } else { 'Status desconhecido ou nao ativado' })
}
