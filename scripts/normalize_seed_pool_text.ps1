param(
  [string]$OutFile = "assets/seed/initial_question_pool.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$path = Resolve-Path $OutFile
$raw = [System.IO.File]::ReadAllText($path)

$raw = [regex]::Replace(
  $raw,
  '"question":\s+"What is ([0-9]+) .*? ([0-9]+)\?"',
  '"question":  "What is $1 x $2?"'
)

$raw = [regex]::Replace(
  $raw,
  '"question":\s+"Using .*? = 3\.14, what is the circumference of a circle with radius ([0-9]+) cm\?"',
  '"question":  "Using pi = 3.14, what is the circumference of a circle with radius $1 cm?"'
)

$raw = [regex]::Replace(
  $raw,
  '"explanation":\s+"Circumference is 2.*?r = 2 .*? 3\.14 .*? ([0-9]+) = ([0-9.]+) cm\."',
  '"explanation":  "Circumference is 2 x pi x $1 = $2 cm."'
)

$raw = [regex]::Replace(
  $raw,
  '"explanation":\s+"Area of a rectangle is length .*? width = ([0-9.]+) cm.*?\."',
  '"explanation":  "Area of a rectangle is length x width = $1 sq cm."'
)

$raw = [regex]::Replace(
  $raw,
  '"explanation":\s+"Time = distance .*? speed = ([0-9.]+) .*? ([0-9.]+) = ([0-9.]+) hours\."',
  '"explanation":  "Time = distance / speed = $1 / $2 = $3 hours."'
)

$raw = [regex]::Replace(
  $raw,
  '"([0-9.]+) cm.*?"',
  '"$1 sq cm"'
)

$raw = $raw -replace 'sq sq cm', 'sq cm'

$dataset = $raw | ConvertFrom-Json
foreach ($mode in $dataset.modes) {
  foreach ($category in $mode.categories) {
    foreach ($question in $category.questions) {
      $isCircumferenceQuestion = $question.question -match 'circumference'
      $isSquareUnitQuestion =
        $question.question -match 'area of a rectangle' -or
        $question.question -match 'area of a triangle' -or
        $question.question -match 'area of a sector' -or
        $question.question -match 'volume'

      if ($isCircumferenceQuestion) {
        $question.choices = @(
          $question.choices | ForEach-Object {
            ([string]$_) -replace '\s*sq cm$', ' cm'
          }
        )
        $question.explanation = ([string]$question.explanation) -replace '\s*sq cm([.])', ' cm$1'
      }

      if ($isSquareUnitQuestion) {
        $question.choices = @(
          $question.choices | ForEach-Object {
            if ([string]$_ -match '^[0-9.]+ cm$') {
              ([string]$_) -replace ' cm$', ' sq cm'
            }
            else {
              [string]$_
            }
          }
        )
        $question.explanation = ([string]$question.explanation) -replace '([0-9.]+) (?<!sq )cm\.', '$1 sq cm.'
      }
    }
  }
}

$raw = $dataset | ConvertTo-Json -Depth 100
$raw = $raw -replace 'sq\s+sq cm', 'sq cm'

[System.IO.File]::WriteAllText($path, $raw, [System.Text.UTF8Encoding]::new($false))

$null = Get-Content -Raw $path | ConvertFrom-Json
Write-Host 'Seed pool text normalized successfully.'