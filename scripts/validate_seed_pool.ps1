param(
  [string]$OutFile = "assets/seed/initial_question_pool.json",
  [switch]$FailOnWarnings,
  [int]$QuestionNumberMin = 1,
  [string[]]$SourceFilter = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Normalize-QuestionText {
  param([string]$Text)

  $normalized = $Text.ToLowerInvariant().Trim()
  $normalized = $normalized -replace '[^a-z0-9\s]', ' '
  $normalized = $normalized -replace '\s+', ' '
  return $normalized.Trim()
}

function Normalize-StemText {
  param([string]$Text)

  $normalized = $Text.ToLowerInvariant().Trim()
  $normalized = $normalized -replace '[0-9]+', '#'
  $normalized = $normalized -replace '[^a-z#\s]', ' '
  $normalized = $normalized -replace '\s+', ' '
  return $normalized.Trim()
}

function Get-StemKey {
  param([string]$Text)

  $normalized = Normalize-StemText $Text
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    return ''
  }

  $parts = @($normalized.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))
  $alphaParts = @($parts | Where-Object { $_ -match '[a-z]' })
  if ($alphaParts.Count -lt 2) {
    return ''
  }

  if ($parts.Count -le 4) {
    return ($parts -join ' ')
  }

  return (($parts[0..3]) -join ' ')
}

function Get-CaseSensitiveUniqueCount {
  param([string[]]$Values)

  $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  foreach ($value in $Values) {
    $null = $set.Add($value)
  }

  return $set.Count
}

function Contains-LinearCentimeterUnit {
  param([string]$Text)

  foreach ($match in [regex]::Matches($Text, '[0-9.]+\s*cm\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
    $start = [Math]::Max(0, $match.Index - 8)
    $prefix = $Text.Substring($start, $match.Index - $start).ToLowerInvariant()
    if ($prefix -notmatch '(sq\s*|square\s*|cubic\s*)$') {
      return $true
    }
  }

  return $false
}

$dataset = Get-Content -Raw $OutFile | ConvertFrom-Json
$issues = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

foreach ($mode in $dataset.modes) {
  foreach ($category in $mode.categories) {
    $normalizedQuestions = @{}
    $stemCounts = @{}

    foreach ($question in $category.questions) {
      if ([int]$question.number -lt $QuestionNumberMin) {
        continue
      }

      if ($SourceFilter.Count -gt 0 -and ([string]$question.source) -notin $SourceFilter) {
        continue
      }

      $label = "$($mode.mode)/$($category.category)/#$($question.number)"
      $choices = @($question.choices | ForEach-Object { [string]$_ })
      $uniqueChoiceCount = Get-CaseSensitiveUniqueCount $choices

      if ($choices.Count -ne 4) {
        $issues.Add("$label has $($choices.Count) choices instead of 4.")
      }

      if ($uniqueChoiceCount -ne $choices.Count) {
        $issues.Add("$label contains duplicate answer choices.")
      }

      if ([string]$question.answer -notin @('A', 'B', 'C', 'D')) {
        $issues.Add("$label has invalid answer key '$($question.answer)'.")
      }

      $normalizedQuestion = Normalize-QuestionText ([string]$question.question)
      if ($normalizedQuestions.ContainsKey($normalizedQuestion)) {
        $issues.Add("$label repeats the same normalized question as #$($normalizedQuestions[$normalizedQuestion]).")
      }
      else {
        $normalizedQuestions[$normalizedQuestion] = $question.number
      }

      $stemKey = Get-StemKey ([string]$question.question)
      if (-not [string]::IsNullOrWhiteSpace($stemKey)) {
        if ($stemCounts.ContainsKey($stemKey)) {
          $stemCounts[$stemKey] += 1
        }
        else {
          $stemCounts[$stemKey] = 1
        }
      }

      $questionText = [string]$question.question
      $explanationText = [string]$question.explanation
      $choiceText = $choices -join ' | '

      if ($questionText -match 'circumference') {
        if ($explanationText -match 'sq cm' -or $choiceText -match 'sq cm') {
          $issues.Add("$label uses square units for a circumference item.")
        }
      }

      if ($questionText -match '\barea\b') {
        if ((Contains-LinearCentimeterUnit $explanationText) -or (Contains-LinearCentimeterUnit $choiceText)) {
          $issues.Add("$label uses linear cm for an area item.")
        }
      }
    }

    foreach ($stem in $stemCounts.Keys) {
      if ($stemCounts[$stem] -ge 3) {
        $warnings.Add("$($mode.mode)/$($category.category) repeats stem '$stem' $($stemCounts[$stem]) times.")
      }
    }
  }
}

if ($issues.Count -gt 0) {
  Write-Host 'Seed pool validation failed:' -ForegroundColor Red
  foreach ($issue in $issues) {
    Write-Host "- $issue" -ForegroundColor Red
  }
}

if ($warnings.Count -gt 0) {
  Write-Host 'Seed pool validation warnings:' -ForegroundColor Yellow
  foreach ($warning in $warnings) {
    Write-Host "- $warning" -ForegroundColor Yellow
  }
}

if ($issues.Count -gt 0 -or ($FailOnWarnings -and $warnings.Count -gt 0)) {
  exit 1
}

Write-Host 'Seed pool validation passed.' -ForegroundColor Green