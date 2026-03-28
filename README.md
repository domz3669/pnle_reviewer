# ACET Reviewer 2027

Repository: https://github.com/domz3669/acet_reviewer_2027.git

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

## Codemagic iOS TestFlight

This repository already includes a Codemagic workflow in `codemagic.yaml` for iOS TestFlight builds.

Current workflow details:

- Workflow name: `ios-testflight`
- Trigger branch: `main`
- Apple Developer Portal integration: `Codemagic`
- App Store Connect publishing: enabled for TestFlight only
- Bundle identifier: `com.niotron.domingotambasacan.acetreviewer2027`

Required Codemagic setup:

1. Connect the GitHub repository `domz3669/acet_reviewer_2027` in Codemagic.
2. Configure the App Store Connect integration named `Codemagic`.
3. Upload the iOS distribution certificate and provisioning profile in Codemagic code signing.
4. Create or update the environment group `Secure` with these variables:
	- `GPT_API_KEY`
	- `GEMINI_API_KEY`
	- `DEEPSEEK_API_KEY`
	- `REPORT_CONTENT_WEBHOOK_URL`
5. Push to `main` to trigger the workflow.

The workflow builds an IPA and submits it to TestFlight automatically.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
