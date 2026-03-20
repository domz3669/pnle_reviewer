import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/pnle_theme.dart';

class OnboardingScreen extends StatefulWidget {
  final ValueChanged<String> onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  final TextEditingController _nicknameController = TextEditingController();

  static const int _totalPages = 5;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter your nickname to continue.',
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    await prefs.setString('user_nickname', nickname);
    widget.onComplete(nickname);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: PnleTheme.appBackground),
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (int page) =>
                      setState(() => _currentPage = page),
                  children: [
                    _buildOnboardingPage(
                      icon: Icons.quiz_rounded,
                      title: 'Welcome to UPCAT Reviewer 2027',
                      description:
                          'Master your UPCAT preparation with high-quality questions and expert explanations.',
                      color: PnleTheme.accent,
                    ),
                    _buildOnboardingPage(
                      icon: Icons.assessment_outlined,
                      title: '4 Daily Sessions',
                      description:
                          'Complete 4 quiz sessions each day to build comprehensive exam knowledge across all categories.',
                      color: const Color(0xFF34D399),
                    ),
                    _buildOnboardingPage(
                      icon: Icons.trending_up_outlined,
                      title: 'Track Your Progress',
                      description:
                          'Scores accumulate across sessions. Aim for strong overall accuracy and steady gains across your UPCAT subject areas.',
                      color: const Color(0xFF0891B2),
                    ),
                    _buildOnboardingPage(
                      icon: Icons.lightbulb_outline,
                      title: 'Coach Explanations',
                      description:
                          'Get clear coaching notes for every question with practical step-by-step guidance.',
                      color: const Color(0xFFFF6B6B),
                    ),
                    _buildGetStartedPage(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    if (!(_currentPage == _totalPages - 1 &&
                        keyboardVisible)) ...[
                      // Dots indicator
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _totalPages,
                          (index) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: _currentPage == index ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: _currentPage == index
                                  ? PnleTheme.accent
                                  : Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Navigation buttons (only on pages before the last)
                      if (_currentPage < _totalPages - 1)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (_currentPage > 0)
                              ElevatedButton(
                                onPressed: () {
                                  _pageController.previousPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  'Back',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else
                              const SizedBox(width: 80),
                            ElevatedButton(
                              onPressed: () {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: PnleTheme.accent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                              child: Text(
                                'Next',
                                style: GoogleFonts.outfit(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOnboardingPage({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(icon, size: 64, color: Colors.white),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 28,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            description,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 16,
              height: 1.6,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGetStartedPage() {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final keyboardVisible = viewInsets.bottom > 0;
    final isReady = _nicknameController.text.trim().isNotEmpty;

    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        const SizedBox(height: 8),
                        if (!keyboardVisible) ...[
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  PnleTheme.accent,
                                  PnleTheme.accent.withValues(alpha: 0.5),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Icon(Icons.rocket_launch_rounded,
                                size: 64, color: Colors.white),
                          ),
                          const SizedBox(height: 24),
                        ],
                        Text(
                          'Ready to Start!',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: keyboardVisible ? 24 : 28,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (!keyboardVisible)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
                            child: Column(
                              children: [
                                _buildBenefitRow(
                                  icon: Icons.insights_rounded,
                                  title: 'Smart Practice Sessions',
                                  description:
                                      'Clear feedback after every completed quiz',
                                ),
                                const SizedBox(height: 14),
                                _buildBenefitRow(
                                  icon: Icons.assessment_outlined,
                                  title: 'Daily Progress Tracking',
                                  description:
                                      'Complete 4 sessions to finish your daily mock',
                                ),
                                const SizedBox(height: 14),
                                _buildBenefitRow(
                                  icon: Icons.local_fire_department_rounded,
                                  title: 'Build Your Streak',
                                  description:
                                      'Stay consistent to build your study streak',
                                ),
                                const SizedBox(height: 14),
                                _buildBenefitRow(
                                  icon: Icons.auto_awesome_rounded,
                                  title: 'High-Quality Questions',
                                  description:
                                      'Fresh questions prepared every session',
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Column(
                      children: [
                        TextField(
                          controller: _nicknameController,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) {
                            if (_nicknameController.text.trim().isNotEmpty) {
                              _completeOnboarding();
                            }
                          },
                          onTapOutside: (_) => FocusScope.of(context).unfocus(),
                          style: GoogleFonts.outfit(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Nickname (required)',
                            labelStyle:
                                GoogleFonts.outfit(color: Colors.white70),
                            hintText: 'Ex. Nika or Miko',
                            hintStyle:
                                GoogleFonts.outfit(color: Colors.white38),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.08),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.25),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: PnleTheme.accent),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isReady
                                ? () {
                                    FocusScope.of(context).unfocus();
                                    _completeOnboarding();
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: PnleTheme.accent,
                              disabledBackgroundColor:
                                  Colors.white.withValues(alpha: 0.16),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Get Started',
                              style: GoogleFonts.outfit(
                                color: isReady ? Colors.black : Colors.white54,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBenefitRow({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      children: [
        Icon(icon, color: PnleTheme.accent, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                description,
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
