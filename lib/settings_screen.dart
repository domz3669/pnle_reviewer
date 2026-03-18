import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/pnle_theme.dart';

class SettingsScreen extends StatefulWidget {
  final String nickname;
  final Future<void> Function(String nickname)? onNicknameChanged;
  final bool muteAllSounds;
  final Future<void> Function(bool muted)? onMuteAllSoundsChanged;
  final bool embedded;

  const SettingsScreen({
    super.key,
    this.nickname = '',
    this.onNicknameChanged,
    this.muteAllSounds = false,
    this.onMuteAllSoundsChanged,
    this.embedded = false,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nicknameController;
  late bool _muteAllSounds;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.nickname);
    _muteAllSounds = widget.muteAllSounds;
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_nicknameController.text != widget.nickname) {
      _nicknameController.text = widget.nickname;
    }
    _muteAllSounds = widget.muteAllSounds;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
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
          _buildSectionTitle('PROFILE'),
          _buildSettingsTile(
            icon: Icons.person_outline,
            title: 'Nickname',
            subtitle: _nicknameController.text.trim().isEmpty
                ? 'Set your display name'
                : _nicknameController.text.trim(),
            trailing: const Icon(Icons.edit_rounded, color: Colors.white70),
            onTap: _showNicknameDialog,
          ),
          const SizedBox(height: 24),

          _buildSectionTitle('AUDIO'),
          _buildToggleTile(
            icon: Icons.volume_off_rounded,
            title: 'Mute All Sounds',
            subtitle: 'Disable sound effects and result music',
            value: _muteAllSounds,
            onChanged: (value) async {
              setState(() => _muteAllSounds = value);
              await widget.onMuteAllSoundsChanged?.call(value);
            },
          ),
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: textColor.withValues(alpha: 0.8)),
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
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
        trailing: trailing ??
            Icon(Icons.chevron_right, color: textColor.withValues(alpha: 0.6)),
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: PnleTheme.accent,
        secondary: Icon(icon, color: Colors.white.withValues(alpha: 0.8)),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.outfit(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
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
              PnleTheme.bgTop.withValues(alpha: 0.98),
              PnleTheme.bgBottom.withValues(alpha: 0.96),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PnleTheme.accent.withValues(alpha: 0.32)),
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
                    color: Colors.white.withValues(alpha: 0.8),
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

  void _showNicknameDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _buildGradientDialog(
        context: context,
        title: 'Edit Nickname',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nicknameController,
              autofocus: true,
              maxLength: 24,
              style: GoogleFonts.outfit(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter your nickname',
                hintStyle: GoogleFonts.outfit(color: Colors.white38),
                counterStyle: GoogleFonts.outfit(color: Colors.white54),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: PnleTheme.accent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final updated = _nicknameController.text.trim();
                  if (updated.isEmpty) return;
                  await widget.onNicknameChanged?.call(updated);
                  if (!mounted) return;
                  setState(() {
                    _nicknameController.text = updated;
                  });
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: PnleTheme.accent,
                ),
                child: Text(
                  'Save Nickname',
                  style: GoogleFonts.outfit(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
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
          style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.8)),
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
            style:
                GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.8)),
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
                'Version 1.0.4',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A comprehensive exam preparation app powered by AI-generated questions and explanations.',
                style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.8)),
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
                  color: Colors.white.withValues(alpha: 0.9),
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
}
