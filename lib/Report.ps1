# Gerador de relatorio HTML profissional

function Get-HtmlEncoded([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
    return [System.Web.HttpUtility]::HtmlEncode($Text)
}

function Get-StatusIcon([string]$Status) {
    switch ($Status) {
        'PASS' { return '&#10003;' }
        'FAIL' { return '&#10007;' }
        'WARN' { return '&#9888;' }
        'SKIP' { return '&#8212;' }
        default { return '&#9432;' }
    }
}

function Export-TestReport {
    param(
        [string]$OutputDir,
        [string]$KitRoot,
        [string]$Mode
    )

    if (-not $KitRoot) { $KitRoot = Split-Path $OutputDir -Parent }
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    $Script:Report.Meta['FinishedAt'] = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $Script:Report.Meta['Mode'] = $Mode

    $inv     = $Script:Report.Inventory
    $sum     = $Script:Report.Summary
    $machine = if ($inv.ComputerName) { $inv.ComputerName } else { $env:COMPUTERNAME }
    $model   = if ($inv.Model) { "$($inv.Manufacturer) $($inv.Model)" } else { 'Desconhecido' }
    $stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dateBr  = Get-Date -Format 'dd/MM/yyyy HH:mm:ss'
    $baseName = Get-SafeFilename "${stamp}_${machine}_${Mode}"

    $htmlPath = Join-Path $OutputDir "$baseName.html"
    $jsonPath = Join-Path $OutputDir "$baseName.json"
    $latestHtml = Join-Path $KitRoot 'Ultimo-Relatorio.html'
    $latestJson = Join-Path $KitRoot 'Ultimo-Relatorio.json'

    # JSON export
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
                if ($null -ne $t.Data.Score) {
                    $safeData = [ordered]@{
                        Score = $t.Data.Score; MaxTempC = $t.Data.MaxTempC
                        AvgFps = $t.Data.AvgFps; MinFps = $t.Data.MinFps
                        Renderer = $t.Data.Renderer; Seconds = $t.Data.Seconds
                    }
                } elseif ($null -ne $t.Data.Percent) {
                    $safeData = [ordered]@{
                        Percent = $t.Data.Percent; PressedCount = $t.Data.PressedCount
                        Total = $t.Data.Total; Missing = @($t.Data.Missing)
                    }
                } elseif ($t.Data.Installed) {
                    $safeData = [ordered]@{ Installed = $t.Data.Installed; Missing = $t.Data.Missing }
                }
            }
            [ordered]@{ Name = $t.Name; Status = $t.Status; Detail = $t.Detail; Time = $t.Time; Data = $safeData }
        }
    }
    $jsonContent = $export | ConvertTo-Json -Depth 6
    $jsonContent | Set-Content $jsonPath -Encoding UTF8
    $jsonContent | Set-Content $latestJson -Encoding UTF8

    # Veredito
    $verdict = if ($sum.Failed -gt 0) { 'REPROVADO' } elseif ($sum.Warn -gt 3) { 'ATENCAO' } else { 'APROVADO' }
    $verdictClass = switch ($verdict) {
        'APROVADO' { 'pass' }
        'ATENCAO'  { 'warn' }
        default    { 'fail' }
    }
    $verdictDesc = switch ($verdict) {
        'APROVADO' { 'Equipamento aprovado nos testes realizados. Nenhuma falha critica detectada.' }
        'ATENCAO'  { 'Equipamento com alertas. Revisar itens em amarelo antes da compra.' }
        default    { 'Equipamento reprovado. Falhas criticas encontradas — nao recomendado para compra.' }
    }

    $totalTests = [math]::Max(1, $sum.Passed + $sum.Failed + $sum.Warn + $sum.Skip)
    $passPct = if ($totalTests -gt 0) { [math]::Round(($sum.Passed / $totalTests) * 100, 1) } else { 0 }

    # Destaques (GPU, teclado, bateria)
    $highlights = ''
    foreach ($cat in @('GPU', 'Teclado', 'Bateria', 'Disco')) {
        if (-not $Script:Report.Tests.Contains($cat)) { continue }
        foreach ($t in $Script:Report.Tests[$cat]) {
            if ($t.Status -in 'PASS', 'FAIL', 'WARN' -and $t.Name -notmatch 'Modelo|Deteccao|Capacidade|SMART WMI') {
                $highlights += @"
    <div class="highlight-card $($t.Status.ToLower())">
      <div class="hl-cat">$(Get-HtmlEncoded $cat)</div>
      <div class="hl-name">$(Get-HtmlEncoded $t.Name)</div>
      <div class="hl-detail">$(Get-HtmlEncoded $t.Detail)</div>
      <span class="badge $($t.Status.ToLower())">$($t.Status)</span>
    </div>
"@
            }
        }
    }

    # Secoes por categoria
    $sections = ''
    foreach ($cat in $Script:Report.Tests.Keys) {
        $catRows = ''
        foreach ($t in $Script:Report.Tests[$cat]) {
            $cls = $t.Status.ToLower()
            if ($cls -eq 'info') { $cls = 'info' }
            elseif ($cls -notin 'pass','fail','warn','skip') { $cls = 'info' }
            $icon = Get-StatusIcon $t.Status
            $catRows += @"
        <tr class="row-$cls">
          <td class="col-icon">$icon</td>
          <td class="col-test">$(Get-HtmlEncoded $t.Name)</td>
          <td><span class="badge $cls">$($t.Status)</span></td>
          <td class="col-detail">$(Get-HtmlEncoded $t.Detail)</td>
          <td class="col-time">$(Get-HtmlEncoded $t.Time)</td>
        </tr>
"@
        }
        $sections += @"
  <section class="category-block">
    <h2>$(Get-HtmlEncoded $cat)</h2>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th></th>
            <th>Teste</th>
            <th>Status</th>
            <th>Resultado</th>
            <th>Horario</th>
          </tr>
        </thead>
        <tbody>$catRows</tbody>
      </table>
    </div>
  </section>
"@
    }

    $machineType = if ($inv.IsNotebook) { 'Notebook' } else { 'Desktop / PC' }
    $duration = ''
    if ($Script:Report.Meta.StartedAt -and $Script:Report.Meta.FinishedAt) {
        try {
            $start = [datetime]::ParseExact($Script:Report.Meta.StartedAt, 'yyyy-MM-dd HH:mm:ss', $null)
            $end   = [datetime]::ParseExact($Script:Report.Meta.FinishedAt, 'yyyy-MM-dd HH:mm:ss', $null)
            $duration = "$([math]::Round(($end - $start).TotalMinutes, 1)) min"
        } catch { $duration = '-' }
    }

    $ramSpec = Get-HtmlEncoded "$($inv.RAM_GB) GB | $($inv.RAM_Sticks)"
    $highlightsBlock = if ($highlights) {
        "<div class=""highlights""><h2>Destaques dos testes</h2><div class=""highlights-grid"">$highlights</div></div>"
    } else { '' }

    $pctPass = [math]::Round([math]::Max(0, $sum.Passed / $totalTests * 100), 1)
    $pctWarn = [math]::Round([math]::Max(0, $sum.Warn / $totalTests * 100), 1)
    $pctFail = [math]::Round([math]::Max(0, $sum.Failed / $totalTests * 100), 1)
    $pctSkip = [math]::Round([math]::Max(0, $sum.Skip / $totalTests * 100), 1)

    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Laudo Tecnico - $machine - $dateBr</title>
<style>
  :root {
    --bg: #f4f6f9;
    --surface: #ffffff;
    --border: #e2e8f0;
    --text: #1e293b;
    --muted: #64748b;
    --accent: #2563eb;
    --pass: #059669;
    --pass-bg: #ecfdf5;
    --warn: #d97706;
    --warn-bg: #fffbeb;
    --fail: #dc2626;
    --fail-bg: #fef2f2;
    --info: #0369a1;
    --info-bg: #f0f9ff;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    background: var(--bg);
    color: var(--text);
    line-height: 1.5;
    font-size: 14px;
  }
  .page { max-width: 1100px; margin: 0 auto; padding: 32px 24px 48px; }

  /* Capa */
  .cover {
    background: linear-gradient(135deg, #1e3a5f 0%, #2563eb 50%, #3b82f6 100%);
    color: #fff;
    border-radius: 16px;
    padding: 40px 44px;
    margin-bottom: 28px;
    box-shadow: 0 10px 40px rgba(37, 99, 235, 0.25);
  }
  .cover-top { display: flex; justify-content: space-between; align-items: flex-start; flex-wrap: wrap; gap: 16px; }
  .cover-brand { font-size: 0.75rem; letter-spacing: 0.15em; text-transform: uppercase; opacity: 0.85; }
  .cover h1 { font-size: 1.85rem; font-weight: 700; margin: 8px 0 4px; }
  .cover-sub { opacity: 0.9; font-size: 1rem; }
  .cover-meta { text-align: right; font-size: 0.85rem; opacity: 0.9; }
  .verdict-banner {
    margin-top: 28px;
    display: flex;
    align-items: center;
    gap: 24px;
    flex-wrap: wrap;
  }
  .verdict-badge {
    font-size: 1.75rem;
    font-weight: 800;
    padding: 12px 28px;
    border-radius: 12px;
    letter-spacing: 0.05em;
  }
  .verdict-badge.pass { background: #fff; color: var(--pass); }
  .verdict-badge.warn { background: #fff; color: var(--warn); }
  .verdict-badge.fail { background: #fff; color: var(--fail); }
  .verdict-text { flex: 1; min-width: 200px; font-size: 0.95rem; opacity: 0.95; }

  /* Cards resumo */
  .stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
    gap: 16px;
    margin-bottom: 28px;
  }
  .stat-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 20px;
    text-align: center;
    box-shadow: 0 1px 3px rgba(0,0,0,0.04);
  }
  .stat-card .num { font-size: 2rem; font-weight: 800; line-height: 1.2; }
  .stat-card .lbl { font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted); margin-top: 4px; }
  .stat-card.pass .num { color: var(--pass); }
  .stat-card.fail .num { color: var(--fail); }
  .stat-card.warn .num { color: var(--warn); }

  /* Barra progresso */
  .progress-section {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 24px;
    margin-bottom: 28px;
  }
  .progress-section h3 { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted); margin-bottom: 12px; }
  .progress-bar { height: 12px; background: #e2e8f0; border-radius: 6px; overflow: hidden; display: flex; }
  .progress-bar .seg-pass { background: var(--pass); }
  .progress-bar .seg-warn { background: var(--warn); }
  .progress-bar .seg-fail { background: var(--fail); }
  .progress-bar .seg-skip { background: #cbd5e1; }
  .progress-legend { display: flex; gap: 20px; margin-top: 10px; font-size: 0.8rem; color: var(--muted); flex-wrap: wrap; }

  /* Especificacoes */
  .spec-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: 16px;
    margin-bottom: 28px;
  }
  .spec-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 20px 24px;
  }
  .spec-card h3 {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: var(--accent);
    margin-bottom: 12px;
    padding-bottom: 8px;
    border-bottom: 2px solid #eff6ff;
  }
  .spec-row { display: flex; padding: 6px 0; border-bottom: 1px solid #f1f5f9; }
  .spec-row:last-child { border-bottom: none; }
  .spec-label { width: 90px; flex-shrink: 0; color: var(--muted); font-size: 0.8rem; }
  .spec-value { flex: 1; font-size: 0.85rem; word-break: break-word; }

  /* Destaques */
  .highlights { margin-bottom: 28px; }
  .highlights h2 { font-size: 1.1rem; margin-bottom: 14px; color: var(--text); }
  .highlights-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 14px; }
  .highlight-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 16px;
    border-left: 4px solid var(--border);
  }
  .highlight-card.pass { border-left-color: var(--pass); background: var(--pass-bg); }
  .highlight-card.warn { border-left-color: var(--warn); background: var(--warn-bg); }
  .highlight-card.fail { border-left-color: var(--fail); background: var(--fail-bg); }
  .hl-cat { font-size: 0.65rem; text-transform: uppercase; letter-spacing: 0.1em; color: var(--muted); }
  .hl-name { font-weight: 700; margin: 4px 0; }
  .hl-detail { font-size: 0.82rem; color: var(--muted); margin-bottom: 8px; }

  /* Tabelas por categoria */
  .category-block { margin-bottom: 28px; }
  .category-block h2 {
    font-size: 1rem;
    margin-bottom: 10px;
    padding-left: 12px;
    border-left: 4px solid var(--accent);
  }
  .table-wrap {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    overflow: hidden;
    box-shadow: 0 1px 3px rgba(0,0,0,0.04);
  }
  table { width: 100%; border-collapse: collapse; }
  th {
    background: #f8fafc;
    padding: 12px 14px;
    text-align: left;
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--muted);
    border-bottom: 1px solid var(--border);
  }
  td { padding: 11px 14px; border-bottom: 1px solid #f1f5f9; font-size: 0.85rem; vertical-align: top; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #fafbfc; }
  .col-icon { width: 32px; text-align: center; font-size: 1rem; }
  .col-time { white-space: nowrap; color: var(--muted); font-size: 0.78rem; width: 130px; }
  .col-detail { color: #475569; max-width: 400px; }
  .row-pass .col-icon { color: var(--pass); }
  .row-fail .col-icon { color: var(--fail); }
  .row-warn .col-icon { color: var(--warn); }

  .badge {
    display: inline-block;
    padding: 3px 10px;
    border-radius: 20px;
    font-size: 0.68rem;
    font-weight: 700;
    letter-spacing: 0.04em;
  }
  .badge.pass { background: var(--pass-bg); color: var(--pass); }
  .badge.fail { background: var(--fail-bg); color: var(--fail); }
  .badge.warn { background: var(--warn-bg); color: var(--warn); }
  .badge.skip { background: #f1f5f9; color: var(--muted); }
  .badge.info { background: var(--info-bg); color: var(--info); }

  .footer {
    margin-top: 40px;
    padding-top: 24px;
    border-top: 1px solid var(--border);
    text-align: center;
    color: var(--muted);
    font-size: 0.78rem;
  }
  .footer strong { color: var(--text); }
  .disclaimer {
    background: #fffbeb;
    border: 1px solid #fde68a;
    border-radius: 8px;
    padding: 14px 18px;
    margin-top: 20px;
    font-size: 0.8rem;
    color: #92400e;
    text-align: left;
  }

  @media print {
    body { background: #fff; }
    .page { padding: 0; max-width: 100%; }
    .cover { box-shadow: none; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    .category-block { break-inside: avoid; }
  }
</style>
</head>
<body>
<div class="page">

  <header class="cover">
    <div class="cover-top">
      <div>
        <div class="cover-brand">Hardware Test Kit</div>
        <h1>Laudo Tecnico de Hardware</h1>
        <p class="cover-sub">Avaliacao para compra de equipamentos usados</p>
      </div>
      <div class="cover-meta">
        <div><strong>ID:</strong> $baseName</div>
        <div><strong>Data:</strong> $dateBr</div>
        <div><strong>Duracao:</strong> $duration</div>
        <div><strong>Modo:</strong> $Mode</div>
      </div>
    </div>
    <div class="verdict-banner">
      <div class="verdict-badge $verdictClass">$verdict</div>
      <p class="verdict-text">$verdictDesc</p>
    </div>
  </header>

  <div class="stats-grid">
    <div class="stat-card pass"><div class="num">$($sum.Passed)</div><div class="lbl">Aprovados</div></div>
    <div class="stat-card fail"><div class="num">$($sum.Failed)</div><div class="lbl">Falhas</div></div>
    <div class="stat-card warn"><div class="num">$($sum.Warn)</div><div class="lbl">Alertas</div></div>
    <div class="stat-card"><div class="num">$($sum.Skip)</div><div class="lbl">Ignorados</div></div>
    <div class="stat-card pass"><div class="num">${passPct}%</div><div class="lbl">Taxa de aprovacao</div></div>
  </div>

  <div class="progress-section">
    <h3>Distribuicao dos resultados</h3>
    <div class="progress-bar">
      <div class="seg-pass" style="width:${pctPass}%"></div>
      <div class="seg-warn" style="width:${pctWarn}%"></div>
      <div class="seg-fail" style="width:${pctFail}%"></div>
      <div class="seg-skip" style="width:${pctSkip}%"></div>
    </div>
    <div class="progress-legend">
      <span>&#9679; Aprovados ($($sum.Passed))</span>
      <span>&#9679; Alertas ($($sum.Warn))</span>
      <span>&#9679; Falhas ($($sum.Failed))</span>
      <span>&#9679; Ignorados ($($sum.Skip))</span>
    </div>
  </div>

  <div class="spec-grid">
    <div class="spec-card">
      <h3>Equipamento</h3>
      <div class="spec-row"><span class="spec-label">Tipo</span><span class="spec-value">$machineType</span></div>
      <div class="spec-row"><span class="spec-label">Modelo</span><span class="spec-value">$(Get-HtmlEncoded $model)</span></div>
      <div class="spec-row"><span class="spec-label">Hostname</span><span class="spec-value">$(Get-HtmlEncoded $machine)</span></div>
      <div class="spec-row"><span class="spec-label">Sistema</span><span class="spec-value">$(Get-HtmlEncoded $inv.OS)</span></div>
      <div class="spec-row"><span class="spec-label">BIOS</span><span class="spec-value">$(Get-HtmlEncoded $inv.BIOS)</span></div>
    </div>
    <div class="spec-card">
      <h3>Componentes</h3>
      <div class="spec-row"><span class="spec-label">CPU</span><span class="spec-value">$(Get-HtmlEncoded $inv.CPU)</span></div>
      <div class="spec-row"><span class="spec-label">GPU</span><span class="spec-value">$(Get-HtmlEncoded $inv.GPU)</span></div>
      <div class="spec-row"><span class="spec-label">RAM</span><span class="spec-value">$ramSpec</span></div>
      <div class="spec-row"><span class="spec-label">Discos</span><span class="spec-value">$(Get-HtmlEncoded $inv.Disks)</span></div>
      <div class="spec-row"><span class="spec-label">Volumes</span><span class="spec-value">$(Get-HtmlEncoded $inv.Volumes)</span></div>
    </div>
  </div>

  $highlightsBlock

  <h2 style="font-size:1.15rem;margin-bottom:16px;">Detalhamento completo</h2>
  $sections

  <footer class="footer">
    <p><strong>Hardware Test Kit</strong> - Relatorio gerado automaticamente</p>
    <p>Inicio: $($Script:Report.Meta.StartedAt) &nbsp;|&nbsp; Fim: $($Script:Report.Meta.FinishedAt)</p>
    <div class="disclaimer">
      Este laudo e uma ferramenta de apoio a decisao de compra. Recomenda-se inspecao fisica do equipamento,
      verificacao de nota fiscal e testes adicionais quando necessario. Resultados podem variar conforme
      configuracao do sistema e ferramentas instaladas.
    </div>
  </footer>
</div>
</body>
</html>
"@

    $html | Set-Content $htmlPath -Encoding UTF8
    $html | Set-Content $latestHtml -Encoding UTF8

    # Atalho para ultimo relatorio na pasta principal
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $lnk = $WshShell.CreateShortcut((Join-Path $KitRoot 'Abrir Ultimo Relatorio.lnk'))
        $lnk.TargetPath = $latestHtml
        $lnk.Description = 'Ultimo laudo tecnico de hardware'
        $lnk.Save()
    } catch {}

    Write-TestLog "Laudo HTML: $htmlPath" -Level Ok
    Write-TestLog "Copia na pasta: $latestHtml" -Level Ok
    Write-TestLog "JSON: $jsonPath" -Level Ok

    return @{
        Html    = $htmlPath
        Latest  = $latestHtml
        Json    = $jsonPath
        Verdict = $verdict
    }
}
