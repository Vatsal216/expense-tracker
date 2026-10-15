# v17 acceptance checks

1. Home shows Safe to Spend without overflow on narrow screens.
2. Safe to Spend reserves recurring **expense** bills due before month end; SIP/investment recurrence is not counted as a bill twice.
3. Month-to-date comparisons use the same elapsed-day window from the previous month.
4. Low-confidence detections appear in Financial Inbox; Ignore / Fix / Accept all work.
5. More tools does not duplicate Needs Review or Smart Insights.
6. Transaction details explain classifier method and confidence and direct users to Edit when wrong.
7. Screenshots remain enabled during QA (`secure_screen_enabled=0` and native secure flag cleared).
8. Existing v14 classifier regression cases continue to pass after build.
