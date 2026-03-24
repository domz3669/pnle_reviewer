param(
  [string]$OutFile = "assets/seed/initial_question_pool.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Format-FocusPrompt {
  param([string]$Question)

  $clean = $Question.Trim()
  $clean = $clean -replace '^(Diagnostic set:\s*|Mixed diagnostic:\s*)', ''
  $clean = $clean -replace '^Diagnostic [^:]+:\s*', ''
  $clean = $clean -replace '^Focus on [^:]+:\s*', ''
  $clean = $clean -replace '^Focus [^:]+:\s*', ''

  if ($clean.Length -gt 0) {
    $clean = $clean.Substring(0, 1).ToUpper() + $clean.Substring(1)
  }

  return $clean
}

function New-FocusQuestion {
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
    question = Format-FocusPrompt $Question
    choices = $rotated
    answer = $answer
    explanation = $Explanation
    source = 'seed_pool_2027_focus'
  }
}

$focusBank = @{
  'Mental Ability' = @(
    @{ q='Diagnostic set: identify the rule. 4, 8, 12, 16, ?'; c='20'; d=@('18','22','24'); e='This sequence uses a constant addition rule of +4.' },
    @{ q='Diagnostic set: identify the rule. 81, 27, 9, ?'; c='3'; d=@('6','1','12'); e='This sequence uses repeated division by 3.' },
    @{ q='Diagnostic set: odd-one-out among dog, cat, eagle, horse'; c='eagle'; d=@('dog','cat','horse'); e='The task checks classification: eagle is a bird while the others are mammals.' },
    @{ q='Diagnostic set: book is to reading as piano is to'; c='music'; d=@('wood','bench','keys'); e='The item checks simple analogy by matching object to purpose.' },
    @{ q='Diagnostic set: if BAD becomes CBE, then MAP becomes'; c='NBQ'; d=@('MBQ','NCQ','NAP'); e='The code adds one to each letter, so M-A-P becomes N-B-Q.' },
    @{ q='Diagnostic set: north, east, south, ?'; c='west'; d=@('north','left','right'); e='The item checks ordered directions in clockwise sequence.' },
    @{ q='Diagnostic set: all pencils are tools. Which conclusion is valid?'; c='Some tools may be pencils.'; d=@('All tools are pencils.','No pencils are tools.','Every tool is made of wood.'); e='This tests cautious logical inference from a class statement.' },
    @{ q='Diagnostic set: next pair after A1, C3, E5 is'; c='G7'; d=@('F6','G6','H7'); e='The letters and numbers both increase by two.' },
    @{ q='Diagnostic set: choose the strongest pattern, 2, 5, 8, 11, ?'; c='14'; d=@('13','15','16'); e='The sequence checks recognition of a constant +3 rule.' },
    @{ q='Diagnostic set: who is youngest if Lea is older than Mia and Mia is older than Nia?'; c='Nia'; d=@('Lea','Mia','Cannot be known'); e='This checks ranking and ordering from chained comparisons.' },
    @{ q='Focus on coding: TREE with +1 code becomes'; c='USFF'; d=@('TRFD','UTFF','USFE'); e='Each letter advances one step forward.' },
    @{ q='Focus on coding: HOME with +2 code becomes'; c='JQOG'; d=@('IQNF','JPNG','KQOF'); e='Each letter advances two places: H to J, O to Q, M to O, E to G.' },
    @{ q='Focus on direction: face east then turn left. Final direction?'; c='north'; d=@('south','west','east'); e='A left turn from east points north.' },
    @{ q='Focus on direction: face south then turn right. Final direction?'; c='west'; d=@('east','north','south'); e='A right turn from south points west.' },
    @{ q='Focus on analogy: nest is to bird as den is to'; c='bear'; d=@('leaf','tree','fish'); e='A nest is a bird dwelling, just as a den is a bear dwelling.' },
    @{ q='Focus on analogy: key is to lock as password is to'; c='account'; d=@('screen','paper','mouse'); e='Both unlock access to something.' },
    @{ q='Focus on classification: which does not belong, mango, banana, carrot, apple'; c='carrot'; d=@('mango','banana','apple'); e='The item checks grouping: carrot is a vegetable while the others are fruits.' },
    @{ q='Focus on classification: which does not belong, triangle, square, circle, rectangle'; c='circle'; d=@('triangle','square','rectangle'); e='The item checks polygon recognition; circle has no sides.' },
    @{ q='Focus on logic: all roses are flowers. Which statement must be true?'; c='Some flowers can be roses.'; d=@('All flowers are roses.','No roses are flowers.','All roses are trees.'); e='This checks whether the learner distinguishes necessary from reversible statements.' },
    @{ q='Focus on logic: some players are singers. Which statement follows?'; c='Some singers are players.'; d=@('All singers are players.','No player is a singer.','All players are singers.'); e='The statement can be restated by switching the group order.' },
    @{ q='Pattern focus: 1, 4, 9, 16, ?'; c='25'; d=@('20','24','36'); e='This tests recognition of perfect squares.' },
    @{ q='Pattern focus: 3, 6, 12, 24, ?'; c='48'; d=@('36','42','54'); e='This tests repeated doubling.' },
    @{ q='Ranking focus: Ana finished ahead of Ben, and Ben ahead of Cara. Who is first?'; c='Ana'; d=@('Ben','Cara','Cannot be known'); e='The ordering clue places Ana at the top.' },
    @{ q='Ranking focus: D is taller than C, C taller than B, and B taller than A. Who is second tallest?'; c='C'; d=@('D','B','A'); e='The ranking order is D, C, B, A.' },
    @{ q='Mixed diagnostic: next letter after D, G, J is'; c='M'; d=@('K','L','N'); e='The letters increase by three positions.' },
    @{ q='Mixed diagnostic: next number after 50, 45, 40 is'; c='35'; d=@('34','36','30'); e='The sequence decreases by 5.' },
    @{ q='Mixed diagnostic: brother is to sister as uncle is to'; c='aunt'; d=@('cousin','niece','grandmother'); e='The item checks male-female relationship matching.' },
    @{ q='Mixed diagnostic: glove is to hand as sock is to'; c='foot'; d=@('shoe','toe','leg'); e='The relationship is item to body part covered.' },
    @{ q='Mixed diagnostic: if mark is 5th from the left in a line of 11, he is __ from the right'; c='7th'; d=@('5th','6th','8th'); e='From the right, the position is 11 - 5 + 1 = 7.' },
    @{ q='Mixed diagnostic: which should come next, Monday, Wednesday, Friday, ?'; c='Sunday'; d=@('Saturday','Thursday','Tuesday'); e='The pattern skips one day each time.' }
  )
  'English' = @(
    @{ q='Diagnostic grammar: choose the correct verb. Each of the books ___ on the shelf.'; c='is'; d=@('are','were','have'); e='The head word each is singular, so the correct verb is is.' },
    @{ q='Diagnostic grammar: choose the correct pronoun. The adviser thanked Paolo and ___.'; c='me'; d=@('I','mine','myself'); e='The pronoun is the object of thanked, so me is correct.' },
    @{ q='Diagnostic vocabulary: synonym of cautious'; c='careful'; d=@('noisy','rapid','joyful'); e='Careful is the closest synonym of cautious.' },
    @{ q='Diagnostic vocabulary: antonym of expand'; c='shrink'; d=@('grow','stretch','widen'); e='Shrink is the opposite of expand.' },
    @{ q='Diagnostic context clue: The trail was steep and rugged, so the climb felt exhausting. Rugged most nearly means'; c='rough'; d=@('empty','gentle','silent'); e='The context of a difficult climb suggests rough terrain.' },
    @{ q='Diagnostic punctuation: choose the correct sentence.'; c='After lunch, the team returned to work.'; d=@('After lunch the team, returned to work.','After, lunch the team returned to work.','After lunch the team returned, to work.'); e='The introductory phrase is correctly followed by a comma.' },
    @{ q='Diagnostic capitalization: choose the correctly capitalized sentence.'; c='We visited Cebu in April.'; d=@('We visited cebu in April.','We visited Cebu in april.','We visited cebu in april.'); e='Proper nouns and months are capitalized.' },
    @{ q='Diagnostic sentence order: best first sentence for exam prep paragraph'; c='A good first step is to list the topics you must review.'; d=@('Finally, check your mistakes.','Next, answer a practice set.','After that, review weak areas.'); e='The strongest opening sentence introduces the plan.' },
    @{ q='Diagnostic inference: Liza packed an umbrella and waterproof shoes. The weather is likely'; c='rainy'; d=@('freezing','windless','dry'); e='The clues point to rainy weather.' },
    @{ q='Diagnostic main idea: Daily reading improves vocabulary over time. Best restatement?'; c='Regular reading can build vocabulary.'; d=@('Vocabulary never changes.','Only hard books matter.','Reading lowers memory.'); e='The correct option restates the main idea.' },
    @{ q='Focus grammar: Neither of the answers ___ correct.'; c='is'; d=@('are','were','be'); e='Neither is singular, so is is correct.' },
    @{ q='Focus grammar: The list of names ___ on the board.'; c='is'; d=@('are','were','have'); e='The subject is list, which is singular.' },
    @{ q='Focus vocabulary: closest meaning of concise'; c='brief'; d=@('pleasant','rough','careless'); e='Concise means brief and direct.' },
    @{ q='Focus vocabulary: closest meaning of reluctant'; c='unwilling'; d=@('excited','certain','friendly'); e='Reluctant means unwilling or hesitant.' },
    @{ q='Focus transition: The first draft was weak. ____, the revision was much clearer.'; c='However'; d=@('Therefore','Likewise','Instead'); e='However signals contrast between the two drafts.' },
    @{ q='Focus transition: The storm ended. ____, classes resumed.'; c='Therefore'; d=@('Meanwhile','Although','Similarly'); e='Therefore shows a result after the storm ended.' },
    @{ q='Focus punctuation: choose the sentence with correct apostrophe.'; c='The students'' project won first place.'; d=@('The students project won first place.','The student''s project won first place.','The students project'' won first place.'); e='Students'' is the correct plural possessive form.' },
    @{ q='Focus punctuation: choose the correctly punctuated sentence.'; c='Yes, the results were posted yesterday.'; d=@('Yes the results, were posted yesterday.','Yes; the results were, posted yesterday.','Yes the results were posted, yesterday.'); e='The sentence uses standard comma placement after Yes.' },
    @{ q='Focus inference: Carlo kept checking the clock and tapping his foot. He was probably'; c='nervous'; d=@('asleep','confused about clocks','completely relaxed'); e='The behavior suggests nervousness or impatience.' },
    @{ q='Focus main idea: Plants need light, water, and nutrients to grow well. Best summary?'; c='Plant growth depends on several basic needs.'; d=@('Plants grow only with water.','Light is unnecessary for plants.','Only nutrients matter.'); e='The summary combines the three stated needs.' },
    @{ q='Focus tone: The volunteers offered generous, steady help all week. Tone?'; c='appreciative'; d=@('hostile','fearful','sarcastic'); e='The positive wording creates an appreciative tone.' },
    @{ q='Focus purpose: A paragraph explaining how to register online is written mainly'; c='to instruct'; d=@('to entertain','to argue','to describe scenery'); e='Step-by-step directions are meant to instruct.' },
    @{ q='Focus clarity: choose the clearer sentence.'; c='The principal announced the new policy this morning.'; d=@('This morning the new policy by the principal was announced by him.','Announcing this morning was the principal policy.','The principal policy announced this morning him.'); e='The correct sentence is direct and grammatical.' },
    @{ q='Focus word choice: The witness gave a ____ answer with no extra details.'; c='brief'; d=@('metal','stormy','fragile'); e='Brief matches the idea of a short answer.' },
    @{ q='Focus paragraph order: after a topic sentence about study habits, what should come next?'; c='A supporting detail about making a schedule'; d=@('An unrelated story about lunch','A random joke','A new title'); e='A supporting detail should follow the topic sentence.' },
    @{ q='Focus comparison word: She is ____ than her older sister.'; c='shorter'; d=@('more short','shortest','most short'); e='Shorter is the correct comparative form.' },
    @{ q='Focus editing: best revision of "The team met in order to discuss plans"'; c='The team met to discuss plans.'; d=@('The team met in order discussing plans.','The team met for plans to discuss.','The team plans met to discuss.'); e='The revision removes unnecessary words.' },
    @{ q='Focus formal tone: choose the formal sentence.'; c='The data suggest a need for further review.'; d=@('The data totally prove everything.','The data are kind of weird.','The data are super clear already.'); e='The sentence is precise and appropriately cautious.' },
    @{ q='Focus antonym of generous'; c='selfish'; d=@('kind','giving','open'); e='Selfish is opposite in meaning to generous.' },
    @{ q='Focus synonym of fragile'; c='delicate'; d=@('massive','steady','loud'); e='Delicate is the closest synonym of fragile.' }
  )
  'Mathematics' = @(
    @{ q='Diagnostic arithmetic: 14 + 27 = ?'; c='41'; d=@('39','40','42'); e='This checks quick addition; 14 + 27 = 41.' },
    @{ q='Diagnostic multiplication: 8 x 9 = ?'; c='72'; d=@('63','81','64'); e='This checks multiplication fact fluency.' },
    @{ q='Diagnostic fraction: 1/2 + 1/4 = ?'; c='3/4'; d=@('2/6','1','1/4'); e='Use a common denominator to get 2/4 + 1/4 = 3/4.' },
    @{ q='Diagnostic percent: 20% of 150 = ?'; c='30'; d=@('20','25','35'); e='0.20 x 150 = 30.' },
    @{ q='Diagnostic equation: x + 8 = 15'; c='7'; d=@('6','8','9'); e='Subtract 8 from both sides.' },
    @{ q='Diagnostic geometry: area of rectangle 7 by 5'; c='35 sq cm'; d=@('12 sq cm','24 sq cm','30 sq cm'); e='Area = length x width = 35 sq cm.' },
    @{ q='Diagnostic geometry: perimeter of square side 4 cm'; c='16 cm'; d=@('8 cm','12 cm','20 cm'); e='Perimeter of a square is 4 times the side length, so the answer is 16 cm.' },
    @{ q='Diagnostic ratio: if 2 pens cost PHP 18, one pen costs'; c='PHP 9'; d=@('PHP 6','PHP 8','PHP 10'); e='18 divided by 2 is 9.' },
    @{ q='Diagnostic time-rate: 90 km at 45 km/h takes'; c='2 hours'; d=@('1 hour','1.5 hours','3 hours'); e='Time = distance / speed = 90 / 45 = 2 hours.' },
    @{ q='Diagnostic mean: average of 3, 5, 7'; c='5'; d=@('4','6','7'); e='The sum is 15 and 15 / 3 = 5.' },
    @{ q='Focus on operations: 36 / 9 = ?'; c='4'; d=@('3','5','6'); e='This checks basic division fluency.' },
    @{ q='Focus on operations: 13 x 6 = ?'; c='78'; d=@('72','76','80'); e='Multiply 13 by 6 to get 78.' },
    @{ q='Focus on operations: 72 - 28 = ?'; c='44'; d=@('42','43','46'); e='Subtract 28 from 72.' },
    @{ q='Focus on fractions: 3/5 of 20 = ?'; c='12'; d=@('10','15','18'); e='Multiply 20 by 3/5 to get 12.' },
    @{ q='Focus on decimals: 2.5 + 1.3 = ?'; c='3.8'; d=@('3.6','3.7','4.0'); e='Add the decimals to get 3.8.' },
    @{ q='Focus on percent: 50% of 64 = ?'; c='32'; d=@('16','24','36'); e='Half of 64 is 32.' },
    @{ q='Focus on equation: 4x = 28'; c='7'; d=@('6','8','9'); e='Divide both sides by 4.' },
    @{ q='Focus on equation: y - 6 = 11'; c='17'; d=@('5','16','18'); e='Add 6 to both sides to get 17.' },
    @{ q='Focus on sequence: 6, 12, 18, ?'; c='24'; d=@('20','22','26'); e='Add 6 each time.' },
    @{ q='Focus on sequence: 2, 4, 8, ?'; c='16'; d=@('12','14','18'); e='Each term doubles.' },
    @{ q='Focus on divisibility: a number divisible by 10 ends in'; c='0'; d=@('5','2','1'); e='Numbers divisible by 10 end in 0.' },
    @{ q='Focus on line equation: point on y = x + 2'; c='(3,5)'; d=@('(3,4)','(1,1)','(0,1)'); e='Substitute x = 3 to get y = 5.' },
    @{ q='Focus on slope: rise 6 and run 3 gives slope'; c='2'; d=@('1','3','6'); e='Slope is rise divided by run = 6 / 3 = 2.' },
    @{ q='Focus on area: triangle base 10 cm, height 4 cm'; c='20 sq cm'; d=@('14 sq cm','24 sq cm','40 sq cm'); e='Area = 1/2 x base x height = 20 sq cm.' },
    @{ q='Focus on circle: circumference, radius 2 cm, pi = 3.14'; c='12.56 cm'; d=@('6.28 cm','9.42 cm','15.70 cm'); e='Circumference = 2 x pi x r = 12.56 cm.' },
    @{ q='Focus on probability: one favorable outcome out of 4 gives'; c='1/4'; d=@('1/2','3/4','4/1'); e='Probability = favorable outcomes / total outcomes.' },
    @{ q='Focus on ratio: 3:4 and first term is 12, second is'; c='16'; d=@('15','18','20'); e='If 3 parts is 12, then 1 part is 4 and 4 parts is 16.' },
    @{ q='Focus on order of operations: 3 + 2 x 5'; c='13'; d=@('25','17','10'); e='Multiply first, then add: 3 + 10 = 13.' },
    @{ q='Focus on exponent: 2^5 = ?'; c='32'; d=@('16','25','64'); e='2 multiplied by itself five times equals 32.' },
    @{ q='Focus on angle: a straight angle measures'; c='180'; d=@('90','45','360'); e='A straight angle measures 180 degrees.' }
  )
  'Science' = @(
    @{ q='Diagnostic biology: the basic unit of life is the'; c='cell'; d=@('atom','organ','molecule'); e='This identifies whether the learner knows the core biology term cell.' },
    @{ q='Diagnostic chemistry: H2O is'; c='water'; d=@('oxygen','salt','acid'); e='This checks recognition of the basic chemical formula for water.' },
    @{ q='Diagnostic physics: force pulling objects downward'; c='gravity'; d=@('friction','light','magnetism'); e='This checks knowledge of the force gravity.' },
    @{ q='Diagnostic earth science: Earth layer we live on'; c='crust'; d=@('mantle','outer core','inner core'); e='The crust is the outermost solid layer.' },
    @{ q='Diagnostic ecology: plants are usually'; c='producers'; d=@('consumers','predators','decomposers'); e='Plants make their own food, so they are producers.' },
    @{ q='Diagnostic health: organ that pumps blood'; c='heart'; d=@('liver','lung','kidney'); e='The heart pumps blood through the body.' },
    @{ q='Diagnostic weather: liquid water to vapor is'; c='evaporation'; d=@('condensation','freezing','melting'); e='Evaporation changes liquid water into gas.' },
    @{ q='Diagnostic plant science: roots mainly absorb'; c='water and minerals'; d=@('sunlight only','oxygen only','seeds only'); e='Roots take in water and minerals from the soil.' },
    @{ q='Diagnostic astronomy: the Moon shines by'; c='reflecting sunlight'; d=@('making its own fire','using electricity','absorbing gravity'); e='The Moon reflects light from the Sun.' },
    @{ q='Diagnostic matter: melting is a'; c='physical change'; d=@('chemical change','nuclear change','biological change'); e='Melting changes only the state, not the substance.' },
    @{ q='Focus cells: chloroplast is found mainly in'; c='plant cells'; d=@('all rocks','metal wires','animal bones'); e='Chloroplasts are characteristic of plant cells.' },
    @{ q='Focus cells: nucleus mainly controls'; c='cell activities'; d=@('soil quality','weather','sound waves'); e='The nucleus directs many cell functions.' },
    @{ q='Focus body systems: blood vessels carrying blood away from the heart'; c='arteries'; d=@('veins','nerves','bronchi'); e='Arteries carry blood away from the heart.' },
    @{ q='Focus body systems: the gas humans need for respiration'; c='oxygen'; d=@('helium','argon','neon'); e='Oxygen is used in cellular respiration.' },
    @{ q='Focus forces: friction usually acts to'; c='oppose motion'; d=@('create light','add mass','remove gravity'); e='Friction resists relative motion between surfaces.' },
    @{ q='Focus forces: a magnet strongly attracts'; c='iron'; d=@('glass','wood','rubber'); e='Iron is a ferromagnetic material.' },
    @{ q='Focus energy: green plants get energy mainly from'; c='sunlight'; d=@('soil','wind alone','moonlight'); e='Sunlight powers photosynthesis.' },
    @{ q='Focus energy: a moving object has'; c='kinetic energy'; d=@('nuclear energy only','chemical energy only','no energy'); e='Kinetic energy is the energy of motion.' },
    @{ q='Focus water cycle: gas to liquid is'; c='condensation'; d=@('evaporation','freezing','boiling'); e='Condensation changes vapor into liquid.' },
    @{ q='Focus water cycle: rain, snow, and hail are forms of'; c='precipitation'; d=@('evaporation','erosion','photosynthesis'); e='These are all forms of precipitation.' },
    @{ q='Focus earth science: day and night are caused by Earth'; c='rotation'; d=@('revolution only','cooling','erosion'); e='Earth rotating on its axis causes day and night.' },
    @{ q='Focus earth science: seasons are mainly caused by Earth'; c='axial tilt'; d=@('daily cloud cover','moon phases','ocean color'); e='Earth axial tilt changes the angle of sunlight during the year.' },
    @{ q='Focus chemistry: an acid has pH'; c='below 7'; d=@('above 7','equal to 14','equal to 9'); e='Acids have pH values below 7.' },
    @{ q='Focus chemistry: rusting of iron is a'; c='chemical change'; d=@('physical change','state change','magnetic change'); e='Rusting forms a new substance, so it is chemical.' },
    @{ q='Focus ecology: animals that eat only plants are'; c='herbivores'; d=@('carnivores','omnivores','decomposers'); e='Herbivores feed on plants.' },
    @{ q='Focus ecology: fungi are often'; c='decomposers'; d=@('producers','predators','planets'); e='Fungi break down dead material and recycle nutrients.' },
    @{ q='Focus measurement: instrument for mass'; c='balance'; d=@('thermometer','meter stick','barometer'); e='A balance measures mass.' },
    @{ q='Focus measurement: instrument for temperature'; c='thermometer'; d=@('ruler','beaker','stopwatch'); e='A thermometer measures temperature.' },
    @{ q='Focus experiment: the variable you change is the'; c='independent variable'; d=@('conclusion','constant only','graph title'); e='The independent variable is deliberately changed by the experimenter.' },
    @{ q='Focus experiment: a factor kept the same is a'; c='controlled variable'; d=@('prediction','dependent variable only','trial error'); e='Controlled variables are kept constant for a fair test.' }
  )
}

foreach ($entry in $focusBank.GetEnumerator()) {
  if ($entry.Value.Count -ne 30) {
    throw "Category '$($entry.Key)' must contain exactly 30 focus questions."
  }
}

$dataset = Get-Content -Raw $OutFile | ConvertFrom-Json
$focusMode = $dataset.modes | Where-Object { $_.mode -eq 'focusMode' } | Select-Object -First 1
if (-not $focusMode) { throw 'focusMode not found in dataset.' }

foreach ($categoryBlock in $focusMode.categories) {
  $categoryName = [string]$categoryBlock.category
  $prefix = @($categoryBlock.questions[0..29])
  $replacement = @()
  for ($i = 0; $i -lt 30; $i++) {
    $spec = $focusBank[$categoryName][$i]
    $replacement += New-FocusQuestion -Number (31 + $i) -Category $categoryName -Question $spec.q -Correct $spec.c -Distractors $spec.d -Explanation $spec.e -Shift ($i % 4)
  }
  $categoryBlock.questions = @($prefix + $replacement)
}

$json = $dataset | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText((Resolve-Path $OutFile), $json, [System.Text.UTF8Encoding]::new($false))
Write-Host 'Focus mode seed bank specialized successfully.'