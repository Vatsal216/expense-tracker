#!/usr/bin/env python3
"""Additional conservative safety and startup improvements for expense-tracker."""
from pathlib import Path
import sys
ROOT=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()

def patch(path, old, new):
    s=path.read_text(encoding='utf8')
    if new in s:
        print('Already patched',path.name)
        return
    count=s.count(old)
    if count!=1: raise RuntimeError(f'{path}: expected one anchor, got {count}: {old[:90]}')
    path.write_text(s.replace(old,new),encoding='utf8')
    print('Patched',path)

app=ROOT/'lib/app_db.dart'
# Transfers must not be inferred solely from matching amounts and clock proximity.
patch(app, "        if(a['account_hint']==b['account_hint']) continue;\n        final gid=", """        if(a['account_hint']==b['account_hint']) continue;
        // Two unrelated payments can have the same amount on the same day.
        // Require a shared transaction reference or explicit self-transfer evidence.
        final refA = (a['upi_reference'] as String? ?? '').trim().toLowerCase();
        final refB = (b['upi_reference'] as String? ?? '').trim().toLowerCase();
        if (refA.isNotEmpty && refB.isNotEmpty && refA != refB) continue;
        final sameRef = refA.isNotEmpty && refA == refB;
        final messageA = '${a['raw_message'] ?? ''}'.toLowerCase();
        final messageB = '${b['raw_message'] ?? ''}'.toLowerCase();
        final explicitSelf = [messageA, messageB].any((message) =>
          message.contains('self transfer') ||
          message.contains('own account') ||
          message.contains('between your accounts') ||
          message.contains('internal transfer'));
        if (!sameRef && !explicitSelf) continue;
        if (diff > (sameRef ? 30 : 5) * 60 * 1000) continue;
        final gid=""")
# Avoid matching unrelated payments having different transaction references.
patch(app, "      if (refA.isNotEmpty && refB.isNotEmpty && refA.toLowerCase() == refB.toLowerCase()) return diff <= 10 * 60 * 1000;", """      if (refA.isNotEmpty && refB.isNotEmpty) {
        if (refA.toLowerCase() != refB.toLowerCase()) return false;
        return diff <= 10 * 60 * 1000;
      }""")
# Future dedup supports all notification sources but never affects manual entries.
patch(app, "review_status='accepted' AND source IN ('sms','phonepe_notification')", "review_status='accepted' AND (source='sms' OR source LIKE '%_notification')")

main=ROOT/'lib/main.dart'
# Isolate failure of independent startup services: one failed task shouldn't skip everything.
patch(main, """    await NativeBridge.scheduleDailySummary(enabled: enabled, hour: hour, minute: minute);
    await loadEnhancedPreferences();
    await AppDb.instance.normalizeExistingMerchants();
    await AppDb.instance.syncAccountsFromTransactions();
    await AppDb.instance.matchTransfers();
    final dedupResult = await AppDb.instance.smartDeduplicate();
    if ((dedupResult['ignored'] ?? 0) > 0) expenseDataRevision.value++;
    await runDailySmartAlerts();
    try { await NativeBridge.updateHomeWidget(); } catch (_) {}""", """    Future<void> safeTask(String label, Future<void> Function() task) async {
      try {
        await task();
      } catch (e) {
        debugPrint('Startup task $label failed: $e');
      }
    }
    await safeTask('daily summary', () => NativeBridge.scheduleDailySummary(enabled: enabled, hour: hour, minute: minute));
    await safeTask('preferences', () => loadEnhancedPreferences());
    await safeTask('merchant normalization', () => AppDb.instance.normalizeExistingMerchants());
    await safeTask('account sync', () => AppDb.instance.syncAccountsFromTransactions());
    await safeTask('transfer matching', () async { await AppDb.instance.matchTransfers(); });
    await safeTask('deduplication', () async {
      final dedupResult = await AppDb.instance.smartDeduplicate();
      if ((dedupResult['ignored'] ?? 0) > 0) expenseDataRevision.value++;
    });
    await safeTask('smart alerts', () => runDailySmartAlerts());
    await safeTask('home widget', () => NativeBridge.updateHomeWidget());""")
# Stop presenting rule-based analytics as a trained generative AI assistant.
patch(main, "title: 'AI Financial Coach',", "title: 'Spending Insights',")
patch(main, "subtitle: 'Local pattern analysis, forecasts and saving opportunities',", "subtitle: 'On-device spending patterns and estimates',")
print('Additional fixes applied; compile and test on Android before release.')
