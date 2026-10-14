# Expense Tracker

Android-first Flutter expense tracker designed to work locally on the phone.

## Main features

- SMS transaction detection with user-controlled permission.
- PhonePe notification tracking through Android Notification Access.
- Hybrid on-device classification: safety rules + tiny neural model + context overrides + merchant rules.
- UPI payment screen that opens PhonePe/UPI apps and keeps the note locally before payment.
- Expense, income, investment, transfer and refund transaction types.
- Merchant rules and categories.
- Learning from corrections: editing a detected transaction can create a local merchant override for future messages.
- Confidence-aware auto-save: low-confidence or pending messages are ignored instead of being added automatically.
- Monthly budget and category budgets.
- Reports and recent transactions.
- Daily summary and transaction notifications.
- SQLite local storage; no backend or cloud sync.
- Startup is non-blocking: Flutter renders first, then database/alarm initialization runs with error handling.


## Enhanced UI (v1.3)

- Premium finance-style dashboard with a monthly spending hero card.
- Budget progress and remaining amount surfaced immediately.
- Quick actions for UPI payment, manual entry and budgets.
- Cleaner transaction cards with type-aware icons, amount emphasis, notes and ML confidence.
- Refined Material 3 theme, spacing, cards, chips, buttons and navigation.
- Improved loading, empty, error and settings states.
- Bottom navigation keeps the five core areas easy to reach: Home, Activity, Pay, Reports and Settings.

## Hybrid ML classification

The app does not rely on a single regex or a large LLM. Incoming SMS and PhonePe notification text follows this pipeline:

```text
Message
  -> hard safety gate
     - OTP / promotional / collect requests -> ignore
     - future or scheduled debit -> pending -> ignore
  -> tiny on-device neural classifier
     - ignore / pending / expense / income / refund / transfer / investment
  -> deterministic context override
     - refund/reversal, credit, self-transfer, investment, completed debit
  -> user/default merchant rule
  -> confidence threshold
  -> category + merchant extraction
  -> deduplication
  -> local SQLite
```

The embedded model is a small MLP:

```text
hashed unigram + bigram features (192)
  -> ReLU hidden layer (24)
  -> softmax output (7 classes)
```

It runs directly in Kotlin and needs no network, TensorFlow Lite runtime, external model download, or cloud API. The embedded weight block is well below 1 MB.

Example handled correctly:

```text
Rs 301.00 will be debited on 13-Oct-26 towards Autopay...
```

This is classified as `pending` and is **not** saved as a completed expense.

Developer training examples are in `ml/training_samples.json`, and a reproducible developer-side trainer is in `tools/train_classifier.py`. The runtime app does not need Python or NumPy.

## PhonePe notes

If a payment is started from this app, the note is saved locally before PhonePe opens and is also passed as the UPI `tn` parameter. This avoids depending on PhonePe exposing its private transaction history or note field to third-party apps.

For payments initiated directly inside PhonePe, this app can only use what PhonePe exposes in Android notifications. If the note is not present in the notification text, Android does not provide a general public API to read it from PhonePe's private transaction history.

## Build on GitHub

1. Extract this ZIP.
2. Upload the extracted project contents to the root of your GitHub repository.
3. Keep `.github/workflows/build-apk.yml` in place.
4. Commit to `main`.
5. Open GitHub **Actions** > **Build Android APK**.
6. Download the `expense-tracker-apk` artifact when the workflow finishes.

## Android permissions

The app requests sensitive Android capabilities only when the relevant feature is enabled:

- `RECEIVE_SMS` for incoming bank/payment SMS detection.
- Notification access for PhonePe notification tracking.
- `POST_NOTIFICATIONS` for local alerts on Android 13+.

SMS and notification content stays on the device in the local SQLite database.

## Limitations

- The included model is a compact product classifier trained on representative synthetic banking/UPI message patterns. It should be tested against real messages from the banks and payment apps you use before relying on it broadly.
- Android/PhonePe can change notification wording at any time; low-confidence messages are intentionally ignored rather than guessed.
- PhonePe private transaction-history notes are not directly readable by this app.

## v10: historical SMS + full transaction details + analytics

- Tap any transaction to open a full detail view with amount, category, source, sender, account hint, UPI/reference, classifier confidence, note, and the complete raw SMS/PhonePe message when available.
- Settings → **Import previous SMS** asks for `READ_SMS` only when the user explicitly chooses to import. Existing inbox messages are scanned locally with the same hybrid classifier and deduplicated before insertion.
- Reports now support **Monthly** and **Yearly** views, a 12-month spending graph, top category, top merchant, largest single expense, category distribution, and top-merchant totals.
- Transaction filter chips use explicit selected/unselected contrast so labels remain readable.

### Android SMS permission note

`READ_SMS` and `RECEIVE_SMS` are sensitive Android permissions. They are appropriate for a directly installed/internal build only when the user understands and enables the feature. Public Google Play distribution is subject to Google Play SMS/Call Log permission policy and may require an eligible core-SMS use case or a policy exception.


## UPI QR scanner
The Pay screen can scan standard UPI QR codes, populate payment fields, and requires user review before launching the UPI app.


## UPI QR payments
- Pay screen supports both QR scanning and manual UPI ID entry.
- Uses the device camera to scan standard `upi://pay` QR codes.
- Extracts payee UPI ID (`pa`), payee name (`pn`), amount (`am`), note (`tn`) and transaction reference (`tr`) when available.
- QR scanning never launches payment automatically. The user reviews all populated fields and taps Pay.
- Camera access is requested only when the scanner is opened.
