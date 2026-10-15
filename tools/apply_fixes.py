#!/usr/bin/env python3
"""Apply conservative transaction ingestion fixes to the expense-tracker source checkout."""
from pathlib import Path
import sys
ROOT = Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
BASE=ROOT/'android/app/src/main/kotlin/com/example/expense_tracker'

def patch(path, old, new):
    s=path.read_text(encoding='utf-8')
    if new in s: print('Already patched:',path.name); return
    if s.count(old)!=1: raise RuntimeError(f'Expected exactly one match in {path}: {old[:80]!r}, got {s.count(old)}')
    path.write_text(s.replace(old,new),encoding='utf-8');print('Patched:',path.name)

p=BASE/'HybridMessageClassifier.kt'
patch(p,'        hardGate(lower)?.let { return it }\n',r'''        hardGate(lower)?.let { return it }

        // A neural prediction or merchant rule alone is never evidence of a transaction.
        // Conservative guard: uncertain alerts remain outside recorded expenses.
        val currencyAmount = Regex("""(?:₹|\brs\.?|\binr\b)\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?""")
            .containsMatchIn(lower)
        val completedMoneyMovement = Regex(
            """\b(debited|deducted|credited|withdrawn|paid|spent|received|sent|refunded|transferred|purchased|invested)\b|payment successful|transaction successful|payment completed|order executed|units allotted"""
        ).containsMatchIn(lower)
        if (!currencyAmount || !completedMoneyMovement) {
            return decision("ignore", 1.0, "hard_gate", "ignore", 1.0,
                "no confirmed currency transaction")
        }
''')

p=BASE/'PhonePeNotificationListener.kt'
patch(p,'        if (item.packageName != "com.phonepe.app") return', '''        // Only allow-listed finance app notifications; never read arbitrary apps.
        val appName = when (item.packageName) {
            "com.phonepe.app" -> "PhonePe"
            "net.one97.paytm" -> "Paytm"
            "com.google.android.apps.nbu.paisa.user" -> "Google Pay"
            else -> return
        }''')
patch(p,'        val parsed = TransactionParser.parsePhonePeNotification(db, title, body, item.postTime) ?: return', '''        // Use the same explicit transaction evidence guard for all supported UPI apps.
        val parsed = TransactionParser.parsePhonePeNotification(db, title, body, item.postTime, appName) ?: return''')

p=BASE/'TransactionParser.kt'
patch(p,'fun parsePhonePeNotification(db: ExpenseDatabase, title: String, body: String, occurredAt: Long): ParsedTransaction?', 'fun parsePhonePeNotification(db: ExpenseDatabase, title: String, body: String, occurredAt: Long, appName: String = "PhonePe"): ParsedTransaction?')
patch(p,'fingerprint("phonepe|$amount|${decision.label}|$merchant|${occurredAt / 60000}|$upiReference|$text")','fingerprint("notification|$appName|$amount|${decision.label}|$merchant|${occurredAt / 60000}|$upiReference|$text")')
patch(p,'            sender = "PhonePe",\n            paymentMethod = "UPI / PhonePe",','            sender = appName,\n            paymentMethod = "UPI / $appName",')


# Dashboard: weekly view by default, with existing date chips unchanged.
main = ROOT / 'lib/main.dart'
patch(main, "class _HomePageState extends State<HomePage> {\n  String period = 'month';",
            "class _HomePageState extends State<HomePage> {\n  String period = 'week';")

# Recurring payments get their own bottom-navigation destination instead of a
# preview taking space on the Home dashboard.
patch(main,
      "      SettingsPage(key: ValueKey('settings-$refreshToken'), onChanged: refresh),",
      "      SettingsPage(key: ValueKey('settings-$refreshToken'), onChanged: refresh),\n"
      "      const RecurringPaymentsPage(),")
patch(main,
      "              NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Settings'),",
      "              NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Settings'),\n"
      "              NavigationDestination(icon: Icon(Icons.repeat_rounded), label: 'Recurring'),")
# Remove the home-only recurring preview while preserving the managing page.
patch(main,
      "              const SizedBox(height: 12),\n              const _HomeRecurringPreview(),",
      "              const SizedBox(height: 12),\n              // Recurring payments have a dedicated navigation destination.")

print('Dashboard default and recurring navigation prepared.')

print('Patch applied. Run Flutter analysis and build; then validate on an Android device.')
