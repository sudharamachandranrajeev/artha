# Your first five minutes with Artha

Artha keeps accounts, spending and investments together. You can start on one device without
creating an online account. Financial data is encrypted on that device.

## 1. Install and open Artha

On Linux, follow the [Linux installation guide](https://github.com/sudharamachandranrajeev/artha/blob/main/docs/install-linux.md).
On Windows, run the release's `setup.exe`. On Android, install the release's `.apk`.
Downloads are on the [releases page](https://github.com/sudharamachandranrajeev/artha/releases);
sign in to GitHub with an account that has repository access.

## 2. Choose your base currency

At **Welcome to Artha**, choose the currency you want for totals, then select **Get started**.
This is usually the currency you are paid in. Each account can still use its own currency.

Already using Artha on another device? Choose **Join from another device** instead, or
**Sign in with e-mail instead** if you have a sync account.

## 3. Add an account

Open **Accounts**, choose **Add account** (or the **+ Account** button), and enter its name,
type and currency. Start with one current account so you can check the results easily.

## 4. Add your first transactions

Open **Transactions** and choose **+ Transaction** to enter an income, expense or transfer.
For a bank statement, use **Import statement**, select the destination account and choose
your CSV, OFX, QFX or QIF file. Review the proposed entries and any duplicate or transfer
matches before importing. For CSV files, check the date and amount columns carefully.

Open the account and use **Record statement balance** to compare your records with your
bank's closing balance on the same date. This is a check, not a replacement for missing entries.

## 5. See the picture

The dashboard shows your net worth, income and spending. **Reports** provides accounting
summaries; **Portfolio** covers investments. Under **Settings → Appearance**, choose your
palette and light, dark or system mode. The hints beside controls explain what each one does.

## Optional: use more than one device

Sync needs a running Artha server. Ask its operator for the HTTPS server address and invite
code, or follow the [server setup guide](https://github.com/sudharamachandranrajeev/artha/blob/main/server/README.md).

On your first device, open **Settings → Sync → Create account**. Save the recovery key
somewhere separate and safe before finishing. On another device, sign in, or use **Add a
device** on the first device and **Join from another device** on the new one. Compare the
displayed verification codes before approving the pairing.

Sync is optional. Server backups are still needed: sync alone is not a backup against every
mistake. Losing both your password and recovery key can make synced data unrecoverable.
