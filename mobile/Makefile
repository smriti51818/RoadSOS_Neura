ENV_FILE := .env

# ── Run ────────────────────────────────────────────────────────────────────────
run:
	flutter run --dart-define-from-file=$(ENV_FILE)

run-release:
	flutter run --release --dart-define-from-file=$(ENV_FILE)

# ── Build APK ─────────────────────────────────────────────────────────────────
build:
	flutter build apk --release --dart-define-from-file=$(ENV_FILE)

build-debug:
	flutter build apk --debug --dart-define-from-file=$(ENV_FILE)

# ── Install to connected device ───────────────────────────────────────────────
install: build
	adb install -r build/app/outputs/flutter-apk/app-release.apk

.PHONY: run run-release build build-debug install
