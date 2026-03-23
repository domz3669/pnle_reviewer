class PromptConfig {
  final String examId;
  final Map<String, String> modeTemplates;
  final String seedRefillTemplate;
  final Map<String, String> seedRefillModeInstructions;
  final String systemPrompt;

  const PromptConfig({
    required this.examId,
    required this.modeTemplates,
    required this.seedRefillTemplate,
    required this.seedRefillModeInstructions,
    required this.systemPrompt,
  });

  factory PromptConfig.fromJson(String examId, Map<String, dynamic> json) {
    final prompts = (json['prompts'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    final modeTemplates = <String, String>{};
    for (final entry in prompts.entries) {
      final mode = entry.key;
      final value = entry.value;
      if (value is Map) {
        final template = value['template'];
        if (template is String && template.trim().isNotEmpty) {
          modeTemplates[mode] = template;
        }
      }
    }

    final seedRefill =
        (prompts['seedRefill'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final seedRefillTemplate =
        (seedRefill['template'] as String?)?.trim() ?? '';

    final seedRefillModeInstructions = <String, String>{};
    final modeInstructions =
        (seedRefill['modeInstructions'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    for (final entry in modeInstructions.entries) {
      final value = entry.value;
      if (value is String && value.trim().isNotEmpty) {
        seedRefillModeInstructions[entry.key] = value;
      }
    }

    final systemPrompt = (json['systemPrompt'] as String?)?.trim() ?? '';

    return PromptConfig(
      examId: examId,
      modeTemplates: modeTemplates,
      seedRefillTemplate: seedRefillTemplate,
      seedRefillModeInstructions: seedRefillModeInstructions,
      systemPrompt: systemPrompt,
    );
  }
}
