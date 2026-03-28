import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'config/pnle_theme.dart';

const _settingsCream = Color(0xFFFCF6EB);
const _settingsPanel = Color(0xFFF9F3E7);
const _settingsLeaf = Color(0xFF7EA468);
const _settingsLeafSoft = Color(0xFFDDEBCE);
const _settingsText = Color(0xFF5A7652);
const _settingsTextSoft = Color(0xFF8AA081);
const _settingsBorder = Color(0xA4C5D6AE);

class SettingsScreen extends StatefulWidget {
  final String nickname;
  final Future<void> Function(String nickname)? onNicknameChanged;
  final bool muteAllSounds;
  final Future<void> Function(bool muted)? onMuteAllSoundsChanged;
  final bool notificationsEnabled;
  final Future<bool> Function(bool enabled)? onNotificationsChanged;
  final bool strictTimingEnabled;
  final Future<void> Function(bool enabled)? onStrictTimingChanged;
  final bool embedded;

  const SettingsScreen({
    super.key,
    this.nickname = '',
    this.onNicknameChanged,
    this.muteAllSounds = false,
    this.onMuteAllSoundsChanged,
    this.notificationsEnabled = false,
    this.onNotificationsChanged,
    this.strictTimingEnabled = false,
    this.onStrictTimingChanged,
    this.embedded = false,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nicknameController;
  late bool _muteAllSounds;
  late bool _notificationsEnabled;
  late bool _strictTimingEnabled;
  String _appVersionLabel = 'Version';

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.nickname);
    _muteAllSounds = widget.muteAllSounds;
    _notificationsEnabled = widget.notificationsEnabled;
    _strictTimingEnabled = widget.strictTimingEnabled;
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final versionLabel =
        'Version ${packageInfo.version} (Build ${packageInfo.buildNumber})';

    if (!mounted) {
      return;
    }

    setState(() {
      _appVersionLabel = versionLabel;
    });
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_nicknameController.text != widget.nickname) {
      _nicknameController.text = widget.nickname;
    }
    _muteAllSounds = widget.muteAllSounds;
    _notificationsEnabled = widget.notificationsEnabled;
    _strictTimingEnabled = widget.strictTimingEnabled;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = Container(
      decoration: const BoxDecoration(color: _settingsCream),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.embedded) const SizedBox(height: 8),
          _buildSectionTitle('PROFILE'),
          _buildSettingsTile(
            icon: Icons.person_outline,
            title: 'Nickname',
            subtitle: _nicknameController.text.trim().isEmpty
                ? 'Set your display name'
                : _nicknameController.text.trim(),
            trailing: const Icon(Icons.edit_rounded, color: _settingsTextSoft),
            onTap: _showNicknameDialog,
          ),
          const SizedBox(height: 24),

          _buildSectionTitle('AUDIO'),
          _buildToggleTile(
            icon: Icons.volume_off_rounded,
            title: 'Mute All Sounds',
            subtitle: 'Disable sound effects and result music',
            tileKey: const Key('toggle_mute_all_sounds'),
            value: _muteAllSounds,
            onChanged: (value) async {
              setState(() => _muteAllSounds = value);
              await widget.onMuteAllSoundsChanged?.call(value);
            },
          ),
          const SizedBox(height: 24),

          _buildSectionTitle('NOTIFICATIONS'),
          _buildToggleTile(
            icon: Icons.notifications_active_outlined,
            title: 'Study Notifications',
            subtitle: 'Daily session reset and ad refill alerts',
            tileKey: const Key('toggle_notifications'),
            value: _notificationsEnabled,
            onChanged: (value) async {
              final applied =
                  await widget.onNotificationsChanged?.call(value) ?? value;
              if (!mounted) return;
              setState(() => _notificationsEnabled = applied);
            },
          ),
          const SizedBox(height: 24),

          _buildSectionTitle('TEST MODE'),
          _buildToggleTile(
            icon: Icons.timer_rounded,
            title: 'Strict ACET Timing',
            subtitle: 'Use exam-speed timer and auto-next on timeout',
            tileKey: const Key('toggle_strict_timing'),
            value: _strictTimingEnabled,
            onChanged: (value) async {
              setState(() => _strictTimingEnabled = value);
              await widget.onStrictTimingChanged?.call(value);
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
            color: _settingsText,
          ),
        ),
        backgroundColor: _settingsCream,
        elevation: 0,
        iconTheme: const IconThemeData(color: _settingsText),
      ),
      body: body,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        color: _settingsText,
        fontWeight: FontWeight.bold,
        fontSize: 13,
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
    Color textColor = _settingsText,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _settingsPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _settingsBorder),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: _settingsLeaf),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            color: _settingsText,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.outfit(
            color: _settingsTextSoft,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing:
            trailing ?? Icon(Icons.chevron_right, color: _settingsTextSoft),
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Key? tileKey,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _settingsPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _settingsBorder),
      ),
      child: SwitchListTile(
        key: tileKey,
        value: value,
        onChanged: onChanged,
        activeThumbColor: _settingsLeaf,
        activeTrackColor: _settingsLeafSoft,
        inactiveThumbColor: const Color(0xFFF8F1E6),
        inactiveTrackColor: const Color(0xFFE6E8D7),
        secondary: Icon(icon, color: _settingsLeaf),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            color: _settingsText,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.outfit(
            color: _settingsTextSoft,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
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
          color: _settingsPanel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _settingsBorder),
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
                        color: _settingsText,
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: _settingsTextSoft,
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
                      color: _settingsLeaf,
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
                  'Scores currently weight the four ACET categories evenly: English 25%, Mathematics 25%, Logical Reasoning 25%, Mental Ability / Abstract 25%.'),
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
              style: GoogleFonts.outfit(color: _settingsText),
              decoration: InputDecoration(
                hintText: 'Enter your nickname',
                hintStyle: GoogleFonts.outfit(color: _settingsTextSoft),
                counterStyle: GoogleFonts.outfit(color: _settingsTextSoft),
                filled: true,
                fillColor: _settingsCream,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _settingsBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _settingsLeaf),
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
                  backgroundColor: _settingsLeafSoft,
                  foregroundColor: _settingsText,
                  elevation: 0,
                  side: const BorderSide(color: _settingsBorder),
                ),
                child: Text(
                  'Save Nickname',
                  style: GoogleFonts.outfit(
                    color: _settingsText,
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
            color: _settingsLeaf,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          answer,
          style: GoogleFonts.outfit(
            color: _settingsTextSoft,
            fontWeight: FontWeight.w600,
          ),
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
            'ACET Reviewer 2027 stores quiz progress, scores, nickname, and session usage data so your study history and readiness insights can persist across sessions.\n\n'
            'The app uses Firebase to back up progress and Google Mobile Ads for ad delivery. Coach Note explanations use online generative AI services when you request them from a quiz.\n\n'
            'Offline quiz play can continue with local seeded question sets, while syncing, rewards, and AI explanations wait until internet access returns.\n\n'
            'We do not sell your personal data. Publish a full external privacy policy in App Store Connect and keep this summary aligned with it.',
            style: GoogleFonts.outfit(
              color: _settingsTextSoft,
              fontWeight: FontWeight.w600,
            ),
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
        title: 'About ACET Reviewer 2027',
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _appVersionLabel,
                style: GoogleFonts.outfit(
                  color: _settingsText,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A native ACET review app with local quiz modes, progress tracking, and optional AI-generated coaching notes.',
                style: GoogleFonts.outfit(
                  color: _settingsTextSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Developer',
                style: GoogleFonts.outfit(
                  color: _settingsLeaf,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ilocano Dev',
                style: GoogleFonts.outfit(
                  color: _settingsText,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Contact',
                style: GoogleFonts.outfit(
                  color: _settingsLeaf,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'domingotambasacan@gmail.com',
                style: GoogleFonts.outfit(
                  color: _settingsText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '✨ Built with Flutter & Firebase',
                style: GoogleFonts.outfit(
                  color: _settingsLeaf,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
