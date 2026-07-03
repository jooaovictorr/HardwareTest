# Testes de inventario e saude do sistema

function Invoke-InventoryTest {
  Write-TestLog 'Inventario de hardware' -Level Title

  $os  = Get-CimInstance Win32_OperatingSystem
  $cs  = Get-CimInstance Win32_ComputerSystem
  $bios = Get-CimInstance Win32_BIOS
  $cpu = Get-CimInstance Win32_Processor
  $gpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Microsoft|Remote|Virtual|Parsec|Moonlight' })
  $disks = @(Get-CimInstance Win32_DiskDrive)
  $logical = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3")
  $ram = @(Get-CimInstance Win32_PhysicalMemory)

  $inv = [ordered]@{
    ComputerName = $env:COMPUTERNAME
    IsNotebook   = Test-IsNotebook
    Manufacturer = $cs.Manufacturer
    Model        = $cs.Model
    SystemType   = $cs.SystemType
    OS           = "$($os.Caption) $($os.Version) build $($os.BuildNumber)"
    BIOS         = "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion) ($($bios.ReleaseDate))"
    CPU          = ($cpu | ForEach-Object { "$($_.Name) | $($_.NumberOfCores)c/$($_.NumberOfLogicalProcessors)t @ $([math]::Round($_.MaxClockSpeed))MHz" }) -join '; '
    GPU          = ($gpus | ForEach-Object { "$($_.Name) | Driver $($_.DriverVersion) | $($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)" }) -join '; '
    RAM_GB       = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    RAM_Sticks   = ($ram | ForEach-Object { "$([math]::Round($_.Capacity/1GB))GB @ $($_.Speed)MHz $($_.Manufacturer)" }) -join '; '
    Disks        = ($disks | ForEach-Object { "$($_.Model) $([math]::Round($_.Size/1GB))GB $($_.InterfaceType)" }) -join '; '
    Volumes      = ($logical | ForEach-Object { "$($_.DeviceID) $([math]::Round($_.Size/1GB))GB livre $([math]::Round($_.FreeSpace/1GB))GB" }) -join '; '
  }

  $Script:Report.Inventory = $inv
  $Script:Report.Meta['MachineType'] = if ($inv.IsNotebook) { 'Notebook' } else { 'Desktop' }
  $Script:Report.Meta['StartedAt']  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

  Add-TestResult -Category 'Inventario' -Name 'Sistema' -Status 'INFO' -Detail "$($inv.Manufacturer) $($inv.Model)"
  Add-TestResult -Category 'Inventario' -Name 'CPU' -Status 'INFO' -Detail $inv.CPU
  Add-TestResult -Category 'Inventario' -Name 'GPU' -Status 'INFO' -Detail $inv.GPU
  Add-TestResult -Category 'Inventario' -Name 'RAM' -Status 'INFO' -Detail "$($inv.RAM_GB) GB total"
  Add-TestResult -Category 'Inventario' -Name 'Discos' -Status 'INFO' -Detail $inv.Disks
}

function Invoke-DeviceHealthTest {
  Write-TestLog 'Dispositivos com problema' -Level Title

  $bad = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
      $_.Status -ne 'OK' -and $_.Class -notin @('SoftwareDevice', 'Volume', 'WPD')
    })

  if ($bad.Count -eq 0) {
    Add-TestResult -Category 'Saude' -Name 'PnP Devices' -Status 'PASS' -Detail 'Nenhum dispositivo com erro'
  } else {
    $names = ($bad | Select-Object -First 10 | ForEach-Object { "$($_.FriendlyName) [$($_.Status)]" }) -join '; '
    Add-TestResult -Category 'Saude' -Name 'PnP Devices' -Status 'WARN' -Detail "$($bad.Count) com problema: $names" -Data $bad
  }

  # GPUs fantasma
  $phantom = @(Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Unknown' })
  if ($phantom.Count -gt 0) {
    Add-TestResult -Category 'Saude' -Name 'GPU fantasma' -Status 'WARN' -Detail 'Placa antiga ainda registrada - remover no Gerenciador de Dispositivos' -Data $phantom
  }
}

function Invoke-EventLogTest {
  Write-TestLog 'Logs de erro recentes' -Level Title
  $since = (Get-Date).AddDays(-7)

  $patterns = @{
    GPU  = 'display|video|gpu|amdkmdag|nvlddmkm|dxgkrnl|TDR|timeout detection|4101'
    Disk = 'disk|ntfs|storahci|nvme|smart'
    BSOD = 'LiveKernelEvent|BugCheck|blue screen'
  }

  foreach ($key in $patterns.Keys) {
    $events = @(Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        Level     = 1,2,3
        StartTime = $since
      } -MaxEvents 300 -ErrorAction SilentlyContinue |
      Where-Object { $_.Message -match $patterns[$key] })

    if ($events.Count -eq 0) {
      Add-TestResult -Category 'Logs' -Name "Eventos $key" -Status 'PASS' -Detail 'Nenhum nos ultimos 7 dias'
    } else {
      $last = $events[0].TimeCreated.ToString('dd/MM HH:mm')
      Add-TestResult -Category 'Logs' -Name "Eventos $key" -Status $(if ($key -eq 'BSOD') { 'FAIL' } else { 'WARN' }) `
        -Detail "$($events.Count) evento(s). Ultimo: $last" -Data ($events | Select-Object -First 5 TimeCreated, Id, Message)
    }
  }
}

function Invoke-ReliabilityTest {
  Write-TestLog 'Indice de confiabilidade Windows' -Level Title
  try {
    $records = Get-CimInstance -Namespace root\cimv2 -ClassName Win32_ReliabilityRecords -ErrorAction Stop |
      Where-Object { $_.TimeGenerated -gt (Get-Date).AddDays(-7) } |
      Sort-Object TimeGenerated -Descending |
      Select-Object -First 20

    $failures = @($records | Where-Object { $_.EventIdentifier -in @(1000,1001,1002) })
    if ($failures.Count -eq 0) {
      Add-TestResult -Category 'Saude' -Name 'Confiabilidade 7d' -Status 'PASS' -Detail 'Sem falhas criticas recentes'
    } else {
      Add-TestResult -Category 'Saude' -Name 'Confiabilidade 7d' -Status 'WARN' -Detail "$($failures.Count) falha(s) na ultima semana" -Data $failures
    }
  } catch {
    Add-TestResult -Category 'Saude' -Name 'Confiabilidade 7d' -Status 'SKIP' -Detail 'Indisponivel neste sistema'
  }
}

function Invoke-DisplayTest {
  Write-TestLog 'Teste de display' -Level Title
  $screens = Add-Type -AssemblyName System.Windows.Forms
  $monitors = [System.Windows.Forms.Screen]::AllScreens

  foreach ($i in 0..($monitors.Count - 1)) {
    $m = $monitors[$i]
    $b = $m.Bounds
    Add-TestResult -Category 'Display' -Name "Monitor $($i+1)" -Status 'INFO' `
      -Detail "$($b.Width)x$($b.Height) | Primario: $($m.Primary) | Bits: $($m.BitsPerPixel)"
  }

  $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Status -eq 'OK' } | Select-Object -First 1
  if ($gpu.CurrentRefreshRate -ge 60) {
    Add-TestResult -Category 'Display' -Name 'Taxa de atualizacao' -Status 'PASS' -Detail "$($gpu.CurrentRefreshRate) Hz"
  } else {
    Add-TestResult -Category 'Display' -Name 'Taxa de atualizacao' -Status 'WARN' -Detail "$($gpu.CurrentRefreshRate) Hz"
  }
}

function Invoke-AudioUsbTest {
  Write-TestLog 'Audio e USB' -Level Title
  $audio = @(Get-PnpDevice -Class Media, AudioEndpoint -Status OK -ErrorAction SilentlyContinue)
  $usb   = @(Get-PnpDevice -Class USB -Status OK -ErrorAction SilentlyContinue)

  Add-TestResult -Category 'Perifericos' -Name 'Audio' -Status $(if ($audio.Count -gt 0) { 'PASS' } else { 'WARN' }) `
    -Detail "$($audio.Count) dispositivo(s) OK"
  Add-TestResult -Category 'Perifericos' -Name 'USB' -Status $(if ($usb.Count -gt 3) { 'PASS' } else { 'WARN' }) `
    -Detail "$($usb.Count) controlador(es) OK"
}

function Invoke-NetworkTest {
  Write-TestLog 'Teste de rede' -Level Title
  $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
  Add-TestResult -Category 'Rede' -Name 'Adaptadores ativos' -Status 'INFO' `
    -Detail (($adapters | ForEach-Object { "$($_.Name) $($_.LinkSpeed)" }) -join '; ')

  $ping = Test-Connection -ComputerName 8.8.8.8 -Count 4 -Quiet -ErrorAction SilentlyContinue
  Add-TestResult -Category 'Rede' -Name 'Ping 8.8.8.8' -Status $(if ($ping) { 'PASS' } else { 'FAIL' }) `
    -Detail $(if ($ping) { 'Conectividade OK' } else { 'Sem internet' })

  if (Test-IsNotebook) {
    $wifi = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Wi-?Fi|Wireless|WLAN' -and $_.Status -eq 'Up' }
    Add-TestResult -Category 'Rede' -Name 'Wi-Fi' -Status $(if ($wifi) { 'PASS' } else { 'WARN' }) `
      -Detail $(if ($wifi) { "Ativo: $($wifi.Name)" } else { 'Wi-Fi nao detectado ou desligado' })
  }
}

function Invoke-WebcamBluetoothTest {
  if (-not (Test-IsNotebook)) { return }
  Write-TestLog 'Webcam e Bluetooth (notebook)' -Level Title

  $cam = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
      $_.FriendlyName -match 'camera|webcam|integrated camera|hp hd|chicony|sunplus' -and $_.Status -eq 'OK'
    })
  Add-TestResult -Category 'Notebook' -Name 'Webcam' -Status $(if ($cam) { 'PASS' } else { 'WARN' }) `
    -Detail $(if ($cam) { $cam[0].FriendlyName } else { 'Nao detectada - testar manualmente' })

  $bt = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Where-Object Status -eq 'OK')
  Add-TestResult -Category 'Notebook' -Name 'Bluetooth' -Status $(if ($bt) { 'PASS' } else { 'WARN' }) `
    -Detail "$($bt.Count) dispositivo(s)"
}
