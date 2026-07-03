# Testes de GPU (placa dedicada no PC de testes)

function Invoke-GpuInfoTest {
  Write-TestLog 'Diagnostico GPU' -Level Title

  $gpus = @(Get-CimInstance Win32_VideoController | Where-Object {
      $_.Name -notmatch 'Microsoft Basic|Remote|Virtual|Parsec'
    })

  $primary = $gpus | Where-Object { $_.Status -eq 'OK' -and $_.AdapterRAM -gt 0 } | Sort-Object AdapterRAM -Descending | Select-Object -First 1
  if (-not $primary) {
    Add-TestResult -Category 'GPU' -Name 'Deteccao' -Status 'FAIL' -Detail 'Nenhuma GPU dedicada detectada'
    return $null
  }

  $signed = (Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
    Where-Object { $_.DeviceName -eq $primary.Name } | Select-Object -First 1).IsSigned

  Add-TestResult -Category 'GPU' -Name 'Modelo' -Status 'INFO' -Detail $primary.Name
  Add-TestResult -Category 'GPU' -Name 'Driver' -Status 'INFO' -Detail "$($primary.DriverVersion) ($($primary.DriverDate))"
  Add-TestResult -Category 'GPU' -Name 'Status PnP' -Status $(if ($primary.Status -eq 'OK') { 'PASS' } else { 'FAIL' }) -Detail $primary.Status
  Add-TestResult -Category 'GPU' -Name 'Driver assinado' -Status $(if ($signed) { 'PASS' } else { 'FAIL' }) -Detail $(if ($signed) { 'Sim' } else { 'Nao' })
  Add-TestResult -Category 'GPU' -Name 'Resolucao atual' -Status 'INFO' `
    -Detail "$($primary.CurrentHorizontalResolution)x$($primary.CurrentVerticalResolution) @ $($primary.CurrentRefreshRate)Hz"

  # TDR check
  $tdr = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 4101 } -MaxEvents 5 -ErrorAction SilentlyContinue)
  Add-TestResult -Category 'GPU' -Name 'Crash driver (TDR)' -Status $(if ($tdr.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
    -Detail $(if ($tdr.Count -eq 0) { 'Nenhum reset de driver registrado' } else { "$($tdr.Count) evento(s) TDR" })

  return $primary
}

function Invoke-GpuFurMarkTest {
  param(
    [hashtable]$Config,
    [int]$Seconds = 300,
    [switch]$Quick
  )

  $furmark = $Config.FurMarkPath
  if (-not (Test-Path -LiteralPath $furmark)) {
    $furmark = Find-ToolExe -Paths $Config.Tools.FurMark.ExePaths
  }
  if (-not $furmark) {
    Add-TestResult -Category 'GPU' -Name 'FurMark stress' -Status 'SKIP' -Detail 'FurMark nao instalado'
    return
  }

  if ($Quick) { $Seconds = 30 }
  Write-TestLog "FurMark stress test ($Seconds seg) - janela $($Config.GpuTestWidth)x$($Config.GpuTestHeight)" -Level Title
  Write-TestLog 'Aguarde... o teste abre em janela (nao tela cheia)' -Level Info

  $args = @(
    '--hpgfx', '1',
    '--gpu-index', '0',
    '--demo', 'furmark-vk',
    '--benchmark',
    '--width', $Config.GpuTestWidth,
    '--height', $Config.GpuTestHeight,
    '--max-time', $Seconds,
    '--artifact-scanner',
    '--no-score-box',
    '--title-bar', '1'
  )

  $fmDir = Split-Path -Parent $furmark
  $scoresFile = Join-Path $fmDir '_scores.csv'
  $linesBefore = 0
  if (Test-Path -LiteralPath $scoresFile) {
    $linesBefore = @(Get-Content -LiteralPath $scoresFile -ErrorAction SilentlyContinue).Count
  }

  $outFile = Join-Path $env:TEMP "furmark_out_$([guid]::NewGuid().ToString('N').Substring(0,8)).txt"
  $argLine = ($args | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
  $cmd = "`"$furmark`" $argLine > `"$outFile`" 2>&1"
  $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $cmd -Wait -PassThru -NoNewWindow -WorkingDirectory $fmDir

  $output = ''
  if (Test-Path -LiteralPath $outFile) { $output = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue }

  # Resultado via _scores.csv (mais confiavel que stdout)
  $score = $null; $maxTemp = $null; $avgFps = $null; $minFps = $null; $renderer = '?'
  if (Test-Path -LiteralPath $scoresFile) {
    $lines = @(Get-Content -LiteralPath $scoresFile -ErrorAction SilentlyContinue)
    if ($lines.Count -gt $linesBefore -and $lines.Count -gt 1) {
      $cols = $lines[-1] -split ','
      if ($cols.Count -ge 15) {
        $renderer = $cols[4]
        $maxTemp  = [int]$cols[10]
        $score    = [int]$cols[11]
        $avgFps   = [double]$cols[12]
        $minFps   = [double]$cols[13]
      }
    }
  }

  if (-not $score -and $output) {
    $score    = if ($output -match 'SCORE\s*:\s*(\d+)') { [int]$Matches[1] } else { $null }
    $maxTemp  = if ($output -match 'max temperature:\s*(\d+)') { [int]$Matches[1] } else { $null }
    $avgFps   = if ($output -match 'FPS.*?\)\s*:\s*[\d.]+\s*/\s*([\d.]+)') { [double]$Matches[1] } else { $null }
    $maxUsage = if ($output -match 'max usage:\s*(\d+)') { [int]$Matches[1] } else { $null }
    if ($output -match 'renderer\s*:\s*(.+)') { $renderer = $Matches[1].Trim() }
  } else {
    $maxUsage = $null
  }

  $data = [ordered]@{
    ExitCode = $proc.ExitCode
    Score    = $score
    MaxTempC = $maxTemp
    AvgFps   = $avgFps
    MinFps   = $minFps
    MaxUsage = $maxUsage
    Renderer = $renderer
    Seconds  = $Seconds
  }

  $status = 'PASS'
  $detail = "GPU: $renderer"
  if (-not $score -and $proc.ExitCode -ne 0) { $status = 'FAIL'; $detail += ' | FurMark nao retornou resultado' }
  elseif (-not $score) { $status = 'WARN'; $detail += ' | Sem score (verifique se o teste abriu)' }
  if ($maxTemp -and $maxTemp -gt 90) { $status = 'WARN'; $detail += " | Temp alta: ${maxTemp}C" }
  if ($score) { $detail += " | Score: $score" }
  if ($avgFps) { $detail += " | FPS medio: $avgFps" }
  if ($maxTemp) { $detail += " | Temp max: ${maxTemp}C" }

  Add-TestResult -Category 'GPU' -Name "FurMark ${Seconds}s" -Status $status -Detail $detail -Data $data
  Remove-Item $outFile -Force -ErrorAction SilentlyContinue
}

function Invoke-GpuVramTest {
  param([hashtable]$Config)

  $furmark = $Config.FurMarkPath
  if (-not (Test-Path -LiteralPath $furmark)) { return }

  Write-TestLog 'Teste de VRAM (OpenGL 8GB) - 60 segundos' -Level Title
  $args = @(
    '--hpgfx', '1', '--gpu-index', '0',
    '--demo', 'furmark-gl',
    '--benchmark',
    '--width', $Config.GpuTestWidth,
    '--height', $Config.GpuTestHeight,
    '--max-time', '60',
    '--furmark-vram-test-gb', '8',
    '--artifact-scanner',
    '--no-score-box', '--title-bar', '1'
  )

  $outFile = Join-Path $env:TEMP "furmark_vram_out.txt"
  $proc = Start-Process -FilePath $furmark -ArgumentList $args -PassThru -NoNewWindow -Wait -RedirectStandardOutput $outFile -RedirectStandardError $outFile
  $output = Get-Content $outFile -Raw -ErrorAction SilentlyContinue
  $maxTemp = if ($output -match 'max temperature:\s*(\d+)') { [int]$Matches[1] } else { $null }

  Add-TestResult -Category 'GPU' -Name 'VRAM 8GB stress' -Status $(if ($proc.ExitCode -eq 0) { 'PASS' } else { 'FAIL' }) `
    -Detail $(if ($maxTemp) { "Temp max ${maxTemp}C - teste de memoria de video" } else { 'Concluido' })
}

function Invoke-GpuFullTest {
  param(
    [hashtable]$Config,
    [int]$StressSeconds = 300,
    [switch]$IncludeVram,
    [switch]$Quick
  )
  Invoke-GpuInfoTest | Out-Null
  Invoke-GpuFurMarkTest -Config $Config -Seconds $StressSeconds -Quick:$Quick
  if ($IncludeVram -and -not $Quick) {
    Invoke-GpuVramTest -Config $Config
  }
}
