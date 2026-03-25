param(
  [string]$OutFile = "assets/seed/initial_question_pool.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

throw @'
This legacy challenge-mode seed specialization script has been disabled.

Reason:
- assets/seed/initial_question_pool.json is now a curated source of truth.
- Running this script would overwrite the curated pool with older generated challenge-mode content.

If you need to update the seed pool, edit the curated asset directly or create a new reviewed workflow that writes to a different output file.
'@

. "$PSScriptRoot\upcat_seed_banks.ps1"

$readingComprehensionChallenge = @(Get-UpcatReadingComprehensionBank)

function New-ChallengeQuestion {
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
    source = 'seed_pool_2027_challenge'
  }
}

$challengeBank = @{
  'Reading Comprehension' = @($readingComprehensionChallenge | ForEach-Object { @{ q = "$(($_.q -replace '^Passage:\s*', '')) Challenge RC"; c = $_.c; d = $_.d; e = $_.e } })
  'Language Proficiency' = @(
    @{ q = 'Read the sentence: Because the data set was incomplete, the conclusion remained tentative. The word tentative most nearly means'; c = 'not fully certain'; d = @('strongly opposed', 'carefully hidden', 'widely praised'); e = 'Tentative means provisional or not yet fully certain.' },
    @{ q = 'Which sentence contains correct parallel structure?'; c = 'The scholar liked reading, annotating, and comparing texts.'; d = @('The scholar liked reading, to annotate, and comparison of texts.', 'The scholar liked to read, annotating, and texts compared.', 'The scholar liked reading, annotation, and to compare texts.'); e = 'All three items in the correct answer use the same grammatical form.' },
    @{ q = 'Choose the best revision: The report was brief, yet it was complete, and it was persuasive too.'; c = 'The report was brief yet complete and persuasive.'; d = @('The report was brief, and complete, and persuasive too.', 'The report being brief was complete and persuasive too.', 'Brief, the report was, complete, and persuasive.'); e = 'The revision removes redundancy while preserving the meaning.' },
    @{ q = 'Which sentence uses the semicolon correctly?'; c = 'The experiment failed twice; however, the team learned from both attempts.'; d = @('The experiment failed twice; and however the team learned.', 'The experiment failed twice, however; the team learned.', 'The experiment failed twice; because the team learned.'); e = 'A semicolon can join closely related independent clauses, especially before a conjunctive adverb.' },
    @{ q = 'Read the paragraph: The mayor announced a river cleanup plan, but residents remained skeptical. Previous projects had begun with publicity and ended with little change. Volunteers still attended the first meeting, though many asked how success would be measured. Which statement best captures the central idea?'; c = 'Residents supported the goal but doubted the plan would be carried out well.'; d = @('Residents refused to attend any meetings.', 'The mayor canceled the cleanup plan immediately.', 'Volunteers believed publicity alone would solve the problem.'); e = 'The paragraph balances cautious participation with skepticism about execution.' },
    @{ q = 'Which word best completes the sentence: The witness gave an ____ account because several details contradicted each other.'; c = 'inconsistent'; d = @('eloquent', 'objective', 'vivid'); e = 'Contradictory details indicate that the account was inconsistent.' },
    @{ q = 'Which sentence avoids ambiguity?'; c = 'After Lara spoke with Nina, Lara submitted the proposal.'; d = @('After Lara spoke with Nina, she submitted the proposal.', 'When Nina met Lara, she approved it.', 'After talking, it was submitted by her.'); e = 'Repeating Lara removes the unclear pronoun reference.' },
    @{ q = 'Choose the best transition: The evidence looked convincing at first. ____, a second review revealed several missing citations.'; c = 'However'; d = @('Therefore', 'Likewise', 'Meanwhile'); e = 'However correctly signals contrast between the first impression and the later finding.' },
    @{ q = 'What can be inferred from this sentence: The professor paused before answering, then carefully redefined every key term in the question.'; c = 'The original question may have used unclear language.'; d = @('The professor did not know the topic.', 'The class had already ended.', 'The answer was unrelated to the lesson.'); e = 'Redefining every key term suggests that the wording of the question needed clarification.' },
    @{ q = 'Which sentence is punctuated correctly?'; c = 'The finalists, exhausted but hopeful, waited for the results.'; d = @('The finalists exhausted, but hopeful waited for the results.', 'The finalists, exhausted but hopeful waited, for the results.', 'The finalists exhausted but hopeful, waited for the results.'); e = 'The nonessential descriptive phrase is correctly set off with commas.' },
    @{ q = 'Choose the best topic sentence for a paragraph about evaluating online sources.'; c = 'Reliable online research depends on checking authorship, evidence, and publication context.'; d = @('Many students use laptops at school.', 'Websites can contain text and pictures.', 'Online reading is faster than printed reading.'); e = 'The sentence introduces the main criteria that a paragraph on evaluation would develop.' },
    @{ q = 'Which sentence contains a dangling modifier?'; c = 'After reading the article, the chart seemed more confusing.'; d = @('After reading the article, Mina explained the chart clearly.', 'Because the chart was complex, Mina reread the article.', 'Mina reread the article after class.'); e = 'The phrase after reading the article incorrectly appears to modify chart instead of a person.' },
    @{ q = 'Read the passage: The debate team practiced rebuttals more than opening statements this week. Their coach believed they already knew their main claims well, but needed to respond more quickly to opposing arguments. Why did the coach change the practice focus?'; c = 'The team needed stronger responses during live exchanges.'; d = @('The team forgot its main claims entirely.', 'Opening statements were removed from the competition.', 'The coach wanted shorter debates.'); e = 'The coach shifted practice because rebuttals required more improvement.' },
    @{ q = 'Which word is the best antonym for mitigate?'; c = 'intensify'; d = @('reduce', 'soften', 'balance'); e = 'Mitigate means lessen, so intensify is its opposite.' },
    @{ q = 'Choose the most precise revision: The manager was mad about the late report.'; c = 'The manager was frustrated by the delayed report.'; d = @('The manager was emotional about the late report.', 'The manager was bad about the late report.', 'The manager had feelings about the late report.'); e = 'Frustrated and delayed are more precise and formal than mad and late in this context.' },
    @{ q = 'Which sentence correctly uses a colon?'; c = 'The committee requested three revisions: clearer data labels, shorter captions, and a stronger conclusion.'; d = @('The committee requested: because the labels were weak.', 'The committee: requested three revisions that day.', 'The committee requested three: because they were concerned.'); e = 'A colon properly introduces the list that explains the revisions.' },
    @{ q = 'What is the tone of the sentence: The proposal was bold, original, and impossible to ignore.'; c = 'admiring'; d = @('indifferent', 'resentful', 'hesitant'); e = 'The positive descriptors create an admiring tone.' },
    @{ q = 'Which sentence is in the passive voice?'; c = 'The final draft was reviewed by the editor.'; d = @('The editor reviewed the final draft carefully.', 'The editor reviews every final draft.', 'The final draft impressed the editor.'); e = 'The subject receives the action in the passive construction.' },
    @{ q = 'Choose the sentence that is logically ordered for a formal paragraph. 1) Evidence from two surveys then confirmed the trend. 2) The researcher first noticed a sharp drop in attendance. 3) She later revised the schedule based on the findings. 4) After that, she interviewed participants about possible causes.'; c = '2-4-1-3'; d = @('2-1-4-3', '4-2-1-3', '1-2-4-3'); e = 'A sound sequence is notice the problem, gather causes, confirm with surveys, then revise the schedule.' },
    @{ q = 'Which sentence best supports the claim that public parks improve community life?'; c = 'Neighborhoods with active parks often report more shared events and outdoor activity.'; d = @('Some parks are painted green.', 'A park may contain trees and benches.', 'People define community in different ways.'); e = 'The sentence directly links active parks with stronger community activity.' },
    @{ q = 'Choose the best concluding sentence for a paragraph arguing that students should learn media literacy.'; c = 'For these reasons, media literacy is no longer optional but essential for informed citizenship.'; d = @('Some students also enjoy photography after class.', 'Media platforms have changed many times.', 'Teachers assign different kinds of homework.'); e = 'The sentence clearly closes the argument by restating its importance.' },
    @{ q = 'Which revision best eliminates wordiness?'; c = 'The committee met to discuss the budget.'; d = @('The committee held a meeting for the purpose of discussing the budget.', 'The committee met up together to discuss about the budget.', 'The committee had a discussion meeting regarding the budget topic.'); e = 'The shortest option is also the clearest and most direct.' },
    @{ q = 'Read the sentence: Unlike the first edition, the new textbook includes local case studies and updated graphs. Which contrast is emphasized?'; c = 'The new textbook is more current and locally relevant.'; d = @('The first edition had better paper quality.', 'The new textbook is shorter than the first edition.', 'The first edition included no text at all.'); e = 'The sentence contrasts the added case studies and updated graphs with the earlier edition.' },
    @{ q = 'Which sentence correctly uses who and whom?'; c = 'The scholar whom the panel praised later thanked the audience.'; d = @('The scholar who the panel praised later thanked the audience.', 'The scholar whom praised the panel later thanked the audience.', 'The scholar who the audience thanked was praised them.'); e = 'Whom is correct because it functions as the object of praised.' },
    @{ q = 'Which sentence has the clearest cause and effect relation?'; c = 'Because the archive was digitized, researchers found the records more quickly.'; d = @('The archive was digitized, and researchers, quickly.', 'Researchers found the records quickly although digitized.', 'The archive, because researchers, found records.'); e = 'The sentence directly states the cause and its result in a complete structure.' },
    @{ q = 'Which phrase best completes the sentence: The editor rejected the article, not because the topic lacked value, but because the argument lacked ____.'; c = 'evidence'; d = @('surprise', 'length', 'emotion'); e = 'An argument is weakened when it lacks supporting evidence.' },
    @{ q = 'Choose the best interpretation of the metaphor: The city became a furnace at noon.'; c = 'The city felt intensely hot.'; d = @('The city turned into a machine.', 'The city was silent and dark.', 'The city produced metal.'); e = 'The metaphor compares the heat of the city to the heat of a furnace.' },
    @{ q = 'Which sentence maintains formal academic tone?'; c = 'The findings suggest a strong correlation, although further study is needed.'; d = @('The findings are super convincing and basically final.', 'The results totally prove everything already.', 'The study kind of says the same thing maybe.'); e = 'The sentence is precise, cautious, and appropriately formal.' },
    @{ q = 'Read the short argument: The museum should extend evening hours because attendance rises whenever working adults can visit after 6 p.m. What is the strongest assumption?'; c = 'Higher evening attendance would justify the added operating time.'; d = @('All visitors prefer museums at night.', 'Morning attendance would disappear completely.', 'Working adults never visit on weekends.'); e = 'The recommendation depends on the assumption that the attendance gain would make longer hours worthwhile.' },
    @{ q = 'Which sentence is free of pronoun reference error?'; c = 'When Rosa handed Ana the folder, Rosa asked Ana to review it immediately.'; d = @('When Rosa handed Ana the folder, she asked her to review it immediately.', 'When Rosa handed Ana the folder, this made her review it.', 'When Rosa handed Ana the folder, it asked for review.'); e = 'Repeating the names removes the unclear pronoun references.' }
  )
  'Mathematics' = @(
    @{ q = 'Solve for x: 2(x - 3) + 5 = 3x - 4'; c = '3'; d = @('2', '4', '5'); e = 'Expanding gives 2x - 6 + 5 = 3x - 4, so 2x - 1 = 3x - 4 and x = 3.' },
    @{ q = 'A store marks an item up by 25 percent and then gives a 20 percent discount. What is the overall percent change from the original price?'; c = 'No change'; d = @('5 percent increase', '5 percent decrease', '10 percent increase'); e = 'A price of 100 becomes 125, then 125 x 0.8 = 100, so there is no net change.' },
    @{ q = 'If 3 printers can print 900 pages in 15 minutes at equal rates, how many pages can 5 printers print in 12 minutes?'; c = '1200'; d = @('900', '1000', '1500'); e = 'One printer prints 900 / (3 x 15) = 20 pages per minute. Five printers for 12 minutes print 5 x 12 x 20 = 1200 pages.' },
    @{ q = 'The sum of two numbers is 42 and their difference is 8. What is the larger number?'; c = '25'; d = @('17', '21', '29'); e = 'Let the numbers be x and y. Solving x + y = 42 and x - y = 8 gives x = 25.' },
    @{ q = 'A triangle has side lengths 7, 24, and 25. What kind of triangle is it?'; c = 'right triangle'; d = @('equilateral triangle', 'isosceles triangle', 'obtuse triangle'); e = 'Since 7^2 + 24^2 = 25^2, the triangle satisfies the Pythagorean theorem.' },
    @{ q = 'What is the value of 3^4 - 2^5?'; c = '49'; d = @('17', '31', '65'); e = '3^4 = 81 and 2^5 = 32, so the difference is 49.' },
    @{ q = 'A cylinder has radius 3 cm and height 5 cm. Using pi = 3.14, what is its volume?'; c = '141.3 cubic cm'; d = @('47.1 cubic cm', '94.2 cubic cm', '188.4 cubic cm'); e = 'Volume = pi r^2 h = 3.14 x 9 x 5 = 141.3 cubic cm.' },
    @{ q = 'If x/4 = 3/10, what is x?'; c = '6/5'; d = @('3/5', '12/5', '5/6'); e = 'Cross multiplication gives 10x = 12, so x = 12/10 = 6/5.' },
    @{ q = 'A class has 18 girls and 12 boys. What percent of the class are boys?'; c = '40 percent'; d = @('30 percent', '45 percent', '60 percent'); e = 'There are 30 students total, and 12 / 30 = 0.4 = 40 percent.' },
    @{ q = 'What is the remainder when 3^5 is divided by 7?'; c = '5'; d = @('1', '3', '6'); e = '3^5 = 243 and 243 = 7 x 34 + 5, so the remainder is 5.' },
    @{ q = 'If the mean of five numbers is 18, what is their total sum?'; c = '90'; d = @('72', '85', '108'); e = 'Mean times number of items gives the total: 18 x 5 = 90.' },
    @{ q = 'A number is increased by 15 percent and becomes 69. What was the original number?'; c = '60'; d = @('54', '57', '63'); e = 'If 1.15x = 69, then x = 69 / 1.15 = 60.' },
    @{ q = 'Solve the system: 2x + y = 11 and x - y = 1'; c = 'x = 4, y = 3'; d = @('x = 3, y = 4', 'x = 5, y = 1', 'x = 6, y = -1'); e = 'From x - y = 1, y = x - 1. Substituting into 2x + y = 11 gives 3x - 1 = 11, so x = 4 and y = 3.' },
    @{ q = 'A rectangular lot measures 18 m by 12 m. A path 1 m wide is built inside along all edges. What is the area of the remaining inner rectangle?'; c = '160 square m'; d = @('176 square m', '180 square m', '144 square m'); e = 'Subtract 2 m from each dimension to get 16 by 10, so the inner area is 160 square m.' },
    @{ q = 'What is the 8th term of the arithmetic sequence 11, 15, 19, ...?'; c = '39'; d = @('35', '41', '43'); e = 'The common difference is 4, so a8 = 11 + 7 x 4 = 39.' },
    @{ q = 'A bag contains 4 red, 5 blue, and 6 yellow beads. What is the probability of drawing a blue or yellow bead?'; c = '11/15'; d = @('5/15', '6/15', '9/15'); e = 'Blue or yellow gives 5 + 6 favorable outcomes out of 15 total, so the probability is 11/15.' },
    @{ q = 'If f(x) = 2x + 3 and g(x) = x^2, what is g(f(2))?'; c = '49'; d = @('25', '36', '64'); e = 'First compute f(2) = 7, then g(7) = 49.' },
    @{ q = 'What is the slope of a line perpendicular to a line with slope 2/3?'; c = '-3/2'; d = @('-2/3', '3/2', '2/3'); e = 'Perpendicular slopes are negative reciprocals, so the slope is -3/2.' },
    @{ q = 'If the ratio of flour to sugar is 7:3 and there are 21 cups of flour, how many cups of sugar are needed?'; c = '9'; d = @('7', '8', '12'); e = 'If 7 parts equals 21, then 1 part is 3 and 3 parts is 9.' },
    @{ q = 'A train travels at 72 km/h for 25 minutes. How far does it travel?'; c = '30 km'; d = @('24 km', '28 km', '32 km'); e = 'Twenty five minutes is 25/60 hour. Distance = 72 x 25/60 = 30 km.' },
    @{ q = 'What is the area of a sector with central angle 90 degrees in a circle of radius 8 cm?'; c = '16pi square cm'; d = @('8pi square cm', '32pi square cm', '64pi square cm'); e = 'A 90 degree sector is one fourth of the circle, so the area is 1/4 x pi x 8^2 = 16pi.' },
    @{ q = 'The expression 5a - 2b has value 19 when a = 3. What is b?'; c = '-2'; d = @('-1', '1', '2'); e = 'Substitute a = 3: 15 - 2b = 19, so -2b = 4 and b = -2.' },
    @{ q = 'Which is greater: 3/7 or 4/9?'; c = '4/9'; d = @('3/7', 'They are equal', 'Not enough information'); e = 'Cross multiply: 3 x 9 = 27 and 4 x 7 = 28, so 4/9 is larger.' },
    @{ q = 'How many diagonals does a hexagon have?'; c = '9'; d = @('6', '8', '12'); e = 'A polygon with n sides has n(n-3)/2 diagonals. For n = 6, that is 6 x 3 / 2 = 9.' },
    @{ q = 'If a number is divided by 5, the quotient is 12 and the remainder is 3. What is the number?'; c = '63'; d = @('57', '60', '67'); e = 'Number = divisor x quotient + remainder = 5 x 12 + 3 = 63.' },
    @{ q = 'Two angles are supplementary. If one angle is 4 times the other, what is the larger angle?'; c = '144 degrees'; d = @('120 degrees', '135 degrees', '150 degrees'); e = 'Let the smaller angle be x. Then x + 4x = 180, so x = 36 and the larger angle is 144 degrees.' },
    @{ q = 'What is the value of (2x - 1)(x + 3) when x = 4?'; c = '49'; d = @('35', '45', '56'); e = 'Substitute x = 4: (8 - 1)(7) = 7 x 7 = 49.' },
    @{ q = 'A mixture is 30 percent acid. How much pure acid must be added to 20 L of the mixture to make it 40 percent acid?'; c = '10/3 L'; d = @('2 L', '3 L', '4 L'); e = 'Initial acid is 6 L. If x liters of acid are added, (6 + x)/(20 + x) = 0.4, which gives x = 10/3 L.' },
    @{ q = 'What is the next term in the sequence 2, 5, 11, 23, 47, ?'; c = '95'; d = @('94', '96', '99'); e = 'Each term is doubled then 1 is added, so 47 becomes 95.' },
    @{ q = 'A student answered 42 out of 50 questions correctly. What was the score percentage?'; c = '84 percent'; d = @('82 percent', '85 percent', '88 percent'); e = '42 / 50 = 0.84, which is 84 percent.' }
  )
  'Science' = @(
    @{ q = 'A scientist changes only the amount of light reaching a plant while keeping soil, water, and temperature constant. What is the independent variable?'; c = 'amount of light'; d = @('plant height', 'soil type', 'temperature'); e = 'The independent variable is the factor intentionally changed by the scientist.' },
    @{ q = 'Which observation best supports the claim that a chemical change occurred?'; c = 'A gas formed when two clear liquids were mixed.'; d = @('Ice changed into water.', 'A metal rod became shorter when cooled.', 'Sugar dissolved in warm tea.'); e = 'Gas formation is strong evidence that a new substance formed.' },
    @{ q = 'Which organ system works most directly with the circulatory system to supply oxygen to body cells?'; c = 'respiratory system'; d = @('skeletal system', 'integumentary system', 'endocrine system'); e = 'The respiratory system loads oxygen into the blood, which the circulatory system then delivers.' },
    @{ q = 'If a diploid organism has 16 chromosomes in a body cell, how many chromosomes are expected in one gamete?'; c = '8'; d = @('4', '12', '16'); e = 'Gametes are haploid, so they contain half the chromosome number of body cells.' },
    @{ q = 'Which statement correctly compares mitosis and meiosis?'; c = 'Mitosis produces genetically similar cells, while meiosis produces cells with half the chromosome number.'; d = @('Both always produce four identical cells.', 'Meiosis is used only for growth and repair.', 'Mitosis reduces chromosome number by half.'); e = 'Mitosis maintains chromosome number, whereas meiosis halves it for sexual reproduction.' },
    @{ q = 'What is the best explanation for why ice floats on liquid water?'; c = 'Ice is less dense than liquid water.'; d = @('Ice has more salt.', 'Ice contains no molecules.', 'Ice is heavier than water.'); e = 'Floating depends on density, and solid water is less dense than liquid water.' },
    @{ q = 'An object moves at constant velocity. What can be concluded about the net force on it?'; c = 'The net force is zero.'; d = @('The net force is increasing.', 'The object has no mass.', 'The object must be accelerating.'); e = 'Constant velocity means no acceleration, so the net force must be zero.' },
    @{ q = 'A 2 kg object accelerates at 3 m/s^2. What net force acts on it?'; c = '6 N'; d = @('1.5 N', '5 N', '9 N'); e = 'By Newton second law, F = ma = 2 x 3 = 6 N.' },
    @{ q = 'Which circuit change will increase current if voltage stays constant?'; c = 'decrease the resistance'; d = @('increase the resistance', 'remove the battery terminals', 'open the switch'); e = 'Ohm law shows that with constant voltage, current increases when resistance decreases.' },
    @{ q = 'Why does a metal spoon feel colder than a wooden spoon at the same room temperature?'; c = 'Metal transfers heat away from the hand faster.'; d = @('Metal has no internal energy.', 'Wood is actually hotter.', 'Metal has lower mass in all cases.'); e = 'Metal is a better thermal conductor, so it draws heat from the hand more quickly.' },
    @{ q = 'Which layer of the Earth is mostly liquid and surrounds the inner core?'; c = 'outer core'; d = @('mantle', 'crust', 'inner core'); e = 'The outer core is liquid and lies between the mantle and the solid inner core.' },
    @{ q = 'What is the main energy source that drives the water cycle?'; c = 'the Sun'; d = @('the Moon', 'the Earth core', 'ocean salt'); e = 'Solar energy causes evaporation and powers the movement of water through the cycle.' },
    @{ q = 'Which greenhouse gas is produced in large amounts by burning fossil fuels?'; c = 'carbon dioxide'; d = @('helium', 'neon', 'argon'); e = 'Burning coal, oil, and gas releases large amounts of carbon dioxide.' },
    @{ q = 'If a dominant allele for seed color is Y and the recessive allele is y, what offspring ratio is expected from Yy x Yy?'; c = '3 dominant : 1 recessive'; d = @('1 dominant : 1 recessive', '1 dominant : 3 recessive', 'all dominant only'); e = 'A heterozygous cross gives genotypes YY, Yy, Yy, yy, which is a 3:1 phenotype ratio.' },
    @{ q = 'In a food web, removing a top predator is most likely to cause'; c = 'an increase in some prey populations'; d = @('photosynthesis to stop immediately', 'all producers to vanish at once', 'the water cycle to end'); e = 'Removing a top predator often allows some prey populations to grow rapidly.' },
    @{ q = 'Which statement about acids and bases is correct?'; c = 'Acids have more hydrogen ions than bases in solution.'; d = @('Bases always have a pH below 7.', 'Acids cannot react with metals.', 'Neutral solutions have no ions.'); e = 'Acidic solutions are characterized by a higher concentration of hydrogen ions.' },
    @{ q = 'What is the most direct role of chlorophyll in photosynthesis?'; c = 'It absorbs light energy.'; d = @('It stores oxygen in roots.', 'It produces soil minerals.', 'It cools the leaf surface.'); e = 'Chlorophyll captures light energy that drives photosynthesis.' },
    @{ q = 'Which kind of wave can travel through a vacuum?'; c = 'electromagnetic wave'; d = @('sound wave', 'seismic S-wave', 'water wave'); e = 'Electromagnetic waves do not require a material medium and can travel through space.' },
    @{ q = 'A student measures the same object three times and gets very similar values, but all are far from the true value. The measurements are'; c = 'precise but not accurate'; d = @('accurate but not precise', 'both accurate and precise', 'neither measurable nor useful'); e = 'Close agreement among trials shows precision, while distance from the true value shows poor accuracy.' },
    @{ q = 'Which process best explains how igneous rock can become sedimentary rock?'; c = 'weathering, erosion, deposition, and compaction'; d = @('melting and immediate cooling only', 'photosynthesis in buried layers', 'radioactive decay alone'); e = 'Igneous rock must be broken into sediments, moved, deposited, and compacted to become sedimentary rock.' },
    @{ q = 'Why do astronauts appear weightless while orbiting Earth?'; c = 'They are in continuous free fall around Earth.'; d = @('There is no gravity in space.', 'Their mass becomes zero.', 'Air pressure cancels their weight.'); e = 'Orbiting objects are still under gravity, but they remain in continuous free fall.' },
    @{ q = 'Which statement best describes a balanced chemical equation?'; c = 'It has the same number of each type of atom on both sides.'; d = @('It has equal numbers of molecules on both sides only.', 'It uses only one reactant.', 'It shows no energy transfer.'); e = 'Balancing preserves atoms, so each element must have equal counts on both sides.' },
    @{ q = 'What is the function of ribosomes in cells?'; c = 'protein synthesis'; d = @('energy storage', 'waste removal', 'cell division control'); e = 'Ribosomes assemble amino acids into proteins.' },
    @{ q = 'Which adaptation best helps a desert plant survive long dry periods?'; c = 'thick stems that store water'; d = @('broad thin leaves with many pores', 'soft stems with no waxy layer', 'shallow roots only at the surface'); e = 'Water storage in thick stems is a key desert adaptation.' },
    @{ q = 'Which statement about momentum is correct?'; c = 'Momentum depends on both mass and velocity.'; d = @('Momentum depends only on speed.', 'Momentum is the same as force.', 'Momentum cannot change during a collision.'); e = 'Momentum is defined as mass times velocity.' },
    @{ q = 'A sample of radioactive material has a half-life of 10 days. If it starts at 80 g, how much remains after 20 days?'; c = '20 g'; d = @('10 g', '30 g', '40 g'); e = 'After one half-life 40 g remains, and after two half-lives 20 g remains.' },
    @{ q = 'Which is the best reason biodiversity is important in ecosystems?'; c = 'Greater biodiversity usually improves ecosystem stability.'; d = @('Biodiversity prevents all natural disasters.', 'Only ecosystems with one species survive.', 'Biodiversity removes the need for producers.'); e = 'Diverse ecosystems are generally more resilient to disturbance.' },
    @{ q = 'If a convex lens forms a real image on a screen, which statement must be true?'; c = 'The object is farther than one focal length from the lens.'; d = @('The image must be upright.', 'The lens must be concave.', 'The object is at the exact center of the lens.'); e = 'A converging lens forms a real image only when the object is beyond the focal point.' },
    @{ q = 'Which variable should be graphed on the x-axis in an experiment?'; c = 'the independent variable'; d = @('the conclusion', 'the dependent variable only', 'the control group label'); e = 'The independent variable is placed on the x-axis because it is the one the experimenter changes.' },
    @{ q = 'What is the best explanation for seasons on Earth?'; c = 'the tilt of Earth axis as Earth revolves around the Sun'; d = @('changes in Earth distance from the Sun each day', 'daily cloud formation', 'the phases of the Moon'); e = 'The axial tilt changes the angle and duration of sunlight during Earth revolution, producing seasons.' }
  )
}

foreach ($entry in $challengeBank.GetEnumerator()) {
  if ($entry.Value.Count -ne 30) {
    throw "Category '$($entry.Key)' must contain exactly 30 challenge questions."
  }
}

$dataset = Get-Content -Raw $OutFile | ConvertFrom-Json

$challengeMode = $dataset.modes | Where-Object { $_.mode -eq 'challenge' } | Select-Object -First 1
if (-not $challengeMode) {
  throw 'Challenge mode not found in dataset.'
}

foreach ($categoryBlock in $challengeMode.categories) {
  $categoryName = [string]$categoryBlock.category
  if (-not $challengeBank.ContainsKey($categoryName)) {
    throw "Challenge bank missing category '$categoryName'."
  }

  $existing = @($categoryBlock.questions)
  if ($existing.Count -lt 30) {
    throw "Category '$categoryName' has fewer than 30 existing questions."
  }

  $prefix = @($existing[0..29])
  $replacement = @()
  for ($i = 0; $i -lt 30; $i++) {
    $spec = $challengeBank[$categoryName][$i]
    $replacement += New-ChallengeQuestion `
      -Number (31 + $i) `
      -Category $categoryName `
      -Question $spec.q `
      -Correct $spec.c `
      -Distractors $spec.d `
      -Explanation $spec.e `
      -Shift ($i % 4)
  }

  $categoryBlock.questions = @($prefix + $replacement)
}

$json = $dataset | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText((Resolve-Path $OutFile), $json, [System.Text.UTF8Encoding]::new($false))

Write-Host 'Challenge mode seed bank specialized successfully.'