param(
  [string]$OutFile = "assets/seed/initial_question_pool.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-Question {
  param(
    [int]$Number,
    [string]$Category,
    [string]$Question,
    [string[]]$Choices,
    [string]$Answer,
    [string]$Explanation
  )

  return [ordered]@{
    number = $Number
    category = $Category
    question = $Question
    choices = $Choices
    answer = $Answer
    explanation = $Explanation
    source = 'seed_pool_2027'
  }
}

function New-LanguageQuestions {
  param([int]$Count, [string]$Mode)

  $items = @()
  $topics = @(
    @{ stem = 'The principal reminded the students to submit ____ projects before Friday.'; good = 'their'; bad = @('there','they are','them') ; exp='The possessive pronoun their correctly shows ownership of projects.' },
    @{ stem = 'Neither of the proposals ____ acceptable to the committee.'; good = 'is'; bad = @('are','were','have been') ; exp='Neither is singular and takes the singular verb is.' },
    @{ stem = 'Choose the best transition: The roads were flooded; ____, classes were suspended.'; good = 'therefore'; bad = @('however','meanwhile','likewise') ; exp='Therefore correctly signals a result or consequence.' },
    @{ stem = 'Select the closest meaning of concise in an academic paragraph.'; good = 'brief but complete'; bad = @('overly emotional','unclear and vague','excessively repetitive') ; exp='Concise writing is brief while preserving essential meaning.' },
    @{ stem = 'The team of researchers ____ presenting its findings today.'; good = 'is'; bad = @('are','were','have') ; exp='Team is treated as a singular collective noun in this sentence.' },
    @{ stem = 'Identify the clearest revision: Because of the fact that it rained, the event was delayed.'; good = 'Because it rained, the event was delayed.'; bad = @('Due to rain, delay happened for the event in general.','The event, it was delayed because rain happened.','Because of raining, the event had delayed itself.') ; exp='The best revision removes wordiness while keeping meaning precise.' },
    @{ stem = 'Choose the correct pronoun reference: When Ana spoke to Bea, ____ smiled politely.'; good = 'Ana smiled politely.'; bad = @('she smiled politely.','her smiled politely.','they smiles politely.') ; exp='Replacing ambiguous pronouns with a noun removes unclear reference.' },
    @{ stem = 'Select the correct parallel structure.'; good = 'The review covered grammar, logic, and organization.'; bad = @('The review covered grammar, to reason, and organization.','The review covered grammar, logic, and to organize.','The review covered to check grammar, logic, and organization.') ; exp='Parallel items must share the same grammatical form.' },
    @{ stem = 'Pick the sentence with correct punctuation for an introductory phrase.'; good = 'After the simulation, the class discussed common errors.'; bad = @('After the simulation the class, discussed common errors.','After, the simulation the class discussed common errors.','After the simulation the class discussed, common errors.') ; exp='A comma follows a nontrivial introductory phrase.' },
    @{ stem = 'Choose the best word: The witness gave a ____ account that included time, place, and sequence.'; good = 'detailed'; bad = @('vague','casual','brief') ; exp='Detailed is appropriate when many specific facts are provided.' }
  )

  for ($i = 1; $i -le $Count; $i++) {
    $t = $topics[($i - 1) % $topics.Count]
    $difficultyTag = switch ($Mode) {
      'randomQuiz' { '' }
      'focusMode' { ' Choose the most precise academic option.' }
      'challenge' { ' Consider subtle grammar and register differences before selecting.' }
      default { '' }
    }

    $question = $t.stem + $difficultyTag
    $choices = @($t.good) + $t.bad

    # Rotate correct position for balanced answer letters.
    $shift = ($i - 1) % 4
    $rot = @()
    for ($k = 0; $k -lt 4; $k++) {
      $rot += $choices[($k + $shift) % 4]
    }

    $answerIdx = 0
    for ($k = 0; $k -lt 4; $k++) {
      if ($rot[$k] -eq $t.good) { $answerIdx = $k; break }
    }
    $answer = [char](65 + $answerIdx)

    $items += New-Question -Number $i -Category 'Language Proficiency' -Question $question -Choices $rot -Answer $answer -Explanation $t.exp
  }

  return $items
}

function New-ReadingQuestions {
  param([int]$Count, [string]$Mode)

  $items = @()
  $passages = @(
    @{ p = 'A coastal town replaced single-use plastic bags with reusable sacks sold at a minimal cost. After six months, waste audits showed fewer plastic fragments in drainage canals, while local stores reported stable sales. Some residents initially resisted the change, but community workshops on flood prevention improved participation.'; q='What is the main idea of the passage?'; a='A low-cost policy plus community education improved compliance and reduced waste.'; d=@('Store sales fell because reusable sacks were expensive.','Flooding increased after reusable sacks were introduced.','Residents accepted the policy immediately without resistance.'); e='The passage emphasizes policy implementation and education leading to environmental improvement.' },
    @{ p = 'During exam season, a school opened an early study hall with peer tutors. Attendance rose steadily, but only students who attended at least three sessions each week showed significant gains in mock-test scores. Administrators then shifted from broad announcements to targeted reminders for low-attendance groups.'; q='Which inference is best supported?'; a='Frequency of participation mattered more than mere availability of support.'; d=@('Any student who entered the hall once improved significantly.','Targeted reminders were unnecessary after attendance rose.','Peer tutoring reduced the need for mock tests.'); e='Score gains were linked to sustained participation, not one-time attendance.' },
    @{ p = 'A barangay introduced a bike lane near two public schools. Traffic volume remained high at rush hour, yet travel time for short trips decreased because more students cycled. Parents requested additional crossings, arguing that lane markings alone did not address intersections with heavy turning vehicles.'; q='What problem remains unresolved?'; a='Intersection safety still needs measures beyond painted lanes.'; d=@('Cycling caused longer travel times for short trips.','The bike lane eliminated rush-hour congestion entirely.','Parents opposed all forms of active transport.'); e='The passage states that intersection risk persists despite lane markings.' },
    @{ p = 'A science club compared two methods for watering seedlings: fixed schedules and moisture-sensor triggers. Sensor-based watering used less water and produced similar plant height after four weeks. The club concluded that scheduling by soil condition can maintain growth while conserving resources.'; q='Which statement is most strongly supported?'; a='Condition-based watering can improve efficiency without harming growth outcomes.'; d=@('Fixed schedules always waste water and reduce plant height.','Sensor devices are unnecessary in all school gardens.','Plant growth depends only on fertilizer, not watering method.'); e='The reported data showed comparable growth with lower water use under sensors.' },
    @{ p = 'A reading teacher replaced weekly vocabulary lists with short context-rich passages. Students still learned target words, and retention after one month improved. The teacher noted that learners used clues from surrounding sentences to confirm meaning, especially when words had multiple senses.'; q='Why did retention likely improve?'; a='Students encoded meaning through contextual use rather than isolated memorization.'; d=@('Students memorized longer lists each week than before.','Multiple meanings made words easier to forget quickly.','Context reduced reading time but not understanding.'); e='Contextual learning links words to use, which supports longer retention.' }
  )

  for ($i = 1; $i -le $Count; $i++) {
    $t = $passages[($i - 1) % $passages.Count]
    $difficultyLine = switch ($Mode) {
      'randomQuiz' { '' }
      'focusMode' { ' Select the option that best follows from explicit evidence in the passage.' }
      'challenge' { ' Choose the strongest evidence-based inference while eliminating plausible but unsupported claims.' }
      default { '' }
    }

    $questionText = "Passage: $($t.p) `n`n$($t.q)$difficultyLine"
    $choices = @($t.a) + $t.d
    $shift = ($i - 1) % 4
    $rot = @()
    for ($k = 0; $k -lt 4; $k++) { $rot += $choices[($k + $shift) % 4] }
    $answerIdx = 0
    for ($k = 0; $k -lt 4; $k++) { if ($rot[$k] -eq $t.a) { $answerIdx = $k; break } }
    $answer = [char](65 + $answerIdx)

    $items += New-Question -Number $i -Category 'Reading Comprehension' -Question $questionText -Choices $rot -Answer $answer -Explanation $t.e
  }

  return $items
}

function New-MathQuestions {
  param([int]$Count, [string]$Mode)

  $items = @()

  for ($i = 1; $i -le $Count; $i++) {
    $type = ($i - 1) % 5
    $question = ''
    $correct = ''
    $distractors = @()
    $exp = ''

    switch ($type) {
      0 {
        $a = 8 + ($i % 7)
        $b = 3 + ($i % 5)
        $c = 2 + ($i % 4)
        $value = ($a * $b) - $c
        $question = "Evaluate $a($b) - $c."
        $correct = "$value"
        $distractors = @("$($value + 2)","$($value - 3)","$($a + $b + $c)")
        $exp = 'Apply multiplication first, then subtraction.'
      }
      1 {
        $x = 2 + ($i % 6)
        $left = 3 * $x + 5
        $question = "Solve for x: 3x + 5 = $left."
        $correct = "$x"
        $distractors = @("$($x+1)","$($x-1)","$($x+2)")
        $exp = 'Subtract 5 from both sides, then divide by 3.'
      }
      2 {
        $n = 4 + ($i % 8)
        $value = $n * $n
        $question = "What is $n squared?"
        $correct = "$value"
        $distractors = @("$($value + $n)","$($value - $n)","$($n*2)")
        $exp = 'Squaring means multiplying the number by itself.'
      }
      3 {
        $a = 12 + ($i % 9)
        $b = 3 + ($i % 4)
        $q = [math]::Floor($a / $b)
        $r = $a % $b
        $question = "When $a is divided by $b, what is the remainder?"
        $correct = "$r"
        $distractors = @("$($b-$r)","$q","$($r+1)")
        $exp = 'Use division algorithm: dividend = divisor × quotient + remainder.'
      }
      default {
        $base = 15 + ($i % 10)
        $pct = 10 + (5 * ($i % 3))
        $inc = [math]::Round($base * $pct / 100,2)
        $new = [math]::Round($base + $inc,2)
        $question = "A value of $base increases by $pct percent. What is the new value?"
        $correct = "$new"
        $distractors = @("$([math]::Round($base + $pct,2))","$([math]::Round($base - $inc,2))","$([math]::Round($inc,2))")
        $exp = 'Compute percent change first, then add it to the original value.'
      }
    }

    if ($Mode -eq 'challenge') {
      $question += ' Choose the most accurate result.'
    } elseif ($Mode -eq 'focusMode') {
      $question += ' Show strong command of operations and numerical reasoning.'
    }

    $choices = @($correct) + $distractors
    $shift = ($i - 1) % 4
    $rot = @()
    for ($k = 0; $k -lt 4; $k++) { $rot += $choices[($k + $shift) % 4] }
    $answerIdx = 0
    for ($k = 0; $k -lt 4; $k++) { if ($rot[$k] -eq $correct) { $answerIdx = $k; break } }
    $answer = [char](65 + $answerIdx)

    $items += New-Question -Number $i -Category 'Mathematics' -Question $question -Choices $rot -Answer $answer -Explanation $exp
  }

  return $items
}

function New-ScienceQuestions {
  param([int]$Count, [string]$Mode)

  $items = @()
  $bank = @(
    @{q='Which process directly converts liquid water into water vapor at normal temperatures?'; a='evaporation'; d=@('condensation','freezing','deposition'); e='Evaporation is the phase change from liquid to gas.'},
    @{q='If the net force on an object is zero, what can be concluded?'; a='Its velocity is constant, which may include rest.'; d=@('It must be moving in a circle.','Its mass is increasing over time.','Its acceleration is always positive.'); e='Zero net force means zero acceleration, so velocity stays constant.'},
    @{q='Which organelle is primarily responsible for energy release in eukaryotic cells?'; a='mitochondrion'; d=@('ribosome','golgi body','nucleus'); e='Cellular respiration mainly occurs in mitochondria.'},
    @{q='What happens to current in a simple circuit if resistance increases while voltage is fixed?'; a='Current decreases.'; d=@('Current increases.','Current stays exactly the same always.','Current changes direction automatically.'); e='By Ohms law I = V/R, larger resistance gives smaller current.'},
    @{q='Why do seasons occur on Earth?'; a='Earths axis is tilted relative to its orbit around the Sun.'; d=@('Earth is much closer to the Sun in summer everywhere.','The Sun changes size every quarter.','Cloud cover alone determines global seasons.'); e='Seasonal sunlight angle and duration are controlled by axial tilt.'},
    @{q='In a food web, what is the primary role of decomposers?'; a='They recycle nutrients from dead matter back into ecosystems.'; d=@('They create sunlight for producers.','They eliminate all predators permanently.','They convert herbivores directly into producers.'); e='Decomposers break down remains and return nutrients to soil and water.'},
    @{q='When an acid reacts with a base in neutralization, one common product is'; a='water'; d=@('chlorophyll','ozone','methane only'); e='Acid-base neutralization commonly forms water and a salt.'},
    @{q='Which statement best describes plate tectonics?'; a='Earths lithosphere is divided into moving plates.'; d=@('The mantle is rigid and completely motionless.','Only continents move while oceans stay fixed.','Earthquake activity is unrelated to plate boundaries.'); e='Plate motion explains major geologic activity including quakes and volcanism.'},
    @{q='What is the best reason metals are used for electrical wiring?'; a='They have many mobile electrons that allow charge flow.'; d=@('They are always nonreactive in all environments.','They cannot conduct heat at all.','They increase circuit resistance by default.'); e='Electrical conductivity in metals comes from delocalized electrons.'},
    @{q='In an experiment, why is a control group important?'; a='It provides a baseline for comparison with the treatment group.'; d=@('It guarantees the hypothesis is true.','It removes the need for repeated trials.','It prevents all measurement error completely.'); e='Controls help isolate the effect of the tested variable.'}
  )

  for ($i = 1; $i -le $Count; $i++) {
    $t = $bank[($i - 1) % $bank.Count]
    $question = $t.q
    if ($Mode -eq 'challenge') {
      $question += ' Select the strongest scientific explanation.'
    } elseif ($Mode -eq 'focusMode') {
      $question += ' Base your choice on mechanism, not memorized labels.'
    }

    $choices = @($t.a) + $t.d
    $shift = ($i - 1) % 4
    $rot = @()
    for ($k = 0; $k -lt 4; $k++) { $rot += $choices[($k + $shift) % 4] }
    $answerIdx = 0
    for ($k = 0; $k -lt 4; $k++) { if ($rot[$k] -eq $t.a) { $answerIdx = $k; break } }
    $answer = [char](65 + $answerIdx)

    $items += New-Question -Number $i -Category 'Science' -Question $question -Choices $rot -Answer $answer -Explanation $t.e
  }

  return $items
}

function Build-Pool {
  param([string]$Mode,[string]$Category,[int]$Count)

  $questions = switch ($Category) {
    'Language Proficiency' { New-LanguageQuestions -Count $Count -Mode $Mode }
    'Reading Comprehension' { New-ReadingQuestions -Count $Count -Mode $Mode }
    'Mathematics' { New-MathQuestions -Count $Count -Mode $Mode }
    'Science' { New-ScienceQuestions -Count $Count -Mode $Mode }
    default { throw "Unsupported category: $Category" }
  }

  return [ordered]@{
    mode = $Mode
    category = $Category
    questions = $questions
  }
}

$modes = @('randomQuiz','focusMode','challenge')
$categories = @('Language Proficiency','Reading Comprehension','Mathematics','Science')

$pools = @()
foreach ($m in $modes) {
  foreach ($c in $categories) {
    $pools += Build-Pool -Mode $m -Category $c -Count 30
  }
}

$payload = [ordered]@{
  schema = 'seed_pool_v1'
  generatedAt = (Get-Date).ToString('o')
  pools = $pools
}

$target = Join-Path (Get-Location) $OutFile
$dir = Split-Path -Parent $target
if (!(Test-Path $dir)) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$payload | ConvertTo-Json -Depth 12 | Set-Content -Path $target -Encoding UTF8
Write-Host "Wrote seed pool to $target"
