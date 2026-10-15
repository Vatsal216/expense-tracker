# UPI interoperability regression cases

1. Dynamic merchant QR: preserve pa, pn, tr, am, cu, mc and any extra query parameters.
2. Static QR without am: add the user-entered amount while preserving all original parameters.
3. QR with am: keep the QR amount read-only and unchanged.
4. Blank note: do not add tn=.
5. Manual UPI ID: create upi://pay with pa, pn, am, cu and optional tn.
6. Invalid scheme/host or missing pa: reject before opening another app.
7. If selected UPI app blocks external P2P for security reasons, offer Copy UPI ID fallback; never bypass its risk control.
