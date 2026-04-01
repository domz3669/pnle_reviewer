import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _onboardCream = Color(0xFFEBF2FA);
const _onboardPanel = Color(0xFFE0ECF5);
const _onboardText = Color(0xFF2D5070);
const _onboardTextSoft = Color(0xFF6B8FA8);
const _onboardBorder = Color(0xA4A8C5D8);
const _onboardLeaf = Color(0xFF5B8DB8);
const _onboardLeafSoft = Color(0xFFC8DCE8);
const _onboardSky = Color(0xFF6088B0);
const _onboardSkySoft = Color(0xFFE0EBF5);
const _onboardWarm = Color(0xFF8A7AA0);
const _onboardWarmSoft = Color(0xFFE4E0EE);
const _onboardButter = Color(0xFF5A7FA0);
const _onboardButterSoft = Color(0xFFDDEAF5);

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  final TextEditingController _nicknameController = TextEditingController();
  String? _nicknameError;
  bool _isSubmitting = false;

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
    if (_isSubmitting) return;

    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      setState(() {
        _nicknameError = 'Please enter your nickname to continue.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _nicknameError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_complete', true);
      await prefs.setString('user_nickname', nickname);
      if (!mounted) return;
      Navigator.of(context).pop(nickname);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _onboardCream,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(_onboardPanel, _onboardLeafSoft, 0.24)!,
                _onboardPanel,
                Color.lerp(_onboardPanel, _onboardSkySoft, 0.22)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
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
                      title: 'Welcome to PNLE Reviewer 2027',
                      description:
                          'Master your PNLE preparation with high-quality questions and expert explanations.',
                      color: _onboardLeaf,
                      softColor: _onboardLeafSoft,
                    ),
                    _buildOnboardingPage(
                      icon: Icons.assessment_outlined,
                      title: '4 Daily Sessions',
                      description:
                          'Complete 4 quiz sessions each day to build comprehensive exam knowledge across all categories.',
                      color: _onboardButter,
                      softColor: _onboardButterSoft,
                    ),
                    _buildOnboardingPage(
                      icon: Icons.trending_up_outlined,
                      title: 'Track Your Progress',
                      description:
                          'Scores accumulate across sessions. Aim for strong overall accuracy and steady gains across your PNLE subject areas.',
                      color: _onboardSky,
                      softColor: _onboardSkySoft,
                    ),
                    _buildOnboardingPage(
                      icon: Icons.lightbulb_outline,
                      title: 'Coach Explanations',
                      description:
                          'Get clear coaching notes for every question with practical step-by-step guidance.',
                      color: _onboardWarm,
                      softColor: _onboardWarmSoft,
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
                                  ? _onboardLeaf
                                  : _onboardBorder.withValues(alpha: 0.55),
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
                                  backgroundColor: _onboardCream,
                                  foregroundColor: _onboardText,
                                  side: const BorderSide(color: _onboardBorder),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  'Back',
                                  style: GoogleFonts.outfit(
                                    color: _onboardText,
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
                                backgroundColor: _onboardLeaf,
                                foregroundColor: _onboardCream,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                              child: Text(
                                'Next',
                                style: GoogleFonts.outfit(
                                  color: _onboardCream,
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
    required Color softColor,
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
                colors: [
                  softColor,
                  Color.lerp(softColor, _onboardCream, 0.28)!,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: color.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, size: 64, color: color),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: _onboardText,
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
              color: _onboardTextSoft,
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
                                  _onboardLeafSoft,
                                  Color.lerp(
                                    _onboardLeafSoft,
                                    _onboardCream,
                                    0.28,
                                  )!,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: _onboardLeaf.withValues(alpha: 0.2),
                              ),
                            ),
                            child: const Icon(
                              Icons.rocket_launch_rounded,
                              size: 64,
                              color: _onboardLeaf,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        Text(
                          'Ready to Start!',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: _onboardText,
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
                                color: _onboardBorder,
                              ),
                              color: _onboardCream,
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
                          onChanged: (_) {
                            final nextError =
                                _nicknameController.text.trim().isEmpty
                                    ? _nicknameError
                                    : null;
                            setState(() {
                              _nicknameError = nextError;
                            });
                          },
                          onSubmitted: (_) {
                            if (!_isSubmitting &&
                                _nicknameController.text.trim().isNotEmpty) {
                              _completeOnboarding();
                            }
                          },
                          onTapOutside: (_) => FocusScope.of(context).unfocus(),
                          enabled: !_isSubmitting,
                          style: GoogleFonts.outfit(color: _onboardText),
                          decoration: InputDecoration(
                            labelText: 'Nickname (required)',
                            labelStyle: GoogleFonts.outfit(
                              color: _onboardTextSoft,
                            ),
                            hintText: 'Ex. Nika or Miko',
                            hintStyle: GoogleFonts.outfit(
                              color: _onboardTextSoft.withValues(alpha: 0.55),
                            ),
                            filled: true,
                            fillColor: _onboardCream,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: _onboardBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _onboardLeaf),
                            ),
                            errorText: _nicknameError,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isReady && !_isSubmitting
                                ? () {
                                    FocusScope.of(context).unfocus();
                                    _completeOnboarding();
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _onboardLeaf,
                              foregroundColor: _onboardCream,
                              disabledBackgroundColor: _onboardPanel,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _isSubmitting ? 'Saving...' : 'Get Started',
                              style: GoogleFonts.outfit(
                                color: isReady && !_isSubmitting
                                    ? _onboardCream
                                    : _onboardTextSoft,
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
        Icon(icon, color: _onboardLeaf, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  color: _onboardText,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                description,
                style: GoogleFonts.outfit(
                  color: _onboardTextSoft,
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
