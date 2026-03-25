param(
  [string]$Path = "assets/seed/initial_question_pool.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

throw @'
This legacy seed pruning script has been disabled.

Reason:
- assets/seed/initial_question_pool.json is now a curated source of truth.
- Running this script would mutate the curated pool using older automated pruning rules.

If you need to update the seed pool, edit the curated asset directly or create a new reviewed workflow that writes to a different output file.
'@

function Test-LooksCorruptedText {
  param([AllowNull()][string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $false
  }

  return $Text.Contains([char]0xFFFD) -or
    [regex]::IsMatch($Text, '\u00E2\u20AC') -or
    [regex]::IsMatch($Text, '[\u00C2\u00C3]')
}

function Test-TemplateQuestionText {
  param([string]$Text)

  $normalized = $Text.Trim().ToLowerInvariant()
  return $normalized.StartsWith('identify the key area being tested') -or
    $normalized.StartsWith('focus mode: pick the most precise key') -or
    $normalized.Contains('scenario emphasis:') -or
    $normalized.Contains('choose the best upcat-style answer') -or
    $normalized.Contains('which choice is most defensible') -or
    $normalized.Contains('select the strongest response') -or
    $normalized.Contains('identify the most accurate answer in this') -or
    $normalized.Contains('concise and speed-answerable') -or
    $normalized.EndsWith(' extra rc') -or
    $normalized.EndsWith(' focus rc') -or
    $normalized.EndsWith(' challenge rc') -or
    $normalized.EndsWith(' timed rc')
}

function Test-GenericTemplateExplanation {
  param([AllowNull()][string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $false
  }

  $normalized = $Text.Trim().ToLowerInvariant()
  return $normalized.Contains('directly matches the required') -and
    $normalized.Contains('target different concepts')
}

function Test-TrivialComputationQuestion {
  param([string]$Text)

  $normalized = $Text.Trim().ToLowerInvariant()
  return $normalized -match '^(compute\s+)?\d+(?:\.\d+)?\s*[\+\-x*/]\s*\d+(?:\.\d+)?\s*(?:=\s*\?)?\.?$' -or
    $normalized -match '^(compute\s+)?\d+/\d+\s*[\+\-x*/]\s*\d+/\d+\s*(?:=\s*\?)?\.?$'
}

function Test-UsableQuestion {
  param($Question)

  $questionText = [string]$Question.question
  if ([string]::IsNullOrWhiteSpace($questionText)) {
    return $false
  }

  if (Test-LooksCorruptedText $questionText) { return $false }
  if (Test-LooksCorruptedText ([string]$Question.explanation)) { return $false }
  if (Test-TemplateQuestionText $questionText) { return $false }
  if (Test-GenericTemplateExplanation ([string]$Question.explanation)) { return $false }
  if (Test-TrivialComputationQuestion $questionText) { return $false }

  foreach ($choice in @($Question.choices)) {
    if (Test-LooksCorruptedText ([string]$choice)) {
      return $false
    }
  }

  return $true
}

$json = Get-Content -Raw -Path $Path | ConvertFrom-Json

$removed = 0
$deduped = 0

foreach ($mode in @($json.modes)) {
  foreach ($category in @($mode.categories)) {
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $clean = New-Object System.Collections.ArrayList

    foreach ($question in @($category.questions)) {
      if (-not (Test-UsableQuestion $question)) {
        $removed++
        continue
      }

      $choiceKey = (@($question.choices) | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() }) -join '|'
      $fingerprint = ([string]$question.question).Trim().ToLowerInvariant() + '||' + $choiceKey

      if (-not $seen.Add($fingerprint)) {
        $deduped++
        continue
      }

      [void]$clean.Add($question)
    }

    for ($index = 0; $index -lt $clean.Count; $index++) {
      $clean[$index].number = $index + 1
    }

    $category.questions = $clean
  }
}

$json.total_questions = (@($json.modes) | ForEach-Object {
  @($_.categories) | ForEach-Object {
    @($_.questions).Count
  }
} | Measure-Object -Sum).Sum

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path $Path), ($json | ConvertTo-Json -Depth 100), $utf8NoBom)

Write-Host "Removed low-quality items: $removed"
Write-Host "Removed duplicate items: $deduped"
Write-Host "New total questions: $($json.total_questions)"