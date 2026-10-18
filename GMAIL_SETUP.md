# Gmail expense import setup

The app uses Google OAuth with the read-only Gmail scope. It never requests a
Gmail password and does not save raw email bodies in the transaction ledger.

## One-time Google Cloud setup

1. Create or select a project in Google Cloud Console.
2. Enable **Gmail API**.
3. Configure the OAuth consent screen. Add yourself as a test user while the
   app remains in testing.
4. Create an Android OAuth client for this app package and signing SHA-1.
5. If your Google configuration requires it, create a Web OAuth client and put
   its client ID in the `gmail_server_client_id` setting before connecting.

## In the app

Open **Settings → Email expense tracking → Connect Gmail**. Choose an account
and grant the displayed read-only permission. The app searches recent financial
receipts and sends candidates through the same hybrid classifier, user rules
and duplicate resolver used for SMS and supported payment-app notifications.
Each source is linked as evidence to one canonical ledger transaction; raw
email bodies are never stored.

## Sync behaviour

SMS and enabled payment-app notifications remain event-driven on-device. Gmail
refreshes when the app opens and whenever the user taps **Sync now**. True
Gmail push while the app is closed requires a separately deployed HTTPS backend
using Gmail Watch and Google Pub/Sub; it is intentionally not faked as an
on-device event.
