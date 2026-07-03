# Testes de CPU, RAM e disco

function Invoke-CpuTest {
  Write-TestLog 'Teste de CPU' -Level Title

  $cpu = Get-CimInstance Win32_Processor
  Add-TestResult -Category 'CPU' -Name 'Modelo' -Status 'INFO' -Detail $cpu.Name

  # Stress CPU por ~30s medindo tempo de calculo
  Write-TestLog 'Stress CPU (calculo intensivo 30s)...' -Level Step
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $end = (Get-Date).AddSeconds(30)
  $iterations = 0
  while ((Get-Date) -lt $end) {
    $null = 1..50000 | ForEach-Object { [math]::Sqrt($_ * [math]::PI) }
    $iterations++
  }
  $sw.Stop()

  $status = if ($iterations -gt 50) { 'PASS' } elseif ($iterations -gt 20) { 'WARN' } else { 'FAIL' }
  Add-TestResult -Category 'CPU' -Name 'Stress calculo 30s' -Status $status `
    -Detail "$iterations ciclos em $($sw.Elapsed.TotalSeconds.ToString('F1'))s" -Data @{ Iterations = $iterations; Seconds = $sw.Elapsed.TotalSeconds }

  # Contadores de performance
  try {
    $samples = @()
    1..5 | ForEach-Object {
      Start-Sleep -Seconds 2
      $c = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue
      if ($c) { $samples += $c.CounterSamples[0].CookedValue }
    }
    if ($samples.Count -gt 0) {
      $avg = [math]::Round(($samples | Measure-Object -Average).Average, 1)
      Add-TestResult -Category 'CPU' -Name 'Uso medio pos-stress' -Status 'INFO' -Detail "${avg}%"
    }
  } catch {}
}

function Invoke-RamTest {
  Write-TestLog 'Teste de RAM' -Level Title

  $os = Get-CimInstance Win32_OperatingSystem
  $total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
  $free  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
  $used  = $total - $free

  Add-TestResult -Category 'RAM' -Name 'Capacidade' -Status 'INFO' -Detail "${total} GB total | ${used} GB em uso | ${free} GB livre"

  # Teste rapido de alocacao
  Write-TestLog 'Teste de alocacao de memoria...' -Level Step
  try {
    $blockSize = 50MB
    $blocks = [System.Collections.Generic.List[byte[]]]::new()
    $allocated = 0
    $maxAlloc = [math]::Min(2GB, [long]($free * 0.4 * 1GB))
    while ($allocated -lt $maxAlloc) {
      $blocks.Add([byte[]]::new($blockSize))
      $allocated += $blockSize
    }
    $blocks.Clear()
    $blocks = $null
    [GC]::Collect()
    Add-TestResult -Category 'RAM' -Name 'Alocacao dinamica' -Status 'PASS' `
      -Detail "Alocou $([math]::Round($allocated/1MB)) MB sem erro"
  } catch {
    Add-TestResult -Category 'RAM' -Name 'Alocacao dinamica' -Status 'FAIL' -Detail $_.Exception.Message
  }

  # Memtest recomendacao
  Add-TestResult -Category 'RAM' -Name 'Memtest86' -Status 'INFO' `
    -Detail 'Para teste profundo de RAM, rode o Windows Memory Diagnostic (mdsched.exe) e reinicie'
}

function Invoke-DiskTest {
  param([int]$TestSizeMB = 512)

  Write-TestLog 'Teste de disco' -Level Title

  # SMART via Storage module
  try {
    $physical = @(Get-PhysicalDisk -ErrorAction Stop)
    foreach ($pd in $physical) {
      $health = $pd.HealthStatus
      $status = switch ($health) {
        'Healthy' { 'PASS' }
        'Warning' { 'WARN' }
        default   { 'FAIL' }
      }
      Add-TestResult -Category 'Disco' -Name "SMART $($pd.FriendlyName)" -Status $status `
        -Detail "$($pd.MediaType) | $($pd.Size/1GB) GB | Saude: $health | Bus: $($pd.BusType)"
    }

    Get-StorageReliabilityCounter -PhysicalDisk $physical -ErrorAction SilentlyContinue | ForEach-Object {
      if ($_.Temperature -gt 0) {
        Add-TestResult -Category 'Disco' -Name 'Temperatura' -Status $(if ($_.Temperature -lt 55) { 'PASS' } elseif ($_.Temperature -lt 70) { 'WARN' } else { 'FAIL' }) `
          -Detail "$($_.Temperature)C"
      }
      if ($_.Wear -gt 0) {
        Add-TestResult -Category 'Disco' -Name 'Desgaste SSD' -Status $(if ($_.Wear -lt 80) { 'PASS' } elseif ($_.Wear -lt 95) { 'WARN' } else { 'FAIL' }) `
          -Detail "$($_.Wear)%"
      }
    }
  } catch {
    Add-TestResult -Category 'Disco' -Name 'SMART WMI' -Status 'SKIP' -Detail 'Contadores de desgaste indisponiveis neste disco'
  }

  # Benchmark leitura/escrita
  $testDir = $env:TEMP
  $testFile = Join-Path $testDir "htest_$([guid]::NewGuid().ToString('N')).tmp"
  Write-TestLog "Benchmark $TestSizeMB MB em $testDir..." -Level Step

  try {
    $bytes = [byte[]]::new(1MB)
    (New-Object Random).NextBytes($bytes)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $fs = [System.IO.File]::Open($testFile, [System.IO.FileMode]::CreateNew)
    for ($i = 0; $i -lt $TestSizeMB; $i++) { $fs.Write($bytes, 0, $bytes.Length) }
    $fs.Flush(); $fs.Close()
    $sw.Stop()
    $writeMbps = [math]::Round(($TestSizeMB * 8) / $sw.Elapsed.TotalSeconds, 1)

    $sw.Restart()
    $null = [System.IO.File]::ReadAllBytes($testFile)
    $sw.Stop()
    $readMbps = [math]::Round(($TestSizeMB * 8) / $sw.Elapsed.TotalSeconds, 1)

    Remove-Item $testFile -Force

    $wStatus = if ($writeMbps -gt 100) { 'PASS' } elseif ($writeMbps -gt 30) { 'WARN' } else { 'FAIL' }
    $rStatus = if ($readMbps -gt 200) { 'PASS' } elseif ($readMbps -gt 50) { 'WARN' } else { 'FAIL' }

    Add-TestResult -Category 'Disco' -Name 'Velocidade escrita' -Status $wStatus -Detail "${writeMbps} Mbps (${TestSizeMB}MB)"
    Add-TestResult -Category 'Disco' -Name 'Velocidade leitura' -Status $rStatus -Detail "${readMbps} Mbps (${TestSizeMB}MB)"
  } catch {
    Add-TestResult -Category 'Disco' -Name 'Benchmark' -Status 'FAIL' -Detail $_.Exception.Message
    Remove-Item $testFile -Force -ErrorAction SilentlyContinue
  }
}
