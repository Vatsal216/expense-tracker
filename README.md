# Expense Tracker — Flutter + Android SMS Auto Tracking

This is a local-only MVP. There is no backend.

## What is included

- Flutter UI: Home, Transactions, Budgets, Reports, Settings.
- Android `SMS_RECEIVED` BroadcastReceiver.
- Financial SMS filter (ignores OTP-style messages).
- Local amount/type/payment-method parsing.
- Case-insensitive `SMS contains(keyword)` merchant rules.
- User rules have priority over default rules.
- SQLite shared by Flutter and Kotlin.
- Expense / Investment / Income / Transfer / Refund.
- Manual transactions and custom categories.
- Overall and category monthly budgets.
- Budget warning in transaction notifications.
- Configurable daily summary (default around 9 PM).
- Boot receiver to restore the summary schedule.

## Setup

The archive intentionally lets your installed Flutter SDK generate its own compatible Gradle wrapper/toolchain files.

```bash
cd expense_tracker_sms_mvp
chmod +x bootstrap.sh
./bootstrap.sh
flutter pub get
flutter run
```

Test on a real Android phone with a SIM/SMS inbox. Emulators normally do not represent your real bank-SMS flow.

## SMS flow

```text
Bank/payment SMS
    ↓
SmsReceiver.kt
    ↓
TransactionParser.looksFinancial()
    ↓
Extract amount / type / payment method
    ↓
ExpenseDatabase.findRule()
    ↓
fullSms.lowercase().contains(rule.keyword.lowercase())
    ↓
Store transaction in expense_tracker.db
    ↓
Check monthly/category budget
    ↓
Android notification
    ↓
Flutter reads the same SQLite DB
```

Example:

```text
INR 850 debited from A/C XX1234 via UPI to RAZORPAY*ZOMATO
```

Matches the keyword `zomato` and becomes `Expense → Food & Dining`.

## Important production work

The included parser is an MVP. Before a public launch, add real SMS fixtures/templates for every bank and payment provider you want to support and test false positives carefully.

Google Play treats SMS permissions as restricted. Budget/money-management apps can be eligible, but the Play Console permission declaration and review are still required. You also need a prominent disclosure/privacy policy explaining why SMS access is required and that unrelated SMS data is not uploaded.

The daily summary uses an inexact Android alarm, so Android may deliver it near the selected time rather than at the exact second, especially under battery/doze restrictions.
