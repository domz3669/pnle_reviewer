// ignore_for_file: constant_identifier_names

// ⚠️ GATEWAY CONFIGURATION
// API keys are server-side only (Firebase Functions).
// Authentication is handled by Firebase App Check (no secrets in client).
// Gateway URLs can be overridden via --dart-define at build time.

const String QUESTIONS_GATEWAY_URL = String.fromEnvironment(
	'QUESTIONS_GATEWAY_URL',
	defaultValue: 'https://us-central1-pnle-reviewer-ios.cloudfunctions.net/generateQuestionsGateway',
);

const String EXPLANATION_GATEWAY_URL = String.fromEnvironment(
	'EXPLANATION_GATEWAY_URL',
	defaultValue: 'https://us-central1-pnle-reviewer-ios.cloudfunctions.net/generateExplanationGateway',
);

const String REPORT_CONTENT_WEBHOOK_URL = String.fromEnvironment(
	'REPORT_CONTENT_WEBHOOK_URL',
	defaultValue: 'https://us-central1-pnle-reviewer-ios.cloudfunctions.net/reportQuestion',
);