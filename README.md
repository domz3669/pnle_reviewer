# ustet_reviewer

Repository: https://github.com/domz3669/ustet_reviewer.git

A new Flutter project.

## Run With Secrets

Local runs and release builds require Dart defines for remote services.

Example PowerShell run:

```powershell
flutter run \
	--dart-define=GPT_API_KEY=$env:GPT_API_KEY \
	--dart-define=GEMINI_API_KEY=$env:GEMINI_API_KEY \
	--dart-define=DEEPSEEK_API_KEY=$env:DEEPSEEK_API_KEY \
	--dart-define=REPORT_CONTENT_WEBHOOK_URL=$env:REPORT_CONTENT_WEBHOOK_URL
```

Codemagic/TestFlight builds must also provide `REPORT_CONTENT_WEBHOOK_URL` in the `Secure` environment group.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
