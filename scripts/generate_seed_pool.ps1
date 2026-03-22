param(
  [string]$OutFile = "assets/seed/initial_question_pool.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modes = @('randomQuiz', 'focusMode', 'challenge', 'timedMode')
$categories = @('Mental Ability', 'English', 'Mathematics', 'Science')
$questionsPerCategory = 30

$keyAreas = @{
  'Mental Ability' = @(
    'abstract pattern completion','figure series progression','number series increasing','number series decreasing','alternating number series','letter series progression','alphanumeric series','analogy word-based','analogy number-based','analogy figure-based','classification words','classification numbers','classification figures','odd one out words','odd one out numbers','odd one out figures','logical reasoning statements','syllogism basic','syllogism conclusion validity','coding letter shift','coding number pattern','coding mixed symbols','decoding patterns','directional reasoning simple','directional reasoning complex','spatial rotation','mirror images figures','paper folding prediction','matrix reasoning 2x2','matrix reasoning 3x3','sequence ordering events','ranking and ordering','venn diagram reasoning','cause and effect reasoning','assumption identification','conclusion drawing','statement evaluation','input-output pattern','symbol substitution','spatial relation mapping'
  )
  'English' = @(
    'reading main idea','reading supporting details','reading inference','reading tone','reading author purpose','vocabulary context clues','vocabulary synonym precision','vocabulary antonym precision','subject-verb agreement','verb tense consistency','pronoun reference','modifier placement','parallel structure','sentence completion','error identification grammar','error identification punctuation','capitalization rules','spelling recognition','paragraph organization','coherence and cohesion','transition logic','topic sentence identification','irrelevant sentence detection','sentence improvement','word usage precision','idiomatic expression use','figurative language inference','active and passive voice','direct and indirect speech','editing and revision choices','clause relationship analysis','tone consistency in paragraph','reference clarity','sentence combination strategy','reasoning from short passage','evidence-based conclusion','argument support evaluation','contextual meaning shift','logic of paragraph order','conciseness and clarity'
  )
  'Mathematics' = @(
    'integer operations','order of operations','fractions operations','decimal operations','percent increase and decrease','ratio and proportion','direct variation','inverse variation','mean median mode','linear equations','word problems linear models','inequalities','systems of equations','exponent laws','radical expressions','polynomial operations','factoring trinomials','quadratic equations','angles and lines','triangle properties','triangle similarity','quadrilateral properties','circle properties','perimeter and area','surface area and volume','coordinate distance and midpoint','slope and line equation','data interpretation tables','data interpretation graphs','probability basics','divisibility rules','lcm and gcf','arithmetic sequence','geometric sequence','work-rate problems','distance-speed-time','mixture problems','age problems','simple interest','estimation and rounding'
  )
  'Science' = @(
    'scientific method variables','experimental design validity','data interpretation in science','cell structure and function','mitosis and meiosis','basic genetics','dna and rna roles','human digestive system','human circulatory system','human respiratory system','human nervous system','homeostasis mechanisms','ecosystem interactions','food chains and webs','photosynthesis and respiration','matter classification','physical and chemical change','atomic structure basics','periodic trends basics','chemical bonding basics','chemical reactions types','balancing equations','solutions and concentration','acids and bases','motion and kinematics','force and newton laws','work energy power','heat and temperature','waves sound and light','electric circuits basics','magnetism basics','earth layers and processes','plate tectonics','earthquakes and volcanoes','weather and climate','water cycle and atmosphere','solar system basics','moon phases and eclipses','environmental conservation','scientific reasoning from evidence'
  )
}

$modeDirectives = @{
  'randomQuiz' = @{
    Label = 'Random Quiz'
    Difficulty = 'easy-to-medium'
    Style = 'broad coverage'
  }
  'focusMode' = @{
    Label = 'Focus Mode'
    Difficulty = 'medium-to-hard'
    Style = 'concept-focused'
  }
  'challenge' = @{
    Label = 'Challenge Mode'
    Difficulty = 'hard-to-very-hard'
    Style = 'multi-step reasoning'
  }
  'timedMode' = @{
    Label = 'Timed Mode'
    Difficulty = 'medium'
    Style = 'concise and speed-answerable'
  }
  'timedExam' = @{
    Label = 'Timed Mode'
    Difficulty = 'medium'
    Style = 'concise and speed-answerable'
  }
}

function To-TitleCase {
  param([string]$Text)
  return ($Text -split ' ' | ForEach-Object {
    if ($_.Length -le 1) { $_.ToUpper() } else { $_.Substring(0,1).ToUpper() + $_.Substring(1) }
  }) -join ' '
}

function Get-ModeDirective {
  param([string]$Mode)
  if ($modeDirectives.ContainsKey($Mode)) {
    return $modeDirectives[$Mode]
  }
  return @{
    Label = 'Practice Mode'
    Difficulty = 'medium'
    Style = 'balanced coverage'
  }
}

function New-Question {
  param(
    [int]$Number,
    [string]$Category,
    [string]$Mode,
    [string]$PrimaryTopic,
    [string[]]$DistractorTopics,
    [int]$TemplateIndex
  )

  $directive = Get-ModeDirective -Mode $Mode
  $label = $directive.Label
  $difficulty = $directive.Difficulty
  $style = $directive.Style

  $stemTemplates = @(
    "In a $label USTET $Category item ($difficulty), which option best addresses this case: ${PrimaryTopic}?",
    "Choose the strongest answer for this $label $Category scenario focused on ${PrimaryTopic} ($style).",
    "Select the most accurate response for a $difficulty USTET $Category item on ${PrimaryTopic} in $label.",
    "For this $label $Category prompt, identify the best answer that demonstrates ${PrimaryTopic}.",
    "Which option is most defensible in a $style $Category question centered on ${PrimaryTopic} ($label)?"
  )

  $question = $stemTemplates[$TemplateIndex % $stemTemplates.Count]

  $correctChoice = (To-TitleCase $PrimaryTopic)
  $choices = @(
    $correctChoice,
    (To-TitleCase $DistractorTopics[0]),
    (To-TitleCase $DistractorTopics[1]),
    (To-TitleCase $DistractorTopics[2])
  )

  # Deterministic rotation keeps answer letters distributed while preserving reproducibility.
  $shift = ($Number - 1) % 4
  $rotated = @()
  for ($i = 0; $i -lt 4; $i++) {
    $rotated += $choices[($i + $shift) % 4]
  }

  $answerIndex = 0
  for ($i = 0; $i -lt 4; $i++) {
    if ($rotated[$i] -eq $correctChoice) {
      $answerIndex = $i
      break
    }
  }

  $answer = [char](65 + $answerIndex)
  $explanation = "Option $answer is correct because it directly matches the required $Category competency on $PrimaryTopic for $label, while the other options target different concepts."

  return [ordered]@{
    number = $Number
    category = $Category
    question = $question
    choices = $rotated
    answer = [string]$answer
    explanation = $explanation
    source = 'seed_pool_2027'
  }
}

function Build-CategoryQuestions {
  param(
    [string]$Mode,
    [string]$Category,
    [int]$Count
  )

  $topics = $keyAreas[$Category]
  if (-not $topics -or $topics.Count -lt 4) {
    throw "Category '$Category' does not have enough key areas to build choices."
  }

  $items = @()
  for ($n = 1; $n -le $Count; $n++) {
    $idx = ($n - 1) % $topics.Count
    $primary = $topics[$idx]

    # Use spaced offsets so distractors differ from the primary topic.
    $d1 = $topics[($idx + 7) % $topics.Count]
    $d2 = $topics[($idx + 13) % $topics.Count]
    $d3 = $topics[($idx + 19) % $topics.Count]

    $items += New-Question `
      -Number $n `
      -Category $Category `
      -Mode $Mode `
      -PrimaryTopic $primary `
      -DistractorTopics @($d1, $d2, $d3) `
      -TemplateIndex $n
  }

  return $items
}

function Build-Dataset {
  $modeBlocks = @()

  foreach ($mode in $modes) {
    $categoryBlocks = @()

    foreach ($category in $categories) {
      $categoryBlocks += [ordered]@{
        category = $category
        questions = Build-CategoryQuestions -Mode $mode -Category $category -Count $questionsPerCategory
      }
    }

    $modeBlocks += [ordered]@{
      mode = $mode
      categories = $categoryBlocks
    }
  }

  return [ordered]@{
    exam = 'USTET'
    total_questions = ($modes.Count * $categories.Count * $questionsPerCategory)
    modes = $modeBlocks
  }
}

function Test-Dataset {
  param([hashtable]$Dataset)

  if ($Dataset.exam -ne 'USTET') {
    throw 'Validation failed: exam must be USTET.'
  }

  if ($Dataset.modes.Count -ne 4) {
    throw "Validation failed: expected 4 modes, found $($Dataset.modes.Count)."
  }

  $globalQuestions = New-Object System.Collections.Generic.HashSet[string]
  $totalCount = 0

  foreach ($modeBlock in $Dataset.modes) {
    $modeName = [string]$modeBlock.mode

    if ($modeBlock.categories.Count -ne 4) {
      throw "Validation failed: mode '$modeName' must contain 4 categories."
    }

    foreach ($categoryBlock in $modeBlock.categories) {
      $categoryName = [string]$categoryBlock.category
      $questions = @($categoryBlock.questions)

      if ($questions.Count -ne $questionsPerCategory) {
        throw "Validation failed: mode '$modeName' category '$categoryName' must have $questionsPerCategory questions, found $($questions.Count)."
      }

      foreach ($q in $questions) {
        $totalCount++

        if ($q.choices.Count -ne 4) {
          throw "Validation failed: mode '$modeName' category '$categoryName' question #$($q.number) does not have 4 choices."
        }

        if ($q.answer -notin @('A','B','C','D')) {
          throw "Validation failed: mode '$modeName' category '$categoryName' question #$($q.number) has invalid answer '$($q.answer)'."
        }

        $answerIndex = [int][char]$q.answer - [int][char]'A'
        if ($answerIndex -lt 0 -or $answerIndex -gt 3) {
          throw "Validation failed: answer index out of range for mode '$modeName' category '$categoryName' question #$($q.number)."
        }

        if ([string]::IsNullOrWhiteSpace($q.explanation)) {
          throw "Validation failed: missing explanation for mode '$modeName' category '$categoryName' question #$($q.number)."
        }

        $fingerprint = "$($q.question.Trim().ToLowerInvariant())||$($q.choices -join '|')"
        if (-not $globalQuestions.Add($fingerprint)) {
          throw "Validation failed: duplicate question detected in mode '$modeName' category '$categoryName' question #$($q.number)."
        }
      }
    }
  }

  if ($totalCount -ne 480) {
    throw "Validation failed: total questions must be 480, found $totalCount."
  }

  if ($Dataset.total_questions -ne 480) {
    throw "Validation failed: total_questions field must be 480, found $($Dataset.total_questions)."
  }
}

$dataset = Build-Dataset
Test-Dataset -Dataset $dataset

$target = Join-Path (Get-Location) $OutFile
$dir = Split-Path -Parent $target
if (!(Test-Path $dir)) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$dataset | ConvertTo-Json -Depth 14 | Set-Content -Path $target -Encoding UTF8
Write-Host "Wrote validated 480-question seed pool to $target"