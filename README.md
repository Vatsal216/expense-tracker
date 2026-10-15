# Expense Tracker v25 — Cleaner Home + Planning Tabs

v25 simplifies the main dashboard and makes the selected Home period persistent. It keeps the v24 classifier safety fixes and v23 UPI interoperability work.

## Dashboard changes

- Home defaults to **Week** for new installs/users with no saved preference.
- Week / Month / Day / Total / Custom selection is saved locally and restored after refresh or app restart.
- The Home state is preserved during in-app refreshes, so the selected filter does not jump back.
- The filter now drives the main spending totals, Money Map preview and Recent Activity.
- The old Financial Assistant preview and Recurring Payments preview were removed from Home to reduce clutter.
- The monthly Safe-to-Spend card was also removed from Home because it conflicted with a week/day dashboard filter.

## New Plan tab

A single **Plan** item was added to bottom navigation. Inside it are two separate tabs:

- **Money planner** — local transaction-grounded planning/questions and savings goal calculations. It is explicitly described as local financial analysis rather than a general AI chatbot.
- **Recurring** — the full user-controlled recurring payment manager with add/remove and transaction drill-down.

Using one Plan destination avoids adding separate Assistant and Recurring icons to an already crowded bottom navigation bar.

---

# Expense Tracker v22 — Financial Assistant + Message-Pattern Learning

v22 replaces the old static “AI Financial Coach” cards with a user-facing Financial Assistant and fixes the overly broad correction-learning behavior found in bank SMS.

## Financial Assistant

The old coach screen has been removed. It no longer repeats ordinary report metrics such as merchant concentration as “AI”.

The new **Financial Assistant** supports useful questions such as:

- Where can I save ₹5,000?
- Why did I spend more this month?
- Compare this month with last month.
- What recurring payments are coming?
- Where am I investing most?
- Forecast this month.
- How much did I spend in Food / Groceries / Shopping / Healthcare / Travel?

Answers are calculated locally from cleaned structured transactions and provide:

- an explanation of why the result matters;
- category-by-category saving actions;
- equal-day month-to-month comparisons;
- a month-end forecast range rather than one overconfident number;
- only user-confirmed recurring commitments;
- transaction drill-down when an answer can be inspected;
- investment allocation descriptions without buy/sell advice.

### Savings goal planner

The user can set a target amount and deadline. The assistant calculates:

- required monthly saving;
- recent recorded monthly saving capacity;
- the remaining monthly gap;
- conservative discretionary changes that could help close the gap.

The goal is persisted locally in Settings storage.

### Home preview

Home now shows a compact **Financial Assistant** preview instead of generic AI insight cards. It prioritizes an actionable saving opportunity or confirmed upcoming commitments, with forecast range as context.

## Critical classification-learning fix

v21 and earlier could learn a user correction at the wrong level. If an ICICI transaction was changed to Gold and “All similar + future” was selected, a broad bank/merchant rule could cause unrelated ICICI messages (Google AutoPay, subscriptions, mutual funds, etc.) to become Gold.

v22 changes the learning model:

- bank/sender names are treated as transport context, not transaction identity;
- “same” means the **same stable message pattern**, not simply the same bank;
- variable data such as amount, date, account digits and reference number are not used as identity;
- stable payee/purpose + context are used, e.g. `ZARIVAULT + Subscription + AutoPay`;
- user rules can use conjunction matching such as `zarivault&&subscription&&autopay`;
- every part must match before the rule is applied;
- unsafe old broad bank-name user rules are removed on upgrade;
- a one-time v22 reclassification pass rechecks affected stored SMS while preserving transactions manually corrected one-by-one.

The correction dialog now says **Same pattern + future** to make the behavior explicit.

## Money Map remains separate

Money Map continues to answer **where money went**. The Financial Assistant answers **what it means and what the user can do**. This avoids duplicate screens.

## Retained

- v20 SMS + notification deduplication
- learned category preservation during duplicate merges
- user-controlled recurring payments
- Home Total / Month / Week / Day / Custom periods
- period-aware Recent Activity and View All
- clickable Reports
- screenshot blocking disabled during QA
- UPI QR payload preservation and multi-app chooser
- spam / stock-tip filtering
- credit-card bill payment handling
- pending SIP / failed reversal handling

## Privacy

Financial Assistant analysis runs locally from structured transactions. Raw SMS text is not sent to a cloud model or server.

## Build

Upload the **contents of this folder** to the GitHub repository root. The existing GitHub Actions workflow builds the Android APK.

## v23 - UPI interoperability fix

- Dynamically detects every Android app currently ready to handle `upi://pay`.
- Direct launch support for Paytm, Google Pay, PhonePe, BHIM, plus any discovered UPI app.
- Keeps an NPCI-style **Pay by any UPI app** generic chooser.
- Adds Android 11+ package visibility for major UPI apps and the `upi://pay` intent.
- Signed merchant QR payloads are forwarded byte-for-byte; they are never rebuilt/re-encoded.
- Unsigned QR payloads preserve merchant/reference parameters and only fill missing amount/currency/note.
- Supports `mam` minimum amount semantics and avoids locking amount when `mam` is present.
- More robust UPI result parsing for success / pending / failed / cancelled states.
- Signed static QR payments without an amount rely on SMS/notification capture to avoid saving an incorrect duplicate.


## v24 classifier safety upgrade

- Promotional amounts (for example `Rs 3000 OFF`) are no longer treated as transaction amounts.
- Added completed-financial-movement evidence gate before ML/rules can create ledger entries.
- Expanded local ML training with discount, coupon, travel-deal, cashback-offer and investment-ad negatives.
- Existing non-user-corrected SMS are reclassified once on upgrade so old promotional false positives are hidden.
- User-confirmed corrections remain protected.
