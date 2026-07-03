# Teste interativo completo de teclado (notebook)

function Get-KeyboardTestLayout {
  $letters = 65..90 | ForEach-Object { [System.Windows.Forms.Keys]$_ }
  $digits  = 48..57 | ForEach-Object { [System.Windows.Forms.Keys]$_ }
  $fkeys   = 112..123 | ForEach-Object { [System.Windows.Forms.Keys]$_ }
  $main = @(
    'Space', 'Return', 'Back', 'Tab', 'Escape', 'Capital',
    'Insert', 'Delete', 'Home', 'End', 'Prior', 'Next',
    'Left', 'Right', 'Up', 'Down'
  ) | ForEach-Object { [System.Windows.Forms.Keys]$_ }
  $mods = @(
    'LShiftKey', 'RShiftKey', 'LControlKey', 'RControlKey',
    'LMenu', 'RMenu', 'LWin', 'RWin'
  ) | ForEach-Object { [System.Windows.Forms.Keys]$_ }
  $oem = @(
    'Oemcomma', 'Oem1', 'Oem2', 'Oem3', 'Oem4', 'Oem5',
    'Oem6', 'Oem7', 'OemMinus', 'Oemplus', 'Oemtilde', 'OemOpenBrackets', 'OemCloseBrackets', 'OemPipe'
  ) | ForEach-Object { [System.Windows.Forms.Keys]$_ }
  $numpad = @(
    'NumPad0', 'NumPad1', 'NumPad2', 'NumPad3', 'NumPad4',
    'NumPad5', 'NumPad6', 'NumPad7', 'NumPad8', 'NumPad9',
    'Add', 'Subtract', 'Multiply', 'Divide', 'Decimal'
  ) | ForEach-Object { [System.Windows.Forms.Keys]$_ }

  $labels = @{
    Space = 'Espaco'; Return = 'Enter'; Back = 'Backspace'; Tab = 'Tab'
    Escape = 'Esc'; Capital = 'CapsLock'; Prior = 'PageUp'; Next = 'PageDown'
    LShiftKey = 'Shift Esq'; RShiftKey = 'Shift Dir'
    LControlKey = 'Ctrl Esq'; RControlKey = 'Ctrl Dir'
    LMenu = 'Alt Esq'; RMenu = 'Alt Dir'
    LWin = 'Win Esq'; RWin = 'Win Dir'
    Oemcomma = 'Ç'; Oem1 = ';'; Oem2 = '''; Oem3 = ']'; Oem4 = '´'
    Oem5 = '['; Oem6 = '¨'; Oem7 = '/'; OemMinus = '-'; Oemplus = '='
    Oemtilde = '~'; OemOpenBrackets = '`'; OemCloseBrackets = '['; OemPipe = '\'
    Add = 'Num +'; Subtract = 'Num -'; Multiply = 'Num *'; Divide = 'Num /'; Decimal = 'Num .'
  }

  $all = @($letters + $digits + $fkeys + $main + $mods + $oem + $numpad)
  return @{ Keys = $all; Labels = $labels }
}

function Invoke-KeyboardTest {
  param(
    [int]$MinPercent = 85
  )

  Write-TestLog 'Teste de teclado completo' -Level Title
  Write-TestLog 'Abrindo janela interativa - pressione todas as teclas' -Level Step

  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  $layout = Get-KeyboardTestLayout
  $pressed = @{}
  foreach ($k in $layout.Keys) { $pressed[$k.ToString()] = $false }

  $result = @{ Completed = $false; Cancelled = $false; Percent = 0; Missing = @(); PressedCount = 0; Total = $layout.Keys.Count }

  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'Hardware Test Kit - Teste de Teclado'
  $form.StartPosition = 'CenterScreen'
  $form.Size = New-Object System.Drawing.Size(1100, 750)
  $form.KeyPreview = $true
  $form.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 23)
  $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

  $title = New-Object System.Windows.Forms.Label
  $title.Text = 'TESTE DE TECLADO - Pressione cada tecla do notebook'
  $title.ForeColor = [System.Drawing.Color]::White
  $title.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
  $title.Location = New-Object System.Drawing.Point(20, 15)
  $title.Size = New-Object System.Drawing.Size(1050, 30)
  $form.Controls.Add($title)

  $hint = New-Object System.Windows.Forms.Label
  $hint.Text = 'F10 = Concluir teste  |  ESC = Cancelar  |  Teste letras, numeros, F1-F12, setas, Alt, Ctrl, Shift, Win, teclas ABNT2 e teclado numerico'
  $hint.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
  $hint.Location = New-Object System.Drawing.Point(20, 48)
  $hint.Size = New-Object System.Drawing.Size(1050, 20)
  $form.Controls.Add($hint)

  $progress = New-Object System.Windows.Forms.ProgressBar
  $progress.Location = New-Object System.Drawing.Point(20, 78)
  $progress.Size = New-Object System.Drawing.Size(1050, 24)
  $progress.Maximum = $layout.Keys.Count
  $form.Controls.Add($progress)

  $statusLbl = New-Object System.Windows.Forms.Label
  $statusLbl.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
  $statusLbl.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
  $statusLbl.Location = New-Object System.Drawing.Point(20, 108)
  $statusLbl.Size = New-Object System.Drawing.Size(1050, 25)
  $form.Controls.Add($statusLbl)

  $panel = New-Object System.Windows.Forms.FlowLayoutPanel
  $panel.Location = New-Object System.Drawing.Point(20, 140)
  $panel.Size = New-Object System.Drawing.Size(1050, 480)
  $panel.AutoScroll = $true
  $panel.BackColor = [System.Drawing.Color]::FromArgb(26, 31, 46)
  $form.Controls.Add($panel)

  $keyLabels = @{}
  foreach ($key in $layout.Keys) {
    $name = $key.ToString()
    $display = if ($layout.Labels.ContainsKey($name)) { $layout.Labels[$name] } else { $name }
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $display
    $lbl.Size = New-Object System.Drawing.Size(72, 28)
    $lbl.Margin = '3,3,3,3'
    $lbl.TextAlign = 'MiddleCenter'
    $lbl.BackColor = [System.Drawing.Color]::FromArgb(45, 55, 72)
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(203, 213, 225)
    $lbl.Tag = $name
    $panel.Controls.Add($lbl)
    $keyLabels[$name] = $lbl
  }

  $missingLbl = New-Object System.Windows.Forms.Label
  $missingLbl.ForeColor = [System.Drawing.Color]::FromArgb(251, 191, 36)
  $missingLbl.Location = New-Object System.Drawing.Point(20, 630)
  $missingLbl.Size = New-Object System.Drawing.Size(800, 60)
  $form.Controls.Add($missingLbl)

  $btnDone = New-Object System.Windows.Forms.Button
  $btnDone.Text = 'Concluir (F10)'
  $btnDone.Location = New-Object System.Drawing.Point(900, 640)
  $btnDone.Size = New-Object System.Drawing.Size(170, 40)
  $btnDone.BackColor = [System.Drawing.Color]::FromArgb(6, 95, 70)
  $btnDone.ForeColor = [System.Drawing.Color]::White
  $btnDone.FlatStyle = 'Flat'
  $form.Controls.Add($btnDone)

  $updateUi = {
    $count = ($pressed.Values | Where-Object { $_ }).Count
    $pct = [math]::Round(($count / $layout.Keys.Count) * 100, 1)
    $progress.Value = [math]::Min($count, $progress.Maximum)
    $statusLbl.Text = "Progresso: $count / $($layout.Keys.Count) teclas ($pct%)"
    $missing = @()
    foreach ($k in $layout.Keys) {
      $n = $k.ToString()
      if ($pressed[$n]) {
        $keyLabels[$n].BackColor = [System.Drawing.Color]::FromArgb(6, 95, 70)
        $keyLabels[$n].ForeColor = [System.Drawing.Color]::White
      } else {
        $display = if ($layout.Labels.ContainsKey($n)) { $layout.Labels[$n] } else { $n }
        $missing += $display
      }
    }
    if ($missing.Count -le 15) {
      $missingLbl.Text = if ($missing.Count -eq 0) { 'Todas as teclas testadas!' } else { "Faltam: $($missing -join ', ')" }
    } else {
      $missingLbl.Text = "Faltam $($missing.Count) teclas - continue pressionando..."
    }
    $result.Percent = $pct
    $result.PressedCount = $count
    $result.Missing = $missing
  }

  $markKey = {
    param($key)
    $n = $key.ToString()
    if ($pressed.ContainsKey($n)) {
      $pressed[$n] = $true
      & $updateUi
    }
  }

  $finishTest = {
    param($cancelled)
    $result.Cancelled = $cancelled
    $result.Completed = -not $cancelled
    $form.Close()
  }

  $form.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq 'F10') {
      & $finishTest $false
      $e.Handled = $true
      return
    }
    if ($e.KeyCode -eq 'Escape') {
      $ans = [System.Windows.Forms.MessageBox]::Show(
        'Cancelar o teste de teclado?', 'Confirmar', 'YesNo', 'Question')
      if ($ans -eq 'Yes') { & $finishTest $true }
      $e.Handled = $true
      return
    }
    & $markKey $e.KeyCode
    if ($e.KeyCode -in 'ShiftKey', 'ControlKey', 'Menu') {
      if ($e.Shift) { & $markKey 'LShiftKey'; & $markKey 'RShiftKey' }
      if ($e.Control) { & $markKey 'LControlKey'; & $markKey 'RControlKey' }
      if ($e.Alt) { & $markKey 'LMenu'; & $markKey 'RMenu' }
    }
  })

  $btnDone.Add_Click({ & $finishTest $false })
  & $updateUi

  [void]$form.ShowDialog()
  $form.Dispose()

  if ($result.Cancelled) {
    Add-TestResult -Category 'Teclado' -Name 'Teste completo' -Status 'SKIP' `
      -Detail "Cancelado pelo usuario ($($result.PressedCount)/$($result.Total) teclas)"
    return
  }

  $pct = $result.Percent
  $status = if ($pct -ge $MinPercent) { 'PASS' } elseif ($pct -ge 60) { 'WARN' } else { 'FAIL' }
  $missingStr = if ($result.Missing.Count -le 20) { $result.Missing -join ', ' } else { "$($result.Missing.Count) teclas" }

  Add-TestResult -Category 'Teclado' -Name 'Teste completo' -Status $status `
    -Detail "$($result.PressedCount)/$($result.Total) teclas ($pct%) | Faltaram: $missingStr" `
    -Data @{
      PressedCount = $result.PressedCount
      Total        = $result.Total
      Percent      = $pct
      Missing      = @($result.Missing)
    }

  if ($result.Missing.Count -gt 0 -and $result.Missing.Count -le 30) {
    Add-TestResult -Category 'Teclado' -Name 'Teclas nao detectadas' -Status 'WARN' `
      -Detail ($result.Missing -join ', ')
  }
}
