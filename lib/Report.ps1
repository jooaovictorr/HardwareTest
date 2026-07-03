# Gerador de relatorio HTML

function Export-TestReport {
  param(
    [string]$OutputDir,
    [string]$Mode
  )

  New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
  $Script:Report.Meta['FinishedAt'] = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  $Script:Report.Meta['Mode'] = $Mode

  $inv = $Script:Report.Inventory
  $sum = $Script:Report.Summary
  $machine = if ($inv.ComputerName) { $inv.ComputerName } else { $env:COMPUTERNAME }
  $model = if ($inv.Model) { "$($inv.Manufacturer) $($inv.Model)" } else { 'Desconhecido' }
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $baseName = Get-SafeFilename "${stamp}_${machine}_${Mode}"
  $htmlPath = Join-Path $OutputDir "$baseName.html"
  $jsonPath = Join-Path $OutputDir "$baseName.json"

  # JSON (sem dados pesados de PnP/FurMark)
  $export = [ordered]@{
    Meta      = $Script:Report.Meta
    Inventory = $Script:Report.Inventory
    Summary   = $Script:Report.Summary
    Tests     = [ordered]@{}
  }
  foreach ($cat in $Script:Report.Tests.Keys) {
    $export.Tests[$cat] = foreach ($t in $Script:Report.Tests[$cat]) {
      $safeData = $null
      if ($t.Data) {
        if ($t.Data.Score -ne $null) {
          $safeData = [ordered]@{
            Score = $t.Data.Score; MaxTempC = $t.Data.MaxTempC
            AvgFps = $t.Data.AvgFps; Renderer = $t.Data.Renderer; Seconds = $t.Data.Seconds
          }
        } elseif ($t.Data.Percent -ne $null) {
          $safeData = [ordered]@{ Percent = $t.Data.Percent; PressedCount = $t.Data.PressedCount; Total = $t.Data.Total; Missing = @($t.Data.Missing) }
        } elseif ($t.Data.Installed) {
          $safeData = [ordered]@{ Installed = $t.Data.Installed; Missing = $t.Data.Missing }
        }
      }
      [ordered]@{ Name = $t.Name; Status = $t.Status; Detail = $t.Detail; Time = $t.Time; Data = $safeData }
    }
  }
  $export | ConvertTo-Json -Depth 6 | Set-Content $jsonPath -Encoding UTF8

  # HTML rows
  $rows = ''
  foreach ($cat in $Script:Report.Tests.Keys) {
    foreach ($t in $Script:Report.Tests[$cat]) {
      $cls = switch ($t.Status) {
        'PASS' { 'pass' }
        'FAIL' { 'fail' }
        'WARN' { 'warn' }
        default { 'info' }
      }
      $rows += @"
<tr class="$cls">
  <td>$cat</td>
  <td>$($t.Name)</td>
  <td><span class="badge $cls">$($t.Status)</span></td>
  <td>$([System.Web.HttpUtility]::HtmlEncode($t.Detail))</td>
  <td>$($t.Time)</td>
</tr>
"@
    }
  }

  $verdict = if ($sum.Failed -gt 0) { 'REPROVADO' } elseif ($sum.Warn -gt 3) { 'ATENCAO' } else { 'APROVADO' }
  $verdictClass = if ($sum.Failed -gt 0) { 'fail' } elseif ($sum.Warn -gt 3) { 'warn' } else { 'pass' }

  $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>Relatorio Hardware - $machine</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', sans-serif; background: #0f1117; color: #e2e8f0; padding: 24px; }
  h1 { font-size: 1.5rem; margin-bottom: 8px; }
  .header { background: #1a1f2e; border-radius: 12px; padding: 24px; margin-bottom: 20px; border: 1px solid #2d3748; }
  .verdict { display: inline-block; padding: 6px 16px; border-radius: 20px; font-weight: 700; font-size: 1.1rem; margin: 12px 0; }
  .verdict.pass { background: #065f46; color: #6ee7b7; }
  .verdict.warn { background: #78350f; color: #fcd34d; }
  .verdict.fail { background: #7f1d1d; color: #fca5a5; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px,1fr)); gap: 12px; margin: 16px 0; }
  .card { background: #1a1f2e; border-radius: 8px; padding: 14px; border: 1px solid #2d3748; }
  .card .label { font-size: 0.75rem; color: #94a3b8; text-transform: uppercase; }
  .card .value { font-size: 1.4rem; font-weight: 700; margin-top: 4px; }
  .card .value.pass { color: #34d399; }
  .card .value.fail { color: #f87171; }
  .card .value.warn { color: #fbbf24; }
  table { width: 100%; border-collapse: collapse; background: #1a1f2e; border-radius: 12px; overflow: hidden; }
  th { background: #252d3d; padding: 12px; text-align: left; font-size: 0.8rem; color: #94a3b8; }
  td { padding: 10px 12px; border-top: 1px solid #2d3748; font-size: 0.875rem; }
  tr.pass td:first-child { border-left: 3px solid #34d399; }
  tr.fail td:first-child { border-left: 3px solid #f87171; }
  tr.warn td:first-child { border-left: 3px solid #fbbf24; }
  .badge { padding: 2px 8px; border-radius: 4px; font-size: 0.75rem; font-weight: 600; }
  .badge.pass { background: #065f46; color: #6ee7b7; }
  .badge.fail { background: #7f1d1d; color: #fca5a5; }
  .badge.warn { background: #78350f; color: #fcd34d; }
  .badge.info { background: #1e3a5f; color: #93c5fd; }
  .inv { margin-top: 16px; font-size: 0.85rem; color: #94a3b8; line-height: 1.8; }
  .inv strong { color: #e2e8f0; }
</style>
</head>
<body>
<div class="header">
  <h1>Relatorio de Testes de Hardware</h1>
  <p style="color:#94a3b8;margin-top:4px">$model | Modo: $Mode | $($Script:Report.Meta.StartedAt)</p>
  <div class="verdict $verdictClass">$verdict</div>
  <div class="grid">
    <div class="card"><div class="label">Aprovados</div><div class="value pass">$($sum.Passed)</div></div>
    <div class="card"><div class="label">Falhas</div><div class="value fail">$($sum.Failed)</div></div>
    <div class="card"><div class="label">Alertas</div><div class="value warn">$($sum.Warn)</div></div>
    <div class="card"><div class="label">Ignorados</div><div class="value">$($sum.Skip)</div></div>
  </div>
  <div class="inv">
    <strong>CPU:</strong> $($inv.CPU)<br>
    <strong>GPU:</strong> $($inv.GPU)<br>
    <strong>RAM:</strong> $($inv.RAM_GB) GB — $($inv.RAM_Sticks)<br>
    <strong>OS:</strong> $($inv.OS)<br>
    <strong>Discos:</strong> $($inv.Disks)
  </div>
</div>
<table>
  <thead><tr><th>Categoria</th><th>Teste</th><th>Status</th><th>Detalhe</th><th>Hora</th></tr></thead>
  <tbody>$rows</tbody>
</table>
<p style="margin-top:20px;color:#475569;font-size:0.75rem">Gerado por HardwareTest Kit — $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</p>
</body>
</html>
"@

  Add-Type -AssemblyName System.Web
  $html | Set-Content $htmlPath -Encoding UTF8

  Write-TestLog "Relatorio HTML: $htmlPath" -Level Ok
  Write-TestLog "Relatorio JSON: $jsonPath" -Level Ok

  return @{ Html = $htmlPath; Json = $jsonPath; Verdict = $verdict }
}
