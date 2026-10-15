# v24 classifier acceptance checks

The classifier must never treat a displayed discount/promotion value as money movement.

## Must ignore

- `SPECIAL DEAL on domestic flights: Up to Rs.3000 OFF*, Use Code: RWYVSP. Book now - Team MakeMyTrip`
- `Pay via UPI today and get Rs 300 cashback. Offer valid for selected users.`
- `Start SIP with just Rs 500 per month. Invest now in our top mutual funds.`
- `Flat INR 2500 discount on hotels. Apply coupon HOTEL2500.`
- `Reward points worth Rs 3000 available. Redeem now.`

## Must remain financial

- `Rs 3000 debited from ICICI Bank Savings Account XX373 towards MAKE MY TRIP` -> Expense
- `Rs 3000 debited from ICICI Bank Account XX373 for SIP purchase in HDFC Mutual Fund. Units allotted successfully.` -> Investment / Mutual Funds
- `INR 2500 credited to your account from ABC` -> Income
- `Refund of Rs 900 credited back to your account` -> Refund
- `Rs 1000 will be debited tomorrow for autopay` -> Pending / not ledger

## Upgrade behavior

On first v24 startup, stored SMS transactions not manually/user-corrected are reclassified once. Promotional false positives are marked ignored. User-corrected records are not overwritten.
