param(
  [string]$OutFile = "assets/seed/initial_question_pool.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

throw @'
This legacy seed normalization script has been disabled.

Reason:
- assets/seed/initial_question_pool.json is now a curated source of truth.
- Running this script would rewrite the curated pool using older normalization rules.

If you need to update the seed pool, edit the curated asset directly or create a new reviewed workflow that writes to a different output file.
'@

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

$questionNormalizations = @(
  @{
    Pattern = '"question":\s+"Passage: Isinulat ng may-akda na .*? Ano ang ipinahihiwatig ng linyang ito\?"'
    Replacement = '"question":  "Passage: Isinulat ng may-akda na \"unti-unting kumapal ang katahimikan sa silid habang binabasa ang resulta.\" Ano ang ipinahihiwatig ng linyang ito?"'
  },
  @{
    Pattern = '"question":\s+"Isinulat ng may-akda na .*? Ano ang ipinahihiwatig ng linyang ito\? Focus RC"'
    Replacement = '"question":  "Isinulat ng may-akda na \"unti-unting kumapal ang katahimikan sa silid habang binabasa ang resulta.\" Ano ang ipinahihiwatig ng linyang ito? Focus RC"'
  },
  @{
    Pattern = '"question":\s+"Isinulat ng may-akda na .*? Ano ang ipinahihiwatig ng linyang ito\? Challenge RC"'
    Replacement = '"question":  "Isinulat ng may-akda na \"unti-unting kumapal ang katahimikan sa silid habang binabasa ang resulta.\" Ano ang ipinahihiwatig ng linyang ito? Challenge RC"'
  },
  @{
    Pattern = '"question":\s+"Isinulat ng may-akda na .*? Ano ang ipinahihiwatig ng linyang ito\? Timed RC"'
    Replacement = '"question":  "Isinulat ng may-akda na \"unti-unting kumapal ang katahimikan sa silid habang binabasa ang resulta.\" Ano ang ipinahihiwatig ng linyang ito? Timed RC"'
  },
  @{
    Pattern = '"question":\s+"Passage: The mayor speech promised .*?but the article notes that similar promises were made in the past with little follow-through\. How does the article mainly treat the promise\?"'
    Replacement = '"question":  "Passage: The mayor speech promised \"lasting reform,\" but the article notes that similar promises were made in the past with little follow-through. How does the article mainly treat the promise?"'
  },
  @{
    Pattern = '"question":\s+"The mayor speech promised .*?but the article notes that similar promises were made in the past with little follow-through\. How does the article mainly treat the promise\? Focus RC"'
    Replacement = '"question":  "The mayor speech promised \"lasting reform,\" but the article notes that similar promises were made in the past with little follow-through. How does the article mainly treat the promise? Focus RC"'
  },
  @{
    Pattern = '"question":\s+"The mayor speech promised .*?but the article notes that similar promises were made in the past with little follow-through\. How does the article mainly treat the promise\? Challenge RC"'
    Replacement = '"question":  "The mayor speech promised \"lasting reform,\" but the article notes that similar promises were made in the past with little follow-through. How does the article mainly treat the promise? Challenge RC"'
  },
  @{
    Pattern = '"question":\s+"The mayor speech promised .*?but the article notes that similar promises were made in the past with little follow-through\. How does the article mainly treat the promise\? Timed RC"'
    Replacement = '"question":  "The mayor speech promised \"lasting reform,\" but the article notes that similar promises were made in the past with little follow-through. How does the article mainly treat the promise? Timed RC"'
  },
  @{
    Pattern = '"question":\s+"The reviewer writes that the new textbook is .*? Which statement best captures the reviewer overall judgment\? Focus RC"'
    Replacement = '"question":  "The reviewer writes that the new textbook is \"ambitious, carefully organized, and occasionally too dense for beginners.\" Which statement best captures the reviewer overall judgment? Focus RC"'
  },
  @{
    Pattern = '"question":\s+"The reviewer writes that the new textbook is .*? Which statement best captures the reviewer overall judgment\? Challenge RC"'
    Replacement = '"question":  "The reviewer writes that the new textbook is \"ambitious, carefully organized, and occasionally too dense for beginners.\" Which statement best captures the reviewer overall judgment? Challenge RC"'
  },
  @{
    Pattern = '"question":\s+"The reviewer writes that the new textbook is .*? Which statement best captures the reviewer overall judgment\? Timed RC"'
    Replacement = '"question":  "The reviewer writes that the new textbook is \"ambitious, carefully organized, and occasionally too dense for beginners.\" Which statement best captures the reviewer overall judgment? Timed RC"'
  },
  @{
    Pattern = '"question":\s+".*?Hindi man agad nakita ang pagbabago, dahan-dahan naman itong naipon sa araw-araw na pagsisikap,.*? wika ng coach\. Ano ang pinakamalapit na kahulugan nito\? Focus RC"'
    Replacement = '"question":  "\"Hindi man agad nakita ang pagbabago, dahan-dahan naman itong naipon sa araw-araw na pagsisikap,\" wika ng coach. Ano ang pinakamalapit na kahulugan nito? Focus RC"'
  },
  @{
    Pattern = '"question":\s+".*?Hindi man agad nakita ang pagbabago, dahan-dahan naman itong naipon sa araw-araw na pagsisikap,.*? wika ng coach\. Ano ang pinakamalapit na kahulugan nito\? Challenge RC"'
    Replacement = '"question":  "\"Hindi man agad nakita ang pagbabago, dahan-dahan naman itong naipon sa araw-araw na pagsisikap,\" wika ng coach. Ano ang pinakamalapit na kahulugan nito? Challenge RC"'
  },
  @{
    Pattern = '"question":\s+".*?Hindi man agad nakita ang pagbabago, dahan-dahan naman itong naipon sa araw-araw na pagsisikap,.*? wika ng coach\. Ano ang pinakamalapit na kahulugan nito\? Timed RC"'
    Replacement = '"question":  "\"Hindi man agad nakita ang pagbabago, dahan-dahan naman itong naipon sa araw-araw na pagsisikap,\" wika ng coach. Ano ang pinakamalapit na kahulugan nito? Timed RC"'
  },
  @{
    Pattern = '"question":\s+"The writer describes the volunteer clinic as .*? What is the meaning of the statement\? Focus RC"'
    Replacement = '"question":  "The writer describes the volunteer clinic as \"small in size but large in reach.\" What is the meaning of the statement? Focus RC"'
  },
  @{
    Pattern = '"question":\s+"The writer describes the volunteer clinic as .*? What is the meaning of the statement\? Challenge RC"'
    Replacement = '"question":  "The writer describes the volunteer clinic as \"small in size but large in reach.\" What is the meaning of the statement? Challenge RC"'
  },
  @{
    Pattern = '"question":\s+"The writer describes the volunteer clinic as .*? What is the meaning of the statement\? Timed RC"'
    Replacement = '"question":  "The writer describes the volunteer clinic as \"small in size but large in reach.\" What is the meaning of the statement? Timed RC"'
  }
)

foreach ($normalization in $questionNormalizations) {
  $raw = [regex]::Replace($raw, $normalization.Pattern, $normalization.Replacement)
}

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