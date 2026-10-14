# Expense Tracker — Smart Finance Edition

Local-first Flutter Android personal-finance app. Transactions are detected from incoming bank/payment SMS and supported payment notifications, classified on-device, deduplicated, and stored in SQLite. No backend is required.

## Core tracking

- Incoming SMS transaction detection with Android `BroadcastReceiver`
- Optional historical SMS import after explicit `READ_SMS` permission
- PhonePe notification tracking after explicit Notification Access permission
- Manual transactions
- UPI payments with notes saved locally before opening the UPI app
- UPI QR scanner with review-before-pay flow
- Full raw SMS/notification text available from transaction details
- Local SQLite database and local-only classification

## Hybrid ML classification

The transaction pipeline combines deterministic safety gates, a tiny on-device neural classifier, contextual overrides, merchant rules and confidence thresholds. OTPs, promotional messages, collect requests and future/pending debits such as “will be debited” are filtered before they can become expenses. Low-confidence financial messages are sent to **Needs Review** instead of being silently trusted.

Manual corrections create local merchant overrides and feedback records. The ML Feedback screen summarizes accepted/corrected/reviewed classifications.

## Smart finance enhancements

- Smart transfer matching between detected own-account debit/credit pairs
- Cross-source duplicate detection across SMS, PhonePe and UPI records
- Recurring/subscription detection for weekly/monthly/quarterly/yearly patterns
- Account detection from SMS sender/account hints, with per-account spending
- Merchant normalization/aliases
- Advanced search by text, type, category, source, account, amount and date
- Cash-flow dashboard with savings rate, daily average and projected month spend
- Spending anomaly detection and budget forecasting
- Local smart alerts for anomalies, forecasts and upcoming recurring payments
- Receipt camera/gallery import with on-device ML Kit OCR, tax/date/item-line extraction
- CSV export and PDF report export
- Passphrase-protected AES-256-GCM backup/restore
- Split transactions across categories
- Needs Review queue for uncertain ML classifications
- Budget forecasting and recurring-payment insights
- Biometric/device lock and Android secure-screen protection
- Light/dark mode
- Android home-screen spending widget
- Notification actions: Food, Shopping, Transfer, Ignore
- Net-worth tracking for assets, liabilities and selected account balances

## Privacy

SMS, notifications, receipts, notes, classifications, budgets and backup data stay on the device unless the user explicitly exports/shares them. The app does not require a server.

Android SMS permissions are restricted for Google Play distribution. A sideloaded/internal build can request them normally, but publishing through Google Play requires compliance with Google Play's SMS/Call Log permission policy.

## Build

This repository includes `.github/workflows/build-apk.yml`. Push the extracted project contents to the repository root and GitHub Actions will build a debug APK.

The workflow creates a fresh Android Flutter shell, restores this project's `lib`, `pubspec.yaml`, and `android/app/src/main`, then runs `flutter pub get` and `flutter build apk --debug`.

## Important permissions

- `RECEIVE_SMS` — incoming transaction SMS
- `READ_SMS` — optional historical SMS import
- `POST_NOTIFICATIONS` — transaction/budget/smart alerts
- Notification listener access — optional PhonePe notification tracking
- `CAMERA` — UPI QR and receipt scanning
- `USE_BIOMETRIC` — optional local app lock

## Project structure

- `lib/main.dart` — main UI, transaction details, QR payment, reports/settings
- `lib/enhancements.dart` — smart finance hub and advanced features
- `lib/app_db.dart` — SQLite schema, analytics, smart matching, backup data
- `lib/models.dart` — data models
- `lib/native_bridge.dart` — Flutter ↔ Android method channel
- `android/app/src/main/kotlin/...` — SMS receiver, notification listener, hybrid parser, notifications, widget and UPI integration
- `ml/` and `tools/` — tiny classifier samples/training utility


## v13 classification/report fixes
- Pending/future debits such as “will be debited” are excluded from transactions and reports.
- Failed/reversed notices without a confirmed credit (for example insufficient-balance SIP reversals) are ignored as no-cash-movement events.
- Existing imported SMS can be reclassified from Settings, and one cleanup pass runs after upgrade.
- Report insight cards are responsive on narrow phones; long amounts and merchant/category names no longer collapse vertically.
- Transaction details preserve paise with two-decimal amount display.


## v14 credit-card payment / spam fixes
- Credit-card bill-payment confirmations such as “payment has been received towards your ... Credit Card” are hard-classified as **Transfer → Credit Card Payment**, never Refund/Income/Expense.
- The transfer keeps the card last-4/account hint and uses payment method **Bank → Credit Card**.
- Explicit carrier/device spam warnings and stock-tip / option-chain / trading-signal messages are hard-rejected before the neural classifier.
- Generic refund wording no longer wins by itself; a refund now requires completed refund/credit-back language.
- Upgrade cleanup key is bumped to v14 so previously imported SMS records are automatically reclassified with these rules.
- Exact regression examples are stored in `tools/classifier_regression_cases.json` and added to ML training samples.
