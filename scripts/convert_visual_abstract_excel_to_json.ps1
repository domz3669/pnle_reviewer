param(
  [string]$ExcelPath = "assets/Abstract Reasoning/Answers.xlsx",
  [string]$OutputPath = "assets/Abstract Reasoning/visual_abstract_questions.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Normalize-HeaderName {
  param([string]$Value)
  if ($null -eq $Value) { $Value = '' }
  $raw = $Value.Trim().ToLowerInvariant()
  if ([string]::IsNullOrWhiteSpace($raw)) { return "" }
  return ($raw -replace '[^a-z0-9]', '')
}

function Try-GetInt {
  param([string]$Value)
  if ($null -eq $Value) { $Value = '' }
  $parsed = 0
  if ([int]::TryParse($Value.Trim(), [ref]$parsed)) {
    return $parsed
  }
  return $null
}

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$wb = $null
$ws = $null
$used = $null

try {
  $resolvedExcelPath = (Resolve-Path $ExcelPath).Path
  $wb = $excel.Workbooks.Open($resolvedExcelPath)
  $ws = $wb.Worksheets.Item(1)
  $used = $ws.UsedRange

  $rowCount = $used.Rows.Count
  $colCount = $used.Columns.Count

  if ($rowCount -lt 2) {
    throw "Excel file has no data rows."
  }

  $headerIndex = @{}
  for ($c = 1; $c -le $colCount; $c++) {
    $name = Normalize-HeaderName -Value ($used.Item(1, $c).Text)
    if (-not [string]::IsNullOrWhiteSpace($name) -and -not $headerIndex.ContainsKey($name)) {
      $headerIndex[$name] = $c
    }
  }

  $imageCol = $null
  foreach ($key in @('imagecode', 'image', 'picture', 'figure', 'imageassetpath')) {
    if ($headerIndex.ContainsKey($key)) { $imageCol = $headerIndex[$key]; break }
  }
  if ($null -eq $imageCol) {
    throw "Missing required Image Code column (e.g., 'Image Code')."
  }

  $answerCol = $null
  foreach ($key in @('correctanswer', 'answer')) {
    if ($headerIndex.ContainsKey($key)) { $answerCol = $headerIndex[$key]; break }
  }
  if ($null -eq $answerCol) {
    throw "Missing required Correct Answer column."
  }

  $explanationCol = $null
  foreach ($key in @('explanation', 'rationale')) {
    if ($headerIndex.ContainsKey($key)) { $explanationCol = $headerIndex[$key]; break }
  }

  $questionCol = $null
  foreach ($key in @('question', 'prompt', 'questiontext')) {
    if ($headerIndex.ContainsKey($key)) { $questionCol = $headerIndex[$key]; break }
  }

  $optionCountCol = $null
  foreach ($key in @('optioncount', 'optionscount', 'totaloptions', 'choicecount')) {
    if ($headerIndex.ContainsKey($key)) { $optionCountCol = $headerIndex[$key]; break }
  }

  $items = New-Object System.Collections.Generic.List[object]

  for ($r = 2; $r -le $rowCount; $r++) {
    $imageCell = $used.Item($r, $imageCol).Text
    if ($null -eq $imageCell) { $imageCell = '' }
    $imageCode = $imageCell.Trim()

    $answerCell = $used.Item($r, $answerCol).Text
    if ($null -eq $answerCell) { $answerCell = '' }
    $answer = $answerCell.Trim().ToUpperInvariant()

    if ([string]::IsNullOrWhiteSpace($imageCode) -or [string]::IsNullOrWhiteSpace($answer)) {
      continue
    }

    if ($imageCode -notmatch '(\d+)$') {
      continue
    }

    $number = [int]$matches[1]
    if ($number -le 0) {
      continue
    }

    $imageAssetPath = "assets/Abstract Reasoning/Picture$number.png"

    $questionText = ''
    if ($null -ne $questionCol) {
      $questionCell = $used.Item($r, $questionCol).Text
      if ($null -eq $questionCell) { $questionCell = '' }
      $questionText = $questionCell.Trim()
    }

    $explanation = ''
    if ($null -ne $explanationCol) {
      $explanationCell = $used.Item($r, $explanationCol).Text
      if ($null -eq $explanationCell) { $explanationCell = '' }
      $explanation = $explanationCell.Trim()
    }

    $optionCount = $null
    if ($null -ne $optionCountCol) {
      $optionCountCell = $used.Item($r, $optionCountCol).Text
      if ($null -eq $optionCountCell) { $optionCountCell = '' }
      $optionCountRaw = $optionCountCell.Trim()
      $optionCount = Try-GetInt -Value $optionCountRaw
      if ($null -ne $optionCount -and $optionCount -lt 2) {
        $optionCount = $null
      }
    }

    $row = [ordered]@{
      number = $number
      question = $questionText
      imageAssetPath = $imageAssetPath
      answer = $answer
      explanation = $explanation
      category = 'Mental Ability / Abstract'
    }

    if ($null -ne $optionCount) {
      $row['optionCount'] = $optionCount
    }

    $items.Add([pscustomobject]$row)
  }

  $sorted = $items | Sort-Object { [int]$_.number }

  $payload = [ordered]@{
    category = 'Mental Ability / Abstract'
    questions = $sorted
  }

  $json = $payload | ConvertTo-Json -Depth 10

  $outputDir = Split-Path -Parent $OutputPath
  if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
  }

  Set-Content -Path $OutputPath -Value $json -Encoding UTF8

  Write-Output "Converted $($sorted.Count) visual questions to $OutputPath"
}
finally {
  if ($wb) { $wb.Close($false) | Out-Null }
  $excel.Quit()
  if ($used) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($used) }
  if ($ws) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws) }
  if ($wb) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) }
  [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
}
