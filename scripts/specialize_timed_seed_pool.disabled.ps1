param(
  [string]$OutFile = "assets/seed/initial_question_pool.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

throw @'
This legacy timed-mode seed specialization script has been disabled.

Reason:
- assets/seed/initial_question_pool.json is now a curated source of truth.
- Running this script would overwrite the curated pool with older generated timed-mode content.

If you need to update the seed pool, edit the curated asset directly or create a new reviewed workflow that writes to a different output file.
'@

. "$PSScriptRoot\upcat_seed_banks.ps1"

$readingComprehensionTimed = @(Get-UpcatReadingComprehensionBank)

function New-TimedQuestion {
  param(
    [int]$Number,
    [string]$Category,
    [string]$Question,
    [string]$Correct,
    [string[]]$Distractors,
    [string]$Explanation,
    [int]$Shift
  )

  $choices = @($Correct) + $Distractors
  $uniqueChoices = [System.Collections.Generic.List[string]]::new()
  foreach ($choice in $choices) {
    if (-not $uniqueChoices.Contains($choice)) {
      $uniqueChoices.Add($choice)
    }
  }
  if ($uniqueChoices.Count -ne 4) {
    throw "Question '$Question' does not have 4 unique choices."
  }

  $rotated = @()
  for ($i = 0; $i -lt 4; $i++) {
    $rotated += $uniqueChoices[($i + $Shift) % 4]
  }

  $answerIndex = $rotated.IndexOf($Correct)
  $answer = [string][char](65 + $answerIndex)

  [pscustomobject]@{
    number = $Number
    category = $Category
    question = $Question
    choices = $rotated
    answer = $answer
    explanation = $Explanation
    source = 'seed_pool_2027_timed'
  }
}

$timedBank = @{
  'Reading Comprehension' = @($readingComprehensionTimed | ForEach-Object { @{ q = "$(($_.q -replace '^Passage:\s*', '')) Timed RC"; c = $_.c; d = $_.d; e = $_.e } })
  'Language Proficiency' = @(
    @{ q='Synonym of rapid'; c='fast'; d=@('rough','late','narrow'); e='Rapid means fast.' },
    @{ q='Antonym of ancient'; c='modern'; d=@('silent','fragile','remote'); e='Ancient means old, so modern is the opposite.' },
    @{ q='Which sentence is correct?'; c='Each student has a notebook.'; d=@('Each student have a notebook.','Each students has a notebook.','Each student are with a notebook.'); e='The singular subject each student takes has.' },
    @{ q='Complete the sentence: The water was so ____ that we could see the pebbles below.'; c='clear'; d=@('loud','slow','heavy'); e='Clear fits the context of seeing through water.' },
    @{ q='Daily practice improves memory over time. Best paraphrase?'; c='Regular practice can strengthen memory.'; d=@('Memory disappears with practice.','Only long practice matters.','Practice and memory are unrelated.'); e='The sentence restates the same central idea.' },
    @{ q='Fill in the pronoun: The teacher spoke to Ana and ____.'; c='me'; d=@('I','mine','myself'); e='The pronoun is the object of to, so me is correct.' },
    @{ q='Pick the best transition: The rain stopped. ____, the game continued.'; c='Therefore'; d=@('However','Meanwhile','Instead'); e='Therefore shows that the game continued because the rain stopped.' },
    @{ q='Pick the correctly punctuated sentence.'; c='Yes, I finished the report.'; d=@('Yes I finished, the report.','Yes I, finished the report.','Yes; I finished, the report.'); e='The comma after Yes is correct.' },
    @{ q='Closest meaning of scarce'; c='limited'; d=@('bright','early','famous'); e='Scarce means limited or hard to find.' },
    @{ q='Sentence in active voice'; c='The captain led the team.'; d=@('The team was led by the captain.','The team had been led.','The team is being led.'); e='The subject captain performs the action in the active sentence.' },
    @{ q='Best opening sentence for a paragraph on recycling'; c='Recycling helps reduce waste and conserve resources.'; d=@('Bins come in many colors.','Plastic is light.','Some trucks are noisy.'); e='The sentence introduces the main idea clearly.' },
    @{ q='Choose the conjunction: Lea was tired, ____ she kept studying.'; c='but'; d=@('because','unless','so'); e='But shows contrast between being tired and continuing to study.' },
    @{ q='Carlo brought an umbrella and wore boots. The weather was likely'; c='rainy'; d=@('snowy','windless','fogless'); e='Umbrella and boots suggest rainy weather.' },
    @{ q='Choose the correctly capitalized sentence.'; c='We visited Manila in May.'; d=@('We visited manila in May.','We visited Manila in may.','We visited manila in may.'); e='Manila and May are proper nouns and should be capitalized.' },
    @{ q='Word that best completes: The class remained ____ during the speech.'; c='silent'; d=@('silence','silently','silencing'); e='Silent correctly describes the class.' },
    @{ q='The garden grew after regular watering and sunlight. Best summary?'; c='The garden improved with proper care.'; d=@('Gardens do not need water.','Sunlight harms plants.','Only watering matters.'); e='The summary captures the combined effect of care.' },
    @{ q='Best first step in an exam-prep paragraph'; c='First, make a study plan.'; d=@('Finally, review the answers.','Afterward, take a test.','Next, fix weak topics.'); e='First introduces the opening step clearly.' },
    @{ q='Antonym of generous'; c='selfish'; d=@('kind','gentle','helpful'); e='Generous is opposite in meaning to selfish.' },
    @{ q='Correct word: The results will ____ our decision.'; c='affect'; d=@('effect','defect','reflect'); e='Affect is the verb meaning influence.' },
    @{ q='Formal tone choice'; c='The findings require further review.'; d=@('The findings are super final.','The findings are kind of weird.','The findings totally end the issue.'); e='The sentence uses precise and formal wording.' },
    @{ q='Choose the sentence free of ambiguity.'; c='Rina told Bea that Rina would leave early.'; d=@('Rina told Bea that she would leave early.','She told Bea about leaving.','Leaving early was told by Rina.'); e='Repeating the name removes the unclear pronoun.' },
    @{ q='Transition word for contrast'; c='However'; d=@('Therefore','Similarly','Meanwhile'); e='However signals contrast.' },
    @{ q='Closest meaning of concise'; c='brief'; d=@('careful','unclear','joyful'); e='Concise means brief and direct.' },
    @{ q='Which sentence uses the semicolon correctly?'; c='The test was difficult; still, the class performed well.'; d=@('The test was difficult; because the class performed well.','The test was difficult, still; the class performed well.','The test was difficult; and still the class performed well.'); e='A semicolon before a conjunctive adverb is correct here.' },
    @{ q='Main purpose of steps in a manual'; c='to instruct'; d=@('to entertain','to confuse','to complain'); e='A manual gives instructions.' },
    @{ q='Correct sentence'; c='Neither of the answers is correct.'; d=@('Neither of the answers are correct.','Neither of the answers be correct.','Neither answers is correct.'); e='Neither is singular, so it takes is.' },
    @{ q='Complete the sentence: The witness gave a ____ reply with no extra detail.'; c='brief'; d=@('stormy','curious','heavy'); e='Brief matches the idea of a short reply.' },
    @{ q='Identify the adverb: She answered quickly.'; c='quickly'; d=@('She','answered','answer'); e='Quickly modifies the verb answered.' },
    @{ q='Best title for a paragraph about saving electricity at home'; c='Simple Ways to Use Less Electricity'; d=@('The Cost of Chairs','What Windows Look Like','A Short Story About Summer'); e='The title directly matches the topic.' },
    @{ q='Choose the clearest revision: The team met in order to discuss plans.'; c='The team met to discuss plans.'; d=@('The team met for discussing plans.','The team met in order plans discuss.','The team plans met to discuss.'); e='The revision is shorter and clearer.' }
  )
  'Mathematics' = @(
    @{ q='12 + 19 = ?'; c='31'; d=@('29','30','32'); e='Add 12 and 19 to get 31.' },
    @{ q='9 x 7 = ?'; c='63'; d=@('56','72','66'); e='Multiply 9 by 7 to get 63.' },
    @{ q='48 / 6 = ?'; c='8'; d=@('6','7','9'); e='48 divided by 6 is 8.' },
    @{ q='25% of 80 = ?'; c='20'; d=@('15','25','30'); e='One fourth of 80 is 20.' },
    @{ q='Solve: x + 11 = 18'; c='7'; d=@('6','8','9'); e='Subtract 11 from 18 to get 7.' },
    @{ q='Perimeter of a square with side 6 cm'; c='24 cm'; d=@('12 cm','18 cm','36 cm'); e='Perimeter of a square is 4 times the side length.' },
    @{ q='Area of a rectangle 9 cm by 4 cm'; c='36 sq cm'; d=@('18 sq cm','26 sq cm','40 sq cm'); e='Area = length x width = 36 sq cm.' },
    @{ q='Mean of 4, 6, 8'; c='6'; d=@('5','7','8'); e='The sum is 18 and 18 / 3 = 6.' },
    @{ q='Next term: 5, 10, 15, ?'; c='20'; d=@('18','19','25'); e='Add 5 each time.' },
    @{ q='3/4 + 1/4 = ?'; c='1'; d=@('1/2','3/8','5/4'); e='The fractions have the same denominator, so add the numerators.' },
    @{ q='A bus travels 120 km at 60 km/h. Time?'; c='2 hours'; d=@('1 hour','2.5 hours','3 hours'); e='Time = distance / speed = 120 / 60 = 2 hours.' },
    @{ q='10% of 250 = ?'; c='25'; d=@('20','15','35'); e='Ten percent is one tenth, so one tenth of 250 is 25.' },
    @{ q='7^2 = ?'; c='49'; d=@('14','42','56'); e='7 squared equals 49.' },
    @{ q='Slope from (1,2) to (3,6)'; c='2'; d=@('1','3','4'); e='Slope = (6 - 2) / (3 - 1) = 2.' },
    @{ q='A number divisible by 5 ends in'; c='0 or 5'; d=@('2 or 4','1 or 3','6 or 8'); e='Numbers divisible by 5 end in 0 or 5.' },
    @{ q='GCF of 12 and 18'; c='6'; d=@('3','4','9'); e='6 is the greatest common factor of 12 and 18.' },
    @{ q='LCM of 4 and 6'; c='12'; d=@('8','10','24'); e='12 is the least common multiple of 4 and 6.' },
    @{ q='Solve: 3x = 21'; c='7'; d=@('6','8','9'); e='Divide both sides by 3.' },
    @{ q='0.5 x 8 = ?'; c='4'; d=@('3','4.5','5'); e='Half of 8 is 4.' },
    @{ q='Midpoint of 2 and 10'; c='6'; d=@('5','7','8'); e='The midpoint is the average of the two numbers.' },
    @{ q='15% of 200 = ?'; c='30'; d=@('20','25','35'); e='0.15 x 200 = 30.' },
    @{ q='Triangle area with base 8 and height 5'; c='20 sq cm'; d=@('13 sq cm','40 sq cm','16 sq cm'); e='Area = 1/2 x 8 x 5 = 20 sq cm.' },
    @{ q='Circumference of a circle with radius 4 cm, pi = 3.14'; c='25.12 cm'; d=@('12.56 cm','28.26 cm','50.24 cm'); e='Circumference = 2 x pi x r = 2 x 3.14 x 4 = 25.12 cm.' },
    @{ q='Probability of heads on one fair coin toss'; c='1/2'; d=@('1/3','1/4','2/3'); e='A fair coin has two equally likely outcomes.' },
    @{ q='Next: 2, 4, 8, 16, ?'; c='32'; d=@('24','30','34'); e='Each term doubles.' },
    @{ q='If 5 notebooks cost PHP 100, one notebook costs'; c='PHP 20'; d=@('PHP 15','PHP 25','PHP 30'); e='100 / 5 = 20.' },
    @{ q='11 x 11 = ?'; c='121'; d=@('111','122','131'); e='11 multiplied by 11 is 121.' },
    @{ q='2.4 + 1.6 = ?'; c='4.0'; d=@('3.8','4.2','4.4'); e='Add the decimals to get 4.0.' },
    @{ q='A right angle measures'; c='90 degrees'; d=@('45 degrees','120 degrees','180 degrees'); e='A right angle is 90 degrees.' },
    @{ q='(6 + 2) / 4 = ?'; c='2'; d=@('1','3','4'); e='Add inside the parentheses first, then divide by 4.' }
  )
  'Science' = @(
    @{ q='Powerhouse of the cell'; c='mitochondrion'; d=@('nucleus','ribosome','chloroplast'); e='Mitochondria release usable energy from food.' },
    @{ q='Plants make food by'; c='photosynthesis'; d=@('respiration','digestion','evaporation'); e='Photosynthesis allows plants to make food using light energy.' },
    @{ q='Gas needed for breathing'; c='oxygen'; d=@('carbon dioxide','helium','hydrogen'); e='Humans need oxygen for respiration.' },
    @{ q='Force pulling objects to Earth'; c='gravity'; d=@('friction','magnetism','tension'); e='Gravity pulls objects toward Earth.' },
    @{ q='The red planet'; c='Mars'; d=@('Venus','Jupiter','Mercury'); e='Mars is known as the red planet.' },
    @{ q='Liquid water changes to vapor by'; c='evaporation'; d=@('condensation','freezing','melting'); e='Evaporation is the process where liquid becomes gas.' },
    @{ q='Part of the plant that absorbs water'; c='root'; d=@('leaf','flower','stem'); e='Roots absorb water and minerals from the soil.' },
    @{ q='A change of state from solid to liquid'; c='melting'; d=@('freezing','condensing','subliming'); e='Melting changes a solid into a liquid.' },
    @{ q='Center of the solar system'; c='Sun'; d=@('Earth','Moon','Mars'); e='The Sun is the star at the center of the solar system.' },
    @{ q='Organ that pumps blood'; c='heart'; d=@('lung','liver','kidney'); e='The heart pumps blood through the body.' },
    @{ q='A food chain starts with a'; c='producer'; d=@('consumer','predator','decomposer'); e='Producers make their own food and begin food chains.' },
    @{ q='The basic unit of life'; c='cell'; d=@('atom','organ','tissue'); e='Cells are the basic structural and functional units of life.' },
    @{ q='H2O is the formula for'; c='water'; d=@('oxygen','salt','hydrogen'); e='H2O is the chemical formula for water.' },
    @{ q='Blood vessels carrying blood away from heart'; c='arteries'; d=@('veins','capillaries','nerves'); e='Arteries carry blood away from the heart.' },
    @{ q='Earth rotates on its axis causing'; c='day and night'; d=@('seasons','eclipses','earthquakes'); e='Rotation causes alternating day and night.' },
    @{ q='Instrument for measuring temperature'; c='thermometer'; d=@('barometer','balance','ruler'); e='A thermometer measures temperature.' },
    @{ q='The process of breaking down food'; c='digestion'; d=@('circulation','respiration','excretion'); e='Digestion breaks food into simpler substances.' },
    @{ q='Metal spoon feels colder than wood because metal'; c='conducts heat faster'; d=@('has no temperature','is lighter','contains water'); e='Metal transfers heat away from the hand more quickly.' },
    @{ q='Animals that eat plants are'; c='herbivores'; d=@('carnivores','omnivores','decomposers'); e='Herbivores feed mainly on plants.' },
    @{ q='The layer of Earth we live on'; c='crust'; d=@('mantle','outer core','inner core'); e='The crust is the outer solid layer of Earth.' },
    @{ q='Acids have pH'; c='below 7'; d=@('above 7','equal to 14','equal to 10'); e='Acids have pH values below 7.' },
    @{ q='A magnet attracts'; c='iron'; d=@('wood','plastic','glass'); e='Magnets attract ferromagnetic materials such as iron.' },
    @{ q='The moon does not produce its own'; c='light'; d=@('gravity','motion','surface'); e='The moon reflects sunlight rather than producing its own light.' },
    @{ q='The part of the eye controlling amount of light'; c='iris'; d=@('retina','lens','cornea'); e='The iris controls the pupil size and amount of light entering the eye.' },
    @{ q='Water freezes at'; c='0 C'; d=@('10 C','50 C','100 C'); e='Pure water freezes at 0 degrees Celsius.' },
    @{ q='The gas plants take in for photosynthesis'; c='carbon dioxide'; d=@('oxygen','nitrogen','helium'); e='Plants use carbon dioxide during photosynthesis.' },
    @{ q='The human skeleton mainly provides'; c='support'; d=@('digestion','circulation','vision'); e='The skeleton supports and protects the body.' },
    @{ q='Lightning is a form of'; c='electricity'; d=@('magnetism','sound','gravity'); e='Lightning is a natural electrical discharge.' },
    @{ q='The phase change from gas to liquid'; c='condensation'; d=@('evaporation','melting','freezing'); e='Condensation is the change from gas to liquid.' },
    @{ q='A balanced diet helps the body stay'; c='healthy'; d=@('invisible','metallic','silent'); e='A balanced diet helps the body function properly and stay healthy.' }
  )
}

foreach ($entry in $timedBank.GetEnumerator()) {
  if ($entry.Value.Count -ne 30) {
    throw "Category '$($entry.Key)' must contain exactly 30 timed questions."
  }
}

$dataset = Get-Content -Raw $OutFile | ConvertFrom-Json
$timedMode = $dataset.modes | Where-Object { $_.mode -eq 'timedExam' } | Select-Object -First 1
if (-not $timedMode) { throw 'timedExam not found in dataset.' }

foreach ($categoryBlock in $timedMode.categories) {
  $categoryName = [string]$categoryBlock.category
  $prefix = @($categoryBlock.questions[0..29])
  $replacement = @()
  for ($i = 0; $i -lt 30; $i++) {
    $spec = $timedBank[$categoryName][$i]
    $replacement += New-TimedQuestion -Number (31 + $i) -Category $categoryName -Question $spec.q -Correct $spec.c -Distractors $spec.d -Explanation $spec.e -Shift ($i % 4)
  }
  $categoryBlock.questions = @($prefix + $replacement)
}

$json = $dataset | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText((Resolve-Path $OutFile), $json, [System.Text.UTF8Encoding]::new($false))
Write-Host 'Timed mode seed bank specialized successfully.'