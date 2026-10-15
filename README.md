# Expense Tracker v21 — Money Map + AI Financial Coach

v21 builds on the v20 cross-source deduplication release and keeps the product local-first and user-controlled.

## New in v21

### Money Map on Home
- Home now shows a compact **Money Map** for the currently selected dashboard period.
- Spending and investing are deliberately separated.
- Spending areas show totals and percentage share. When a stored category is Uncategorized, v21 uses conservative local merchant/message heuristics to infer areas such as Healthcare, Food & Dining, Groceries, Transport, Travel, Shopping, EMI & Loans, Bills & Utilities, Subscriptions, Education, Entertainment, Housing or Cash.
- Investment areas are inferred locally from recorded category / merchant / transaction text.
- Common investment areas include Mutual Funds, Defence, Banking & Financials, Healthcare, IT & Technology, Automobile, Energy, Metals, Gold and Deposits.
- Unclear investments remain **Other / unidentified** rather than being forced into a sector.
- Expense rows can open the exact filtered transactions for that period.
- **View report** opens a full Money Map page with Month / Week / Custom filters.
- The full report contains Spending areas, Investment areas and Investment types.

### AI Financial Coach
- New Home card for local financial behavior analysis.
- Forecasts likely month-end expense from the current daily spending pace.
- Compares the forecast with up to three recent completed months.
- Detects a conservative savings opportunity only in non-protected / discretionary categories.
- Fixed / essential areas such as EMI, loans, rent, insurance, healthcare, education and utilities are excluded from automatic cut suggestions.
- Shows merchant concentration when one merchant is a significant share of monthly expenses.
- Shows investment concentration as a descriptive fact, never a buy/sell recommendation.
- A detailed **See analysis** page explains the forecast, recent monthly average and savings estimate.
- All calculations run from structured local transactions. Raw SMS is not sent to a cloud AI service.

### Simpler information architecture
- The old standalone **What changed?** Home section is removed because the Financial Coach now owns behavioral comparisons and forecasting in one place.
- Financial Inbox remains focused only on uncertain transaction classification.
- Safe to Spend remains a separate actionable budget/cash-flow metric.
- Money Map handles allocation/concentration.
- AI Financial Coach handles behavior, forecast and saving opportunities.

## Retained from v20

- SMS + payment-app notification cross-source deduplication
- learned category/type preservation during duplicate merges
- existing-duplicate cleanup on startup
- user-controlled recurring payments
- "Only this" vs "All similar + future" correction learning
- Total / Month / Week / Day / Custom Home periods
- period-aware Recent Activity and View All
- clickable Reports
- screenshot blocking disabled during QA
- multi-app UPI chooser and QR compatibility improvements
- spam / stock-tip filtering
- credit-card bill payment handling
- pending SIP / failed reversal handling

## Build

Upload the **contents of this folder** to the GitHub repository root. The existing GitHub Actions workflow builds the Android APK.
