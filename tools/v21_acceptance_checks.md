# v21 acceptance checks

1. Home shows Money Map and AI Financial Coach without overflow on a narrow Android screen.
2. Changing Home Total / Month / Week / Day / Custom refreshes Money Map totals for the same period.
3. Money Map -> View report opens Month / Week / Custom filters.
4. Tapping a Spending area opens only expense transactions in that category and date range.
5. Tapping an Investment type opens only investment transactions in that category and date range.
6. HDFC Defence Fund text is classified as Defence, not Banking merely because the funding account mentions a bank.
7. Generic SIP / Mutual Fund records remain Mutual Funds when no reliable sector is present.
8. AI Financial Coach shows projected month-end expense once current-month expense exists.
9. Savings suggestion does not recommend cutting EMI / loan / rent / insurance / healthcare / education / utilities.
10. Investment concentration text is descriptive and includes no buy/sell instruction.
11. Existing v20 SMS + notification dedup regression still passes.
12. No Smart Insights / Net Worth / Smart Automation duplicate UI is reintroduced.
