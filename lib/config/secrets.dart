// ignore_for_file: constant_identifier_names

// ⚠️ GATEWAY CONFIGURATION
// API keys are server-side only (Firebase Functions).
// Authentication is handled by Firebase App Check (no secrets in client).
// Only gateway URLs are needed client-side, set via --dart-define at build time.

const String QUESTIONS_GATEWAY_URL = String.fromEnvironment(
	'QUESTIONS_GATEWAY_URL',
	defaultValue: '',
);

const String EXPLANATION_GATEWAY_URL = String.fromEnvironment(
	'EXPLANATION_GATEWAY_URL',
	defaultValue: '',
);

const String REPORT_CONTENT_WEBHOOK_URL = String.fromEnvironment(
	'REPORT_CONTENT_WEBHOOK_URL',
	defaultValue: '',
);