# Funcoes compartilhadas do kit de testes

$Script:Report = [ordered]@{
    Meta      = [ordered]@{}
    Inventory = [ordered]@{}
    Tests     = [ordered]@{}
    Summary   = [ordered]@{
        Passed = 0
        Failed = 0
        Warn   = 0
        Skip   = 0
    }
}

function Write-TestLog {
    param(
        [string]$Message,
        [ValidateSet('Info','Ok','Warn','Fail','Step','Title')]
        [string]$Level = 'Info'
    )
    $colors = @{
        Info  = 'Gray'
        Ok    = 'Green'
        Warn  = 'Yellow'
        Fail  = 'Red'
        Step  = 'Cyan'
        Title = 'White'
    }
    $prefix = switch ($Level) {
        'Ok'    { '[ OK ]' }
        'Warn'  { '[!!]' }
        'Fail'  { '[XX]' }
        'Step'  { '[>>]' }
        'Title' { '====' }
        default { '[--]' }
    }
    if ($Level -eq 'Title') {
        Write-Host "`n=== $Message ===" -ForegroundColor $colors[$Level]
    } else {
        Write-Host "$prefix $Message" -ForegroundColor $colors[$Level]
    }
}

function Add-TestResult {
    param(
        [string]$Category,
        [string]$Name,
        [ValidateSet('PASS','FAIL','WARN','SKIP','INFO')]
        [string]$Status,
        [string]$Detail = '',
        $Data = $null
    )
    if (-not $Script:Report.Tests.Contains($Category)) {
        $Script:Report.Tests[$Category] = [System.Collections.Generic.List[object]]::new()
    }
    $entry = [ordered]@{
        Name   = $Name
        Status = $Status
        Detail = $Detail
        Data   = $Data
        Time   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    $Script:Report.Tests[$Category].Add([pscustomobject]$entry) | Out-Null

    switch ($Status) {
        'PASS' { $Script:Report.Summary.Passed++ }
        'FAIL' { $Script:Report.Summary.Failed++ }
        'WARN' { $Script:Report.Summary.Warn++ }
        'SKIP' { $Script:Report.Summary.Skip++ }
    }

    $level = switch ($Status) {
        'PASS' { 'Ok' }
        'FAIL' { 'Fail' }
        'WARN' { 'Warn' }
        default { 'Info' }
    }
    $msg = "$Name"
    if ($Detail) { $msg += " - $Detail" }
    Write-TestLog $msg -Level $level
}

function Test-IsNotebook {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        return ($cs.PCSystemType -in 2, 3, 4, 11, 12) -or
               ($cs.Model -match 'laptop|notebook|book|vivobook|ideapad|pavilion|inspiron|nitro|legion|acer|asus|dell|hp|lenovo' -and
                $cs.Model -notmatch 'desktop|tower|workstation')
    } catch {
        return (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) -ne $null
    }
}

function Find-ToolExe {
    param([string[]]$Paths)
    $expanded = foreach ($p in $Paths) {
        if ($p -match '\$env:') {
            $ExecutionContext.InvokeCommand.ExpandString($p)
        } else { $p }
    }
    foreach ($p in $expanded) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    # Tentar paths dinamicos padrao
    foreach ($p in $Paths) {
        $dyn = $p -replace '\$env:ProgramFiles', $env:ProgramFiles -replace '\$\{env:ProgramFiles\(x86\)\}', ${env:ProgramFiles(x86)}
        if ($dyn -and (Test-Path -LiteralPath $dyn)) { return $dyn }
    }
    return $null
}

function Install-TestTool {
    param(
        [string]$WingetId,
        [string]$Name
    )
    Write-TestLog "Instalando $Name via winget..." -Level Step
    $proc = Start-Process -FilePath 'winget' -ArgumentList @(
        'install', '--id', $WingetId,
        '--accept-package-agreements', '--accept-source-agreements', '--silent'
    ) -Wait -PassThru -NoNewWindow
    return $proc.ExitCode -in 0, -1978335189  # ja instalado
}

function Ensure-TestTools {
    param(
        [hashtable]$Config,
        [string[]]$Mode
    )
    Write-TestLog 'Verificando ferramentas de teste' -Level Title
    $installed = @()
    $missing   = @()

    foreach ($toolName in $Config.Tools.Keys) {
        $tool = $Config.Tools[$toolName]
        $needed = $false
        foreach ($m in $Mode) {
            if ($tool.RequiredFor -contains $m -or $tool.RequiredFor -contains 'Completo') {
                $needed = $true
                break
            }
        }
        if (-not $needed) { continue }

        $exe = Find-ToolExe -Paths $tool.ExePaths
        if ($exe) {
            $installed += [pscustomobject]@{ Name = $toolName; Path = $exe }
            Write-TestLog "$toolName encontrado: $exe" -Level Ok
        } else {
            $missing += $toolName
            Write-TestLog "$toolName nao encontrado" -Level Warn
            if (Install-TestTool -WingetId $tool.Id -Name $toolName) {
                $exe = Find-ToolExe -Paths $tool.ExePaths
                if ($exe) {
                    $installed += [pscustomobject]@{ Name = $toolName; Path = $exe }
                    Write-TestLog "$toolName instalado: $exe" -Level Ok
                }
            }
        }
    }

    Add-TestResult -Category 'Setup' -Name 'Ferramentas' -Status 'INFO' -Detail "$($installed.Count) ok, $($missing.Count) faltando" -Data @{
        Installed = $installed
        Missing   = $missing
    }
    return $installed
}

function Get-SafeFilename {
    param([string]$Text)
    ($Text -replace '[\\/:*?"<>|]', '-') -replace '\s+', '_'
}

function Invoke-ExternalTest {
    param(
        [string]$Exe,
        [string[]]$Arguments,
        [int]$TimeoutSec = 600
    )
    $psi = @{
        FilePath     = $Exe
        ArgumentList = $Arguments
        PassThru     = $true
        NoNewWindow  = $true
        Wait         = $true
    }
    $job = Start-Job -ScriptBlock {
        param($e, $a)
        $p = Start-Process -FilePath $e -ArgumentList $a -PassThru -NoNewWindow -Wait
        return $p.ExitCode
    } -ArgumentList $Exe, $Arguments

    $done = Wait-Job $job -Timeout $TimeoutSec
    if (-not $done) {
        Stop-Job $job -Force
        Remove-Job $job -Force
        return @{ ExitCode = -1; TimedOut = $true }
    }
    $code = Receive-Job $job
    Remove-Job $job -Force
    return @{ ExitCode = $code; TimedOut = $false }
}
