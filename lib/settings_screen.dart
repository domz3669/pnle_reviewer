import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'config/pnle_theme.dart';
import 'subscription_dialog.dart';

class SettingsScreen extends StatefulWidget {
  final bool isPremium;
  final bool isTrialActive;
  final DateTime? trialEndDate;
  final VoidCallback? onPremiumActivated;
  final Future<void> Function()? onRestorePurchases;
  final bool embedded;

  const SettingsScreen({
    super.key,
    required this.isPremium,
    required this.isTrialActive,
    required this.trialEndDate,
    this.onPremiumActivated,
    this.onRestorePurchases,
    this.embedded = false,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _isPremium;
  late bool _isTrialActive;
  late DateTime? _trialEndDate;

  @override
  void initState() {
    super.initState();
    _isPremium = widget.isPremium;
    _isTrialActive = widget.isTrialActive;
    _trialEndDate = widget.trialEndDate;
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update local state if widget props change
    _isPremium = widget.isPremium;
    _isTrialActive = widget.isTrialActive;
    _trialEndDate = widget.trialEndDate;
  }

  @override
  Widget build(BuildContext context) {
    final body = Container(
      decoration: const BoxDecoration(gradient: PnleTheme.appBackground),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.embedded) ...[          
            const SizedBox(height: 8),
            Text(
              'Settings',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
          ],
          // Subscription Status
          _buildSectionTitle('SUBSCRIPTION'),
          _buildSubscriptionCard(),
          const SizedBox(height: 24),

          // Information
          _buildSectionTitle('INFORMATION'),
            _buildSettingsTile(
              icon: Icons.help_outline,
              title: 'Help & FAQ',
              subtitle: 'Learn how to use the app',
              onTap: _showHelpDialog,
            ),
            const SizedBox(height: 12),
            _buildSettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              subtitle: 'Our commitment to you',
              onTap: _showPrivacyDialog,
            ),
            const SizedBox(height: 12),
            _buildSettingsTile(
              icon: Icons.info_outline,
              title: 'About',
              subtitle: 'App version & credits',
              onTap: _showAboutDialog,
            ),
            const SizedBox(height: 24),

            const SizedBox(height: 32),
          ],
        ),
      );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: PnleTheme.bgTop,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: body,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 12,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSubscriptionCard() {
    final isExpired = _isTrialActive &&
        _trialEndDate != null &&
        DateTime.now().isAfter(_trialEndDate!);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.18),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isPremium ? '👑 Premium Member' : '🎯 Free Trial',
                    style: GoogleFonts.outfit(
                      color: PnleTheme.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isPremium
                          ? Colors.green.withOpacity(0.3)
                          : Colors.amber.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _isPremium ? 'Active' : isExpired ? 'Expired' : 'Active',
                      style: GoogleFonts.outfit(
                        color: _isPremium ? Colors.green : isExpired ? Colors.red : Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_isTrialActive && !isExpired && _trialEndDate != null)
                Text(
                  'Trial expires in ${_trialEndDate!.difference(DateTime.now()).inDays} days',
                  style: GoogleFonts.outfit(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 13,
                  ),
                )
              else if (_isPremium)
                Text(
                  'Enjoy ad-free experience & unlimited explanations!',
                  style: GoogleFonts.outfit(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 13,
                  ),
                )
              else
                Text(
                  'Upgrade to Premium for unlimited access',
                  style: GoogleFonts.outfit(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 13,
                  ),
                ),
              if (!_isPremium) ...[
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _showSubscriptionDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PnleTheme.accent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    'Upgrade Now',
                    style: GoogleFonts.outfit(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color textColor = Colors.white,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: textColor.withOpacity(0.8)),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            color: textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.outfit(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
          ),
        ),
        trailing: trailing ?? Icon(Icons.chevron_right, color: textColor.withOpacity(0.6)),
      ),
    );
  }

  Widget _buildGradientDialog({
    required BuildContext context,
    required String title,
    required Widget content,
  }) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              PnleTheme.bgTop.withOpacity(0.98),
              PnleTheme.bgBottom.withOpacity(0.96),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PnleTheme.accent.withOpacity(0.32)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white.withOpacity(0.8),
                    splashRadius: 20,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: content,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: GoogleFonts.outfit(
                      color: PnleTheme.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _buildGradientDialog(
        context: context,
        title: 'Help & FAQ',
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHelpItem('How does the daily system work?',
                  'Complete 4 quiz sessions daily to track your progress.'),
              _buildHelpItem('How are scores calculated?',
                  'Scores use UPCAT weighting: Language 20%, Reading 30%, Mathematics 25%, Science 25%. Pass requires 65% overall.'),
              _buildHelpItem('When do streaks reset?',
                  'Missing a day resets your daily streak counter.'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpItem(String question, String answer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: GoogleFonts.outfit(
            color: PnleTheme.accent,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          answer,
          style: GoogleFonts.outfit(color: Colors.white.withOpacity(0.8)),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _buildGradientDialog(
        context: context,
        title: 'Privacy Policy',
        content: SingleChildScrollView(
          child: Text(
            'UPCAT AI Reviewer 2027 stores quiz progress, scores, and usage data to provide learning analytics and personalized recommendations.\n\n'
            'Your progress data is backed up through Firebase to keep your data safe across sessions.\n\n'
            'We do not sell your personal data. Third-party services used by the app may include Firebase and Google Mobile Ads.\n\n'
            'For Google Play release: replace this in-app summary with your final published Privacy Policy link and approved legal text.',
            style: GoogleFonts.outfit(color: Colors.white.withOpacity(0.8)),
          ),
        ),
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _buildGradientDialog(
        context: context,
        title: 'About UPCAT AI Reviewer 2027',
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Version 1.0.3',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A comprehensive exam preparation app powered by AI-generated questions and explanations.',
                style: GoogleFonts.outfit(color: Colors.white.withOpacity(0.8)),
              ),
              const SizedBox(height: 16),
              Text(
                'Developer',
                style: GoogleFonts.outfit(
                  color: PnleTheme.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ilocano Dev',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Contact',
                style: GoogleFonts.outfit(
                  color: PnleTheme.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'domingotambasacan@gmail.com',
                style: GoogleFonts.outfit(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '✨ Built with Flutter & Firebase',
                style: GoogleFonts.outfit(
                  color: PnleTheme.accent,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSubscriptionDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => SubscriptionDialog(
        onStartTrial: () async {
          Navigator.pop(context);
          widget.onPremiumActivated?.call();
        },
        onRestorePurchases: () async {
          Navigator.pop(context);
          await widget.onRestorePurchases?.call();
        },
        onClose: () {
          Navigator.pop(context);
        },
        triggerSource: 'settings',
      ),
    );
  }
}
