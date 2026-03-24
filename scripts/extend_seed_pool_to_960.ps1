param(
  [string]$OutFile = "assets/seed/initial_question_pool.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-SeedQuestion {
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
    source = 'seed_pool_2027_expansion'
  }
}

$questionBank = @{
  'Mental Ability' = @(
    @{ q = 'What number comes next in the series 12, 16, 20, 24, ?'; c = '28'; d = @('26', '30', '32'); e = 'The pattern adds 4 each time, so the next term is 28.' },
    @{ q = 'What number should replace the question mark in the series 81, 27, 9, 3, ?'; c = '1'; d = @('0', '6', '9'); e = 'Each term is divided by 3, so the next number is 1.' },
    @{ q = 'What number comes next in the pattern 2, 5, 3, 6, 4, 7, ?'; c = '5'; d = @('6', '7', '8'); e = 'The pattern alternates between two rising sequences: 2, 3, 4, 5 and 5, 6, 7.' },
    @{ q = 'What number should replace the question mark in the series 1, 4, 9, 16, ?'; c = '25'; d = @('20', '24', '36'); e = 'These are perfect squares: 1^2, 2^2, 3^2, 4^2, so the next term is 5^2 = 25.' },
    @{ q = 'Which letter comes next in the sequence B, D, F, H, ?'; c = 'J'; d = @('I', 'K', 'L'); e = 'The letters move forward by two places each time: B, D, F, H, J.' },
    @{ q = 'If each letter in BOOK is moved one place forward in the alphabet, what is the new code?'; c = 'CPPL'; d = @('CPMK', 'DQQL', 'BPPL'); e = 'B becomes C, O becomes P, O becomes P, and K becomes L, giving CPPL.' },
    @{ q = 'Painter is to brush as writer is to'; c = 'pen'; d = @('paper', 'book', 'desk'); e = 'A painter uses a brush, and a writer uses a pen.' },
    @{ q = 'Seed is to plant as egg is to'; c = 'bird'; d = @('nest', 'feather', 'wing'); e = 'A seed can develop into a plant, and an egg can develop into a bird.' },
    @{ q = 'Which does not belong in the group: rose, tulip, lily, carrot?'; c = 'carrot'; d = @('rose', 'tulip', 'lily'); e = 'Rose, tulip, and lily are flowers, while carrot is a root vegetable.' },
    @{ q = 'Which does not belong in the group: triangle, square, rectangle, circle?'; c = 'circle'; d = @('triangle', 'square', 'rectangle'); e = 'Triangle, square, and rectangle are polygons with straight sides, while a circle has no straight side.' },
    @{ q = 'Lia walks 4 meters north, then 3 meters east, then 4 meters south. Where is she now from her starting point?'; c = 'East'; d = @('West', 'North', 'South'); e = 'The north and south movements cancel out, leaving her 3 meters east of the start.' },
    @{ q = 'A boy faces west, turns left, then turns left again. Which direction is he now facing?'; c = 'East'; d = @('North', 'South', 'West'); e = 'Facing west, a left turn points south, and another left turn points east.' },
    @{ q = 'Ana is taller than Ben. Ben is taller than Cara. Who is the tallest?'; c = 'Ana'; d = @('Ben', 'Cara', 'Cannot be determined'); e = 'If Ana is taller than Ben and Ben is taller than Cara, then Ana is the tallest.' },
    @{ q = 'Your sister''s father is your'; c = 'father'; d = @('uncle', 'brother', 'grandfather'); e = 'Your sister and you have the same father.' },
    @{ q = 'All orchids are flowers. All flowers are plants. Which statement must be true?'; c = 'All orchids are plants.'; d = @('All plants are orchids.', 'Some plants are not flowers.', 'All flowers are orchids.'); e = 'If all orchids are flowers and all flowers are plants, then all orchids are plants.' },
    @{ q = 'Some athletes are musicians. Which statement must be true?'; c = 'Some musicians are athletes.'; d = @('All musicians are athletes.', 'No athlete is a musician.', 'All athletes are musicians.'); e = 'If some athletes are musicians, then the same group can also be described as some musicians who are athletes.' },
    @{ q = 'What comes next in the pattern A2, C4, E6, ?'; c = 'G8'; d = @('F7', 'G7', 'H8'); e = 'The letters move by two places and the numbers increase by 2, so the next term is G8.' },
    @{ q = 'If 4 corresponds to 20 and 6 corresponds to 42, what does 8 correspond to using the same rule?'; c = '72'; d = @('56', '64', '80'); e = 'The pattern multiplies the number by the next integer: 4 x 5 = 20, 6 x 7 = 42, so 8 x 9 = 72.' },
    @{ q = 'Four friends sit in a row. Bea sits to the left of Carlo, and Dana sits to the right of Carlo. Who sits between Bea and Dana?'; c = 'Carlo'; d = @('Bea', 'Dana', 'It cannot be determined'); e = 'Carlo must be between Bea and Dana based on the given positions.' },
    @{ q = 'What number comes next in the series 30, 27, 23, 18, ?'; c = '12'; d = @('11', '13', '14'); e = 'The pattern subtracts 3, then 4, then 5, so the next step subtracts 6 to give 12.' },
    @{ q = 'Bird is to nest as bee is to'; c = 'hive'; d = @('flower', 'honey', 'swarm'); e = 'A bird lives in a nest, and a bee lives in a hive.' },
    @{ q = 'Which does not belong in the group: Mercury, Venus, Mars, Moon?'; c = 'Moon'; d = @('Mercury', 'Venus', 'Mars'); e = 'Mercury, Venus, and Mars are planets, while the Moon is a natural satellite.' },
    @{ q = 'A girl faces south, turns right, then turns left. Which direction is she facing now?'; c = 'South'; d = @('East', 'West', 'North'); e = 'Facing south, a right turn points west, and a left turn from west points back to south.' },
    @{ q = 'In a race, Mark finished ahead of Paul but behind Nina. Who finished first among the three?'; c = 'Nina'; d = @('Mark', 'Paul', 'It cannot be determined'); e = 'If Mark is behind Nina and ahead of Paul, then Nina finished first.' },
    @{ q = 'At exactly 3:00, what is the angle between the hour hand and the minute hand of a clock?'; c = '90 degrees'; d = @('60 degrees', '120 degrees', '180 degrees'); e = 'At 3:00, the minute hand points at 12 and the hour hand points at 3, forming a right angle.' },
    @{ q = 'What number comes next in the pattern 5, 10, 20, 40, ?'; c = '80'; d = @('60', '70', '100'); e = 'Each term is doubled, so the next number is 80.' },
    @{ q = 'Which word does not belong: January, April, Monday, September?'; c = 'Monday'; d = @('January', 'April', 'September'); e = 'January, April, and September are months, while Monday is a day of the week.' },
    @{ q = 'Arrange these words alphabetically. Which comes first? Maple, Mango, March, Market'; c = 'Mango'; d = @('Maple', 'March', 'Market'); e = 'Comparing letter by letter, Mango comes before Maple, March, and Market.' },
    @{ q = 'In a number grid, each row follows the same rule: 2, 4, 8 and 3, 6, 12. Following the rule, 5, 10, ?'; c = '20'; d = @('15', '25', '30'); e = 'The second number is double the first, and the third is double the second, so 10 becomes 20.' },
    @{ q = 'Your uncle''s daughter is your'; c = 'cousin'; d = @('niece', 'sister', 'aunt'); e = 'Your uncle''s daughter is your cousin.' }
  )
  'English' = @(
    @{ q = 'Choose the word closest in meaning to diligent.'; c = 'hardworking'; d = @('careless', 'silent', 'uncertain'); e = 'Diligent means hardworking and consistently careful in effort.' },
    @{ q = 'Choose the word opposite in meaning to reluctant.'; c = 'eager'; d = @('fearful', 'late', 'quiet'); e = 'Reluctant means unwilling, so the opposite is eager or willing.' },
    @{ q = 'The land was arid; not a single patch of grass remained green. Based on context, arid most nearly means'; c = 'dry'; d = @('fertile', 'crowded', 'windy'); e = 'The clue about the grass not remaining green shows that arid means very dry.' },
    @{ q = 'Which sentence is grammatically correct?'; c = 'Each of the players is wearing a number.'; d = @('Each of the players are wearing a number.', 'Each of the players were wearing a number.', 'Each of the players wear a number.'); e = 'The subject each is singular, so it takes the singular verb is.' },
    @{ q = 'Choose the sentence with the correct verb tense.'; c = 'By the time the bell rang, the class had finished the quiz.'; d = @('By the time the bell rang, the class has finished the quiz.', 'By the time the bell rang, the class finish the quiz.', 'By the time the bell rang, the class will finish the quiz.'); e = 'The past perfect had finished correctly shows an action completed before another past event.' },
    @{ q = 'Choose the correct pronoun to complete the sentence: The coach gave the awards to Mia and ____.'; c = 'me'; d = @('I', 'myself', 'mine'); e = 'The pronoun is the object of the preposition to, so me is correct.' },
    @{ q = 'Which sentence avoids a misplaced modifier?'; c = 'Running to catch the bus, Carlo dropped his notebook.'; d = @('Running to catch the bus, the notebook fell from Carlo''s hand.', 'Carlo dropped his notebook running to catch the bus that was blue.', 'The notebook, running to catch the bus, fell.'); e = 'The corrected sentence clearly shows that Carlo was the one running.' },
    @{ q = 'Choose the best conjunction to complete the sentence: Lea was tired, ____ she finished her homework before sleeping.'; c = 'but'; d = @('because', 'unless', 'so'); e = 'But correctly shows contrast between being tired and still finishing the homework.' },
    @{ q = 'Choose the best transition word: The first trial failed. ____, the team changed the design and tested it again.'; c = 'Therefore'; d = @('Meanwhile', 'Instead', 'Similarly'); e = 'Therefore shows a result or response to the failed first trial.' },
    @{ q = 'Choose the word that best completes the sentence: The scientist gave a very ____ explanation that helped the class understand the topic.'; c = 'clear'; d = @('fragile', 'silent', 'narrow'); e = 'Clear is the word that best describes an explanation that helps others understand.' },
    @{ q = 'Which sentence uses punctuation correctly?'; c = 'My brother, who lives in Cebu, will visit us next week.'; d = @('My brother who lives in Cebu will visit us, next week.', 'My brother who lives in Cebu, will visit us next week.', 'My brother, who lives in Cebu will visit us next week.'); e = 'The nonessential clause who lives in Cebu should be enclosed with commas.' },
    @{ q = 'Which sentence uses capitalization correctly?'; c = 'We visited Rizal Park on Sunday in June.'; d = @('We visited rizal park on Sunday in June.', 'We visited Rizal park on sunday in june.', 'We visited rizal Park on Sunday in June.'); e = 'Proper nouns and days and months are capitalized: Rizal Park, Sunday, and June.' },
    @{ q = 'Read the passage: Many students perform better when they review in short daily sessions instead of cramming the night before an exam. Short review periods help information move into long-term memory. What is the main idea?'; c = 'Short daily review sessions are more effective than cramming.'; d = @('Students should never study at night.', 'Memory is unimportant during exams.', 'Long exams are always harder than short ones.'); e = 'Both sentences support the idea that short, regular review is more effective than cramming.' },
    @{ q = 'Read the passage: The library added more tables near the windows. After the change, more students stayed there to study in the afternoon. Which detail supports the idea that the change helped students?'; c = 'More students stayed there to study in the afternoon.'; d = @('The library has many windows.', 'Tables are made of wood.', 'The afternoon is shorter than the morning.'); e = 'That detail directly shows a positive result after the tables were added.' },
    @{ q = 'Read the passage: Paolo reviewed for two weeks and answered practice tests every night. On exam day, he felt calm. What can be inferred?'; c = 'His preparation helped him feel confident.'; d = @('He did not need to study.', 'He forgot the exam date.', 'He was absent during review week.'); e = 'The calm feeling on exam day suggests that his preparation gave him confidence.' },
    @{ q = 'What is the tone of this sentence? The committee appreciated the volunteers'' steady, cheerful help throughout the event.'; c = 'grateful'; d = @('angry', 'mocking', 'fearful'); e = 'The words appreciated and cheerful create a grateful tone.' },
    @{ q = 'What is the author''s purpose in a paragraph that explains how to create a study schedule?'; c = 'to instruct'; d = @('to entertain', 'to confuse', 'to complain'); e = 'A paragraph explaining steps is written to instruct or inform the reader.' },
    @{ q = 'Which sentence is the best topic sentence for a paragraph about regular exercise?'; c = 'Regular exercise improves both physical health and mental focus.'; d = @('Many shoes are sold in sports stores.', 'Some people wake up early on weekends.', 'Water bottles come in different sizes.'); e = 'The sentence introduces the main point that a full paragraph about exercise could develop.' },
    @{ q = 'Which sentence is irrelevant in a paragraph about saving water at home?'; c = 'My cousin prefers blue notebooks to black ones.'; d = @('Turning off the tap while brushing saves water.', 'Fixing leaks prevents waste.', 'Collecting rainwater can help water plants.'); e = 'The notebook preference is unrelated to the topic of saving water.' },
    @{ q = 'Which sentence should come first in a coherent paragraph about preparing for an interview?'; c = 'A good first step is to research the company carefully.'; d = @('Finally, thank the interviewer for the opportunity.', 'After that, practice answering common questions.', 'Next, choose appropriate clothes for the meeting.'); e = 'Researching the company introduces the process and logically comes before later steps.' },
    @{ q = 'Choose the most concise revision: The reason why the team won was because they practiced every day.'; c = 'The team won because they practiced every day.'; d = @('The reason why the team won is because they practiced every day.', 'Because they practiced every day was why the team won.', 'Every day the team practiced because of the reason they won.'); e = 'The revision removes unnecessary words and keeps the meaning clear.' },
    @{ q = 'Choose the best combined sentence: Mara reviewed the notes. Mara solved extra problems.'; c = 'Mara reviewed the notes and solved extra problems.'; d = @('Mara reviewed the notes, Mara solved extra problems.', 'Mara reviewed the notes because Mara solved extra problems.', 'Mara reviewed the notes solved extra problems.'); e = 'The conjunction and combines the two related actions correctly.' },
    @{ q = 'Which sentence shows parallel structure?'; c = 'The program teaches students to analyze, to compare, and to explain.'; d = @('The program teaches students to analyze, comparing, and explanation.', 'The program teaches students analyzing, to compare, and to explain.', 'The program teaches students analysis, compare, and explaining.'); e = 'Each item in the series uses the same grammatical form, creating parallel structure.' },
    @{ q = 'Choose the correct word: The weather can ____ how fast concrete dries.'; c = 'affect'; d = @('effect', 'infect', 'reflect'); e = 'Affect is the verb meaning to influence.' },
    @{ q = 'Choose the sentence that uses the idiom correctly.'; c = 'After weeks of confusion, the lesson finally became clear and everything clicked.'; d = @('The lesson clicked the teacher into the room.', 'Everything clicked under the table quietly.', 'The lesson was clicking because it was loud.'); e = 'The idiom everything clicked means things suddenly became understandable.' },
    @{ q = 'Which sentence is in the active voice?'; c = 'The class president announced the schedule.'; d = @('The schedule was announced by the class president.', 'The schedule had been announced.', 'The schedule is being announced.'); e = 'In the active voice, the subject performs the action: the class president announced the schedule.' },
    @{ q = 'Which title best fits a paragraph about planting vegetables in small urban spaces?'; c = 'Growing Food in Limited Spaces'; d = @('The Tallest Buildings in the City', 'Reasons to Avoid Vegetables', 'How to Paint a Garden Fence'); e = 'The title matches the main idea of raising vegetables even in small urban areas.' },
    @{ q = 'Read the passage: The team recorded lower energy use after replacing old bulbs with LED lights. Their electric bill also dropped. Which conclusion is best supported?'; c = 'LED lights helped the team reduce electricity costs.'; d = @('LED lights never need replacement.', 'The team stopped using electricity at night.', 'All lights use the same amount of energy.'); e = 'Lower energy use and a smaller electric bill directly support the conclusion that LED lights reduced costs.' },
    @{ q = 'Choose the correct word: We need ____ chairs than we used yesterday.'; c = 'fewer'; d = @('less', 'fewest', 'least'); e = 'Fewer is used with countable nouns like chairs.' },
    @{ q = 'Which sentence uses word choice correctly?'; c = 'The principal praised the students for their respectful behavior.'; d = @('The principal praised the students for their respect behavior.', 'The principal praised the students for they respectful behavior.', 'The principal praised the students for behavior respectful.'); e = 'Respectful correctly modifies behavior in a grammatically complete sentence.' }
  )
  'Mathematics' = @(
    @{ q = 'Solve for x: x + 7 = 19'; c = '12'; d = @('10', '11', '13'); e = 'Subtract 7 from both sides: x = 12.' },
    @{ q = 'Solve for x: 3x - 5 = 16'; c = '7'; d = @('6', '8', '9'); e = 'Add 5 to get 3x = 21, then divide by 3 to get x = 7.' },
    @{ q = 'What is 2/3 + 1/6?'; c = '5/6'; d = @('3/6', '1', '4/9'); e = 'Convert 2/3 to 4/6, then add 4/6 + 1/6 = 5/6.' },
    @{ q = 'What is 25% of 240?'; c = '60'; d = @('40', '50', '80'); e = 'Twenty-five percent is one-fourth, and one-fourth of 240 is 60.' },
    @{ q = 'If the ratio of boys to girls is 3:5 and there are 27 boys, how many girls are there?'; c = '45'; d = @('32', '36', '40'); e = 'If 3 parts correspond to 27, then 1 part is 9 and 5 parts is 45.' },
    @{ q = 'What is the average of 8, 12, 15, and 5?'; c = '10'; d = @('9', '11', '12'); e = 'Add the numbers to get 40, then divide by 4 to get 10.' },
    @{ q = 'A box contains 3 red marbles and 2 blue marbles. What is the probability of drawing a red marble?'; c = '3/5'; d = @('2/5', '1/2', '3/4'); e = 'There are 3 favorable outcomes out of 5 total marbles, so the probability is 3/5.' },
    @{ q = 'What is the perimeter of a rectangle with length 9 cm and width 4 cm?'; c = '26 cm'; d = @('13 cm', '32 cm', '36 cm'); e = 'Perimeter = 2(length + width) = 2(9 + 4) = 26 cm.' },
    @{ q = 'What is the area of a triangle with base 10 cm and height 6 cm?'; c = '30 sq cm'; d = @('16 sq cm', '20 sq cm', '60 sq cm'); e = 'Area of a triangle is 1/2 x base x height = 1/2 x 10 x 6 = 30 sq cm.' },
    @{ q = 'What is the circumference of a circle with radius 7 cm if pi is 22/7?'; c = '44 cm'; d = @('14 cm', '22 cm', '49 cm'); e = 'Circumference = 2pi r = 2 x 22/7 x 7 = 44 cm.' },
    @{ q = 'What is the simple interest on PHP 2,000 at 5% per year for 2 years?'; c = 'PHP 200'; d = @('PHP 100', 'PHP 150', 'PHP 250'); e = 'Simple interest = PRT = 2000 x 0.05 x 2 = 200.' },
    @{ q = 'A car travels 150 kilometers at 50 kilometers per hour. How long does the trip take?'; c = '3 hours'; d = @('2 hours', '2.5 hours', '4 hours'); e = 'Time = distance divided by speed = 150 / 50 = 3 hours.' },
    @{ q = 'One worker can finish a job in 6 hours and another in 3 hours. How long will they take working together?'; c = '2 hours'; d = @('1 hour', '2.5 hours', '3 hours'); e = 'Their combined rate is 1/6 + 1/3 = 1/2 job per hour, so they finish in 2 hours.' },
    @{ q = 'What is 2^3 x 2^4?'; c = '128'; d = @('16', '32', '64'); e = 'When multiplying powers with the same base, add the exponents: 2^(3+4) = 2^7 = 128.' },
    @{ q = 'What is the square root of 196?'; c = '14'; d = @('12', '13', '16'); e = 'Since 14 x 14 = 196, the square root of 196 is 14.' },
    @{ q = 'What is the slope of the line passing through (1, 2) and (5, 10)?'; c = '2'; d = @('1', '3', '4'); e = 'Slope = (10 - 2) / (5 - 1) = 8 / 4 = 2.' },
    @{ q = 'Which point lies on the line y = 3x - 1?'; c = '(2, 5)'; d = @('(2, 4)', '(1, 1)', '(3, 10)'); e = 'Substitute x = 2: y = 3(2) - 1 = 5, so (2, 5) lies on the line.' },
    @{ q = 'A number is divisible by 9 if'; c = 'the sum of its digits is divisible by 9'; d = @('it ends in 9', 'it is an odd number', 'its last two digits form a multiple of 9'); e = 'The divisibility rule for 9 depends on the sum of the digits.' },
    @{ q = 'What is the greatest common factor of 18 and 24?'; c = '6'; d = @('3', '8', '12'); e = 'The largest whole number that divides both 18 and 24 is 6.' },
    @{ q = 'What is the least common multiple of 6 and 8?'; c = '24'; d = @('12', '18', '48'); e = 'The smallest number divisible by both 6 and 8 is 24.' },
    @{ q = 'Find the 10th term of the arithmetic sequence with first term 5 and common difference 4.'; c = '41'; d = @('37', '40', '45'); e = 'The nth term is a1 + (n - 1)d = 5 + 9(4) = 41.' },
    @{ q = 'What is the next term in the geometric sequence 3, 6, 12, 24, ?'; c = '48'; d = @('30', '36', '54'); e = 'Each term is multiplied by 2, so the next term is 48.' },
    @{ q = 'Solve the system: x + y = 10 and x - y = 4'; c = 'x = 7, y = 3'; d = @('x = 6, y = 4', 'x = 8, y = 2', 'x = 5, y = 5'); e = 'Adding the equations gives 2x = 14, so x = 7 and then y = 3.' },
    @{ q = 'Solve the inequality: 3x + 2 < 14'; c = 'x < 4'; d = @('x > 4', 'x < 6', 'x > 6'); e = 'Subtract 2 to get 3x < 12, then divide by 3 to get x < 4.' },
    @{ q = 'What is the volume of a rectangular prism with length 3 cm, width 4 cm, and height 5 cm?'; c = '60 cubic cm'; d = @('12 cubic cm', '20 cubic cm', '120 cubic cm'); e = 'Volume = length x width x height = 3 x 4 x 5 = 60 cubic cm.' },
    @{ q = 'By what percent did a value increase from 80 to 100?'; c = '25%'; d = @('20%', '22.5%', '30%'); e = 'The increase is 20, and 20 / 80 = 0.25 = 25%.' },
    @{ q = 'The sum of two ages is 26. Their difference is 4. What is the younger age?'; c = '11'; d = @('10', '12', '15'); e = 'Let the ages be x and y. Solving x + y = 26 and x - y = 4 gives 15 and 11, so the younger age is 11.' },
    @{ q = 'If f(x) = 2x^2 - 3, what is f(3)?'; c = '15'; d = @('9', '12', '18'); e = 'Substitute x = 3: 2(3^2) - 3 = 2(9) - 3 = 15.' },
    @{ q = 'What is 2.5 x 0.4?'; c = '1.0'; d = @('0.5', '0.8', '10.0'); e = 'Multiply 25 by 4 to get 100, then place two decimal places to get 1.0.' },
    @{ q = 'What is the midpoint of the line segment joining (2, 4) and (6, 8)?'; c = '(4, 6)'; d = @('(3, 5)', '(4, 5)', '(5, 6)'); e = 'The midpoint is found by averaging the x-coordinates and y-coordinates: ((2 + 6)/2, (4 + 8)/2) = (4, 6).' }
  )
  'Science' = @(
    @{ q = 'Which organelle is the main site of photosynthesis in plant cells?'; c = 'chloroplast'; d = @('nucleus', 'mitochondrion', 'ribosome'); e = 'Photosynthesis takes place in chloroplasts because they contain chlorophyll.' },
    @{ q = 'What process allows plants to make food using sunlight, carbon dioxide, and water?'; c = 'photosynthesis'; d = @('respiration', 'digestion', 'evaporation'); e = 'Photosynthesis is the process plants use to produce glucose from sunlight, carbon dioxide, and water.' },
    @{ q = 'Which gas do humans release when they exhale?'; c = 'carbon dioxide'; d = @('oxygen', 'nitrogen', 'hydrogen'); e = 'Cells produce carbon dioxide during respiration, and the body removes it through exhalation.' },
    @{ q = 'Which enzyme in saliva begins the digestion of starch?'; c = 'amylase'; d = @('pepsin', 'lipase', 'insulin'); e = 'Amylase in saliva starts breaking down starch into simpler sugars.' },
    @{ q = 'Which blood vessels carry blood away from the heart?'; c = 'arteries'; d = @('veins', 'capillaries', 'bronchi'); e = 'Arteries carry blood away from the heart, while veins carry blood toward it.' },
    @{ q = 'Which part of the cell serves as the control center?'; c = 'nucleus'; d = @('cell membrane', 'vacuole', 'cytoplasm'); e = 'The nucleus contains genetic material and directs cell activities.' },
    @{ q = 'An organism has the genotype Tt for height, where T is dominant. Which description is correct?'; c = 'heterozygous'; d = @('homozygous dominant', 'homozygous recessive', 'mutation'); e = 'Tt contains two different alleles, so the genotype is heterozygous.' },
    @{ q = 'Which is an example of a physical change?'; c = 'ice melting'; d = @('wood burning', 'iron rusting', 'milk souring'); e = 'Melting changes only the state of matter, not the substance itself, so it is a physical change.' },
    @{ q = 'The atomic number of an element tells the number of'; c = 'protons'; d = @('neutrons', 'energy levels', 'bonds'); e = 'The atomic number is defined by the number of protons in the nucleus.' },
    @{ q = 'A substance with a pH lower than 7 is'; c = 'acidic'; d = @('basic', 'neutral', 'metallic'); e = 'Any solution with pH below 7 is considered acidic.' },
    @{ q = 'In a saltwater solution, the solvent is'; c = 'water'; d = @('salt', 'glass', 'air'); e = 'The solvent is the substance that dissolves the solute, and in saltwater that substance is water.' },
    @{ q = 'Newton''s first law is also called the law of'; c = 'inertia'; d = @('gravity', 'acceleration', 'momentum'); e = 'Newton''s first law describes inertia, the tendency of objects to resist changes in motion.' },
    @{ q = 'Speed is calculated by dividing'; c = 'distance by time'; d = @('time by distance', 'mass by volume', 'force by area'); e = 'Speed measures how much distance is covered in a given time.' },
    @{ q = 'The energy an object has because it is moving is called'; c = 'kinetic energy'; d = @('potential energy', 'chemical energy', 'nuclear energy'); e = 'Kinetic energy is the energy of motion.' },
    @{ q = 'Which method transfers heat through direct contact?'; c = 'conduction'; d = @('convection', 'radiation', 'reflection'); e = 'Conduction transfers heat when particles collide through direct contact.' },
    @{ q = 'A wave with greater frequency has a'; c = 'shorter wavelength'; d = @('longer wavelength', 'slower speed in all media', 'lower energy'); e = 'For waves in the same medium, higher frequency corresponds to shorter wavelength.' },
    @{ q = 'For an electric current to flow continuously, a circuit must be'; c = 'closed'; d = @('frozen', 'colorless', 'magnetic'); e = 'A closed circuit provides a complete path for electric charges to move.' },
    @{ q = 'What happens when two like magnetic poles are brought together?'; c = 'They repel each other.'; d = @('They attract each other.', 'They melt.', 'They become neutral immediately.'); e = 'Like poles repel, while unlike poles attract.' },
    @{ q = 'The movement of tectonic plates can directly cause'; c = 'earthquakes'; d = @('photosynthesis', 'digestion', 'condensation'); e = 'Tectonic plate movement releases energy in the Earth''s crust, causing earthquakes.' },
    @{ q = 'When water vapor cools and changes into liquid droplets, the process is called'; c = 'condensation'; d = @('evaporation', 'sublimation', 'melting'); e = 'Condensation happens when a gas cools and becomes liquid.' },
    @{ q = 'Climate refers to'; c = 'the long-term pattern of weather in an area'; d = @('the temperature at one exact moment', 'a single rainy afternoon', 'a short laboratory test'); e = 'Climate describes weather patterns over a long period, not day-to-day conditions.' },
    @{ q = 'The Earth''s rotation on its axis causes'; c = 'day and night'; d = @('the seasons', 'the phases of the moon', 'volcanic eruptions'); e = 'As the Earth rotates, different parts of the planet face the Sun or turn away from it, producing day and night.' },
    @{ q = 'Which moon phase comes immediately after the new moon?'; c = 'waxing crescent'; d = @('full moon', 'waning gibbous', 'third quarter'); e = 'After the new moon, the visible portion of the moon begins increasing, producing a waxing crescent.' },
    @{ q = 'In the food chain grass -> rabbit -> fox, the rabbit is a'; c = 'primary consumer'; d = @('producer', 'decomposer', 'secondary consumer'); e = 'The rabbit eats the producer, so it is the primary consumer.' },
    @{ q = 'Fungi in an ecosystem are important because they act as'; c = 'decomposers'; d = @('producers', 'predators', 'pollinators'); e = 'Fungi break down dead organic matter and recycle nutrients back into the ecosystem.' },
    @{ q = 'Sweating helps the human body maintain'; c = 'homeostasis'; d = @('mutation', 'digestion only', 'inheritance'); e = 'Sweating helps regulate body temperature, which is part of maintaining homeostasis.' },
    @{ q = 'In an experiment, a factor kept the same in all groups is called a'; c = 'controlled variable'; d = @('dependent variable', 'conclusion', 'hypothesis'); e = 'A controlled variable is kept constant so the test remains fair.' },
    @{ q = 'Which tool is best used to measure the mass of a small object?'; c = 'balance'; d = @('thermometer', 'voltmeter', 'graduated cylinder'); e = 'A balance is used to measure mass.' },
    @{ q = 'Which of the following is a renewable source of energy?'; c = 'solar energy'; d = @('coal', 'diesel', 'natural gas'); e = 'Solar energy is naturally replenished by sunlight and is therefore renewable.' },
    @{ q = 'Which gas is a major contributor to the greenhouse effect?'; c = 'carbon dioxide'; d = @('helium', 'argon', 'neon'); e = 'Carbon dioxide traps heat in the atmosphere and is one of the main greenhouse gases.' }
  )
}

foreach ($entry in $questionBank.GetEnumerator()) {
  if ($entry.Value.Count -ne 30) {
    throw "Category '$($entry.Key)' must have exactly 30 expansion questions."
  }
}

$dataset = Get-Content -Raw $OutFile | ConvertFrom-Json

foreach ($modeBlock in $dataset.modes) {
  foreach ($categoryBlock in $modeBlock.categories) {
    $categoryName = [string]$categoryBlock.category
    $existingCount = @($categoryBlock.questions).Count

    if ($existingCount -gt 60) {
      throw "Category '$categoryName' in mode '$($modeBlock.mode)' already has more than 60 questions."
    }

    if ($existingCount -eq 60) {
      continue
    }

    if (-not $questionBank.ContainsKey($categoryName)) {
      throw "No expansion bank found for category '$categoryName'."
    }

    $toAdd = 60 - $existingCount
    for ($i = 0; $i -lt $toAdd; $i++) {
      $spec = $questionBank[$categoryName][$i]
      $categoryBlock.questions += New-SeedQuestion `
        -Number ($existingCount + $i + 1) `
        -Category $categoryName `
        -Question $spec.q `
        -Correct $spec.c `
        -Distractors $spec.d `
        -Explanation $spec.e `
        -Shift (($existingCount + $i) % 4)
    }
  }
}

$total = 0
foreach ($modeBlock in $dataset.modes) {
  foreach ($categoryBlock in $modeBlock.categories) {
    $count = @($categoryBlock.questions).Count
    if ($count -ne 60) {
      throw "Validation failed: mode '$($modeBlock.mode)' category '$($categoryBlock.category)' has $count questions instead of 60."
    }

    foreach ($item in $categoryBlock.questions) {
      if (@($item.choices).Count -ne 4) {
        throw "Validation failed: '$($item.question)' does not have 4 choices."
      }
      if ($item.answer -notin @('A', 'B', 'C', 'D')) {
        throw "Validation failed: '$($item.question)' has invalid answer '$($item.answer)'."
      }
      $total++
    }
  }
}

$dataset.total_questions = $total
if ($total -ne 960) {
  throw "Validation failed: total question count is $total instead of 960."
}

$json = $dataset | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText((Resolve-Path $OutFile), $json, [System.Text.UTF8Encoding]::new($false))

Write-Host "Seed pool updated to $total questions."