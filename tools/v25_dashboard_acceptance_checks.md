# v25 Dashboard acceptance checks

1. Fresh install/no saved Home filter opens Home on **Week**.
2. Select Month, refresh the app/Home, and confirm Month remains selected.
3. Close/reopen app and confirm the last selected Home filter is restored.
4. Select Custom, choose a date range, close/reopen, and confirm Custom range is restored.
5. Home no longer contains Financial Assistant/Money Planner preview.
6. Home no longer contains Recurring Payments preview.
7. Home no longer shows monthly Safe-to-Spend while Week/Day filters are active.
8. Bottom navigation contains Home, Activity, Pay, Plan, Reports, Settings; only selected label is shown to avoid crowding.
9. Plan > Money planner opens local transaction-grounded planning/questions.
10. Plan > Recurring opens the user-controlled recurring rules list.
11. Recurring > Add recurring still allows choosing an existing expense/investment and frequency.
12. Home Week totals, Money Map and Recent Activity cover Monday through today.
13. v24 promotional SMS regression remains: `SPECIAL DEAL ... Rs.3000 OFF ... Use Code ... Book now` must be ignored, not stored as a transaction.
14. v23 UPI regression remains: signed merchant QR payloads are forwarded unchanged and installed UPI apps are discovered dynamically.
