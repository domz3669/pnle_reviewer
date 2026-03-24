param(
  [string]$OutFile = "assets/seed/initial_question_pool.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-BaselineQuestion {
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

  return [pscustomobject]@{
    number = $Number
    category = $Category
    question = $Question
    choices = $rotated
    answer = $answer
    explanation = $Explanation
    source = 'seed_pool_2027'
  }
}

$baselineBank = @{
  'Mental Ability' = @(
    @{ q = 'Identify the next term: 11, 15, 19, 23, ?'; c = '27'; d = @('26', '28', '29'); e = 'The pattern adds 4 each time, so the next term is 27.' },
    @{ q = 'Find the missing number in 2, 6, 18, 54, ?'; c = '162'; d = @('108', '144', '216'); e = 'Each term is multiplied by 3, so the next term is 162.' },
    @{ q = 'BIRD is most closely related to which word?'; c = 'NEST'; d = @('STONE', 'WHEEL', 'CLOUD'); e = 'A bird is closely associated with a nest.' },
    @{ q = 'Which item does not belong: violin, drum, flute, cabbage?'; c = 'cabbage'; d = @('violin', 'drum', 'flute'); e = 'The first three are musical instruments, while cabbage is a vegetable.' },
    @{ q = 'Move every letter of RUG forward by 2. What code results?'; c = 'TWI'; d = @('SVH', 'TXJ', 'UWK'); e = 'Move each letter forward by 2: R to T, U to W, G to I.' },
    @{ q = 'Paolo walks 4 m east, 5 m north, then 4 m west. Where is he from the starting point?'; c = 'North'; d = @('South', 'East', 'West'); e = 'The east and west movements cancel, leaving him 5 m north of the start.' },
    @{ q = 'In a race, Mira finished behind Jon but ahead of Liza. Who finished first among the three?'; c = 'Jon'; d = @('Mira', 'Liza', 'Cannot be determined'); e = 'If Mira is behind Jon and ahead of Liza, Jon finished first.' },
    @{ q = 'All triangles are polygons. Which statement must be true?'; c = 'All triangles are polygons.'; d = @('All polygons are triangles.', 'Some triangles are circles.', 'No polygons are triangles.'); e = 'The only guaranteed statement is the original class relationship.' },
    @{ q = 'Which pair has the same relationship as seed : plant?'; c = 'egg : bird'; d = @('leaf : root', 'book : shelf', 'rain : cloud'); e = 'A seed develops into a plant just as an egg develops into a bird.' },
    @{ q = 'Order these from earliest to latest: 1) bake bread 2) mix dough 3) eat bread 4) put dough in oven'; c = '2-4-1-3'; d = @('2-1-4-3', '1-2-4-3', '4-2-1-3'); e = 'You first mix dough, then bake it, then the bread is ready, and finally it is eaten.' },
    @{ q = 'What number follows 30, 26, 22, 18, ?'; c = '14'; d = @('12', '13', '16'); e = 'The pattern subtracts 4 each time, so the next term is 14.' },
    @{ q = 'Complete the pattern: 1, 4, 10, 19, ?'; c = '31'; d = @('28', '30', '33'); e = 'The differences are 3, 6, and 9, so the next difference is 12, giving 31.' },
    @{ q = 'CHAIR is most closely related to which word?'; c = 'TABLE'; d = @('RIVER', 'SHADOW', 'PENCIL'); e = 'Chair and table are closely associated pieces of furniture.' },
    @{ q = 'Which word does not belong: January, April, July, Guitar?'; c = 'Guitar'; d = @('January', 'April', 'July'); e = 'The first three are months, while guitar is a musical instrument.' },
    @{ q = 'Shift each letter of LAMP back by 1. Which code appears?'; c = 'KZLO'; d = @('KALO', 'JZKN', 'LZNO'); e = 'Move each letter back by one: L to K, A to Z, M to L, P to O.' },
    @{ q = 'A student faces west, turns right, then turns right again. Which direction is the student facing?'; c = 'East'; d = @('North', 'South', 'West'); e = 'From west, a right turn points north, and another right turn points east.' },
    @{ q = 'Ella scored higher than Bea, and Bea scored higher than Cara. Who scored lowest?'; c = 'Cara'; d = @('Ella', 'Bea', 'Cannot be determined'); e = 'If Ella > Bea > Cara, then Cara scored the lowest.' },
    @{ q = 'Some teachers are writers. Which statement must be true?'; c = 'Some writers are teachers.'; d = @('All writers are teachers.', 'No teachers are writers.', 'All teachers are writers.'); e = 'If some teachers are writers, then some writers are teachers.' },
    @{ q = 'Which pair shows the same relationship as pencil : write?'; c = 'knife : cut'; d = @('shoe : road', 'clock : wall', 'bag : zipper'); e = 'A pencil is used to write, just as a knife is used to cut.' },
    @{ q = 'Arrange these from smallest to largest: 1) lake 2) pond 3) puddle 4) sea'; c = '3-2-1-4'; d = @('2-3-1-4', '3-1-2-4', '1-2-3-4'); e = 'A puddle is smallest, followed by a pond, then a lake, then a sea.' }
  )
  'English' = @(
    @{ q = 'Choose the correct verb: The basket of apples ___ on the counter.'; c = 'is'; d = @('are', 'were', 'have'); e = 'The subject is basket, which is singular, so the correct verb is is.' },
    @{ q = 'Pick the best word: The speaker gave a very ____ explanation of the rule.'; c = 'clear'; d = @('clearly', 'clarity', 'clearness'); e = 'Clear is the correct adjective to describe explanation.' },
    @{ q = 'Read the sentence and answer: The room grew silent as the principal opened the envelope. What can be inferred?'; c = 'People were waiting for important news.'; d = @('The room was empty.', 'The principal lost the envelope.', 'Everyone had already left.'); e = 'People usually become silent when waiting for an important announcement.' },
    @{ q = 'Select the best conjunction: Rina practiced every day, ____ she improved steadily.'; c = 'so'; d = @('unless', 'although', 'because'); e = 'So correctly shows the result of her daily practice.' },
    @{ q = 'Which sentence uses punctuation correctly?'; c = 'Before sunrise, the hikers packed their bags.'; d = @('Before sunrise the hikers, packed their bags.', 'Before, sunrise the hikers packed their bags.', 'Before sunrise the hikers packed, their bags.'); e = 'The introductory phrase is correctly followed by a comma.' },
    @{ q = 'Choose the word closest in meaning to fragile.'; c = 'delicate'; d = @('massive', 'silent', 'common'); e = 'Delicate is the closest synonym of fragile.' },
    @{ q = 'In the sentence below, which phrase acts as an adverbial modifier? The team rested after the long trip.'; c = 'after the long trip'; d = @('The team', 'rested', 'long trip'); e = 'After the long trip modifies rested by telling when the action happened.' },
    @{ q = 'Which sentence should begin a paragraph about saving money?'; c = 'A smart way to save money is to track your spending first.'; d = @('Finally, compare your total savings.', 'After that, avoid impulse buying.', 'Next, open a simple notebook.'); e = 'The best opening sentence introduces the main idea of the paragraph.' },
    @{ q = 'Choose the clearest sentence.'; c = 'The mayor announced the new schedule during the meeting.'; d = @('The schedule during the meeting was new by the mayor announced.', 'Announcing the mayor during the meeting was the schedule.', 'The meeting announced by the mayor the new schedule.'); e = 'Choice A is grammatically correct and clearly states the idea.' },
    @{ q = 'Which option is an inference rather than a directly stated fact?'; c = 'The audience probably liked the performance.'; d = @('The show ended at 8 p.m.', 'The curtain closed after the final song.', 'The performers bowed to the crowd.'); e = 'Probably liked is a conclusion drawn from details, not a directly stated fact.' },
    @{ q = 'Complete the sentence correctly: Either the captain or the players ___ carrying the equipment.'; c = 'are'; d = @('is', 'was', 'be'); e = 'With either/or, the verb agrees with the nearer subject, players, so are is correct.' },
    @{ q = 'Choose the best word to complete the sentence: The recipe was easy to follow because the steps were ____.'; c = 'simple'; d = @('simply', 'simplicity', 'simplify'); e = 'Simple correctly describes the noun steps.' },
    @{ q = 'Read the paragraph: Dani planted herbs in recycled cans on her window ledge. After a few weeks, she was using fresh basil and mint in her meals. What is the main idea?'; c = 'Dani successfully grew useful herbs in a small space.'; d = @('Window ledges are hard to clean.', 'Mint grows faster than basil.', 'Meals should always include herbs.'); e = 'The paragraph focuses on Dani growing herbs successfully in a limited space.' },
    @{ q = 'Choose the best transition word: The road was slippery. ____, the driver reduced speed.'; c = 'Therefore'; d = @('Meanwhile', 'Similarly', 'Instead'); e = 'Therefore signals that reducing speed was a result of the slippery road.' },
    @{ q = 'Which sentence uses standard grammar correctly?'; c = 'Its cover was torn after the storm.'; d = @('It''s cover was torn after the storm.', 'Its'' cover was torn after the storm.', 'Its cover, was torn after the storm.'); e = 'Its is the correct possessive pronoun in this sentence.' },
    @{ q = 'Choose the word opposite in meaning to generous.'; c = 'stingy'; d = @('kind', 'helpful', 'warm'); e = 'Stingy is the antonym of generous.' },
    @{ q = 'Which phrase functions as an adverbial modifier in the sentence below? Mara spoke with confidence during the interview.'; c = 'during the interview'; d = @('Mara', 'spoke', 'with confidence'); e = 'During the interview tells when she spoke.' },
    @{ q = 'Which sentence should come first in a paragraph about planting trees?'; c = 'Communities should begin by choosing tree species suited to the area.'; d = @('Later, volunteers can water the seedlings.', 'After that, the holes should be covered with soil.', 'Finally, the young trees should be monitored.'); e = 'The first sentence should introduce the initial planning step.' },
    @{ q = 'Choose the sentence with the most logical wording.'; c = 'The librarian organized the shelves before opening the reading room.'; d = @('Opening the reading room, the shelves organized the librarian.', 'The shelves before opening organized the librarian room.', 'The reading room organized before the librarian shelves.'); e = 'Choice A is the clearest and most logical sentence.' },
    @{ q = 'Which statement is best understood as an inference?'; c = 'The team may need more practice before the finals.'; d = @('The team scored 72 in the last game.', 'The coach called a timeout in the third quarter.', 'The players returned to the bench after the game.'); e = 'May need more practice is a conclusion based on details, not a direct fact.' }
  )
  'Mathematics' = @(
    @{ q = 'Compute 37 + 26.'; c = '63'; d = @('53', '61', '64'); e = 'Adding 37 and 26 gives 63.' },
    @{ q = 'Multiply 14 by 6.'; c = '84'; d = @('76', '80', '96'); e = '14 x 6 = 84.' },
    @{ q = 'Reduce the fraction 24/6.'; c = '4'; d = @('3', '6/4', '1/4'); e = '24 divided by 6 equals 4.' },
    @{ q = 'Solve for x: x + 12 = 19.'; c = '7'; d = @('6', '8', '9'); e = 'Subtract 12 from both sides, so x = 7.' },
    @{ q = 'If y = 4x and x = 3, what is y?'; c = '12'; d = @('7', '9', '16'); e = 'Substitute x = 3 into y = 4x to get y = 12.' },
    @{ q = 'Find the area of a rectangle with length 6 cm and width 8 cm.'; c = '48 sq cm'; d = @('28 sq cm', '14 sq cm', '56 sq cm'); e = 'Area = length x width = 6 x 8 = 48 sq cm.' },
    @{ q = 'A circle has radius 5 cm. Using pi = 3.14, find its circumference.'; c = '31.4 cm'; d = @('15.7 cm', '78.5 cm', '25.0 cm'); e = 'Circumference = 2 x pi x r = 2 x 3.14 x 5 = 31.4 cm.' },
    @{ q = 'Determine the mean of 5, 7, 9, and 11.'; c = '8'; d = @('7', '9', '10'); e = 'The sum is 32 and 32 / 4 = 8.' },
    @{ q = 'Find 25% of 160.'; c = '40'; d = @('20', '30', '50'); e = '25% is one-fourth, and one-fourth of 160 is 40.' },
    @{ q = 'A jeep travels 150 km at 50 km/h. How long is the trip?'; c = '3 hours'; d = @('2 hours', '2.5 hours', '4 hours'); e = 'Time = distance / speed = 150 / 50 = 3 hours.' },
    @{ q = 'A number is divisible by 9 if'; c = 'the sum of its digits is divisible by 9'; d = @('its last digit is even', 'it ends in 0', 'its last two digits form a multiple of 4'); e = 'The divisibility rule for 9 uses the sum of the digits.' },
    @{ q = 'Which point lies on the line y = x + 4?'; c = '(2,6)'; d = @('(2,4)', '(1,4)', '(0,5)'); e = 'Substituting x = 2 gives y = 6, so (2,6) lies on the line.' },
    @{ q = 'Add 18 and 27.'; c = '45'; d = @('35', '44', '46'); e = '18 + 27 = 45.' },
    @{ q = 'Evaluate 9 x 12.'; c = '108'; d = @('96', '99', '118'); e = '9 x 12 = 108.' },
    @{ q = 'Write 18/3 in simplest form.'; c = '6'; d = @('3', '9', '18/3'); e = '18 divided by 3 equals 6.' },
    @{ q = 'Solve for n: n - 5 = 13.'; c = '18'; d = @('8', '17', '19'); e = 'Add 5 to both sides, so n = 18.' },
    @{ q = 'If p = 3m and m = 8, find p.'; c = '24'; d = @('11', '16', '32'); e = 'Substitute m = 8 into p = 3m to get p = 24.' },
    @{ q = 'Find the area of a rectangle with length 12 cm and width 4 cm.'; c = '48 sq cm'; d = @('16 sq cm', '32 sq cm', '40 sq cm'); e = 'Area = 12 x 4 = 48 sq cm.' },
    @{ q = 'Find the circumference of a circle with radius 3 cm if pi = 3.14.'; c = '18.84 cm'; d = @('9.42 cm', '28.26 cm', '12.56 cm'); e = 'Circumference = 2 x 3.14 x 3 = 18.84 cm.' },
    @{ q = 'Find the average of 12, 14, 16, and 18.'; c = '15'; d = @('14', '16', '17'); e = 'The sum is 60 and 60 / 4 = 15.' }
  )
  'Science' = @(
    @{ q = 'Which organelle stores genetic material and directs cell activities?'; c = 'Nucleus'; d = @('Ribosome', 'Mitochondrion', 'Cell wall'); e = 'The nucleus contains genetic material and controls cell activities.' },
    @{ q = 'The symbol for potassium is'; c = 'K'; d = @('P', 'Po', 'Pt'); e = 'The chemical symbol for potassium is K.' },
    @{ q = 'Which force slows motion between two surfaces that rub together?'; c = 'Friction'; d = @('Gravity', 'Magnetism', 'Tension'); e = 'Friction opposes motion between surfaces in contact.' },
    @{ q = 'Which Earth layer lies directly beneath the crust?'; c = 'Mantle'; d = @('Outer core', 'Inner core', 'Atmosphere'); e = 'The mantle is the thick layer beneath Earth''s crust.' },
    @{ q = 'In an experiment, what is the dependent variable?'; c = 'the factor that is measured'; d = @('the factor that is changed on purpose', 'the final conclusion only', 'the list of materials'); e = 'The dependent variable is the result that is observed or measured.' },
    @{ q = 'Which process releases energy from food inside cells?'; c = 'Respiration'; d = @('Photosynthesis', 'Digestion', 'Transpiration'); e = 'Cellular respiration releases usable energy from food.' },
    @{ q = 'What happens to particles when a liquid cools and becomes a solid?'; c = 'They move more slowly and pack closer together.'; d = @('They disappear completely.', 'They turn into gas only.', 'They move farther apart and faster.'); e = 'Cooling lowers particle energy, so particles move less and stay closer together.' },
    @{ q = 'Which blood vessels carry blood back toward the heart?'; c = 'Veins'; d = @('Arteries', 'Bronchi', 'Capillaries'); e = 'Veins return blood to the heart.' },
    @{ q = 'Why does a black shirt feel hotter in sunlight than a white shirt?'; c = 'Black absorbs more heat energy.'; d = @('White creates more friction.', 'Black has no temperature.', 'White blocks all light.'); e = 'Dark colors absorb more radiant heat than light colors.' },
    @{ q = 'Which water-cycle process forms clouds from cooled water vapor?'; c = 'Condensation'; d = @('Evaporation', 'Melting', 'Freezing'); e = 'Condensation happens when water vapor cools into tiny droplets that can form clouds.' },
    @{ q = 'Which simple machine is a wheel attached to a rod that turns with it?'; c = 'Wheel and axle'; d = @('Lever', 'Pulley', 'Inclined plane'); e = 'A wheel and axle is made of a large wheel fixed to a smaller rod.' },
    @{ q = 'A graph shows plant growth rising as water increases, then dropping when water is excessive. What is the best conclusion?'; c = 'Too much water can reduce plant growth.'; d = @('Water never helps plants grow.', 'Plants do not need sunlight.', 'Growth is unrelated to water.'); e = 'The graph suggests moderate water helps, but too much reduces growth.' },
    @{ q = 'Which organelle makes proteins for the cell?'; c = 'Ribosome'; d = @('Nucleus', 'Vacuole', 'Chloroplast'); e = 'Ribosomes are the structures that build proteins.' },
    @{ q = 'Select the correct symbol for iron.'; c = 'Fe'; d = @('Ir', 'In', 'Io'); e = 'The chemical symbol for iron is Fe.' },
    @{ q = 'Which force keeps planets moving around the Sun?'; c = 'Gravity'; d = @('Friction', 'Electricity', 'Buoyancy'); e = 'Gravity provides the attraction that keeps planets in orbit.' },
    @{ q = 'Which Earth layer is liquid and surrounds the inner core?'; c = 'Outer core'; d = @('Crust', 'Mantle', 'Atmosphere'); e = 'The outer core is the liquid layer surrounding Earth''s solid inner core.' },
    @{ q = 'If a scientist changes only soil type, what is the manipulated variable?'; c = 'Type of soil'; d = @('Plant height', 'Amount of sunlight', 'Number of leaves counted'); e = 'The manipulated variable is the factor the scientist changes on purpose.' },
    @{ q = 'Which process in plants moves water from roots to leaves and releases vapor from leaves?'; c = 'Transpiration'; d = @('Respiration', 'Fermentation', 'Condensation'); e = 'Transpiration is the movement and loss of water vapor from plant leaves.' },
    @{ q = 'When water changes from gas to liquid, what happens?'; c = 'Particles lose energy and move closer together.'; d = @('Particles gain energy and spread farther apart.', 'Particles become solid immediately.', 'Particles split into oxygen and hydrogen.'); e = 'Condensation happens when particles lose energy and move closer together.' },
    @{ q = 'Which part of the body exchanges oxygen and carbon dioxide with the blood?'; c = 'Lungs'; d = @('Kidneys', 'Stomach', 'Muscles'); e = 'The lungs exchange gases with the blood in the alveoli.' }
  )
}

foreach ($entry in $baselineBank.GetEnumerator()) {
  if ($entry.Value.Count -ne 20) {
    throw "Category '$($entry.Key)' must contain exactly 20 baseline replacement questions."
  }
}

$dataset = Get-Content -Raw $OutFile | ConvertFrom-Json

foreach ($mode in $dataset.modes) {
  foreach ($category in $mode.categories) {
    $categoryName = [string]$category.category
    if (-not $baselineBank.ContainsKey($categoryName)) {
      throw "No baseline bank found for category '$categoryName'."
    }

    $questions = @($category.questions)
    foreach ($item in $questions) {
      $number = [int]$item.number
      if ($item.source -ne 'seed_pool_2027' -or $number -lt 11 -or $number -gt 30) {
        continue
      }

      $spec = $baselineBank[$categoryName][$number - 11]
      $replacement = New-BaselineQuestion `
        -Number $number `
        -Category $categoryName `
        -Question $spec.q `
        -Correct $spec.c `
        -Distractors $spec.d `
        -Explanation $spec.e `
        -Shift (($number - 1) % 4)

      $category.questions[$number - 1] = $replacement
    }
  }
}

$json = $dataset | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText((Resolve-Path $OutFile), $json, [System.Text.UTF8Encoding]::new($false))

Write-Host 'Baseline seed questions 11-30 refreshed successfully.'