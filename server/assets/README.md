# Branding assets

Files here are bundled into the API image and used when generating documents.

## Coat of arms on the requisition form

Place the official coat of arms here as:

    server/assets/coat-of-arms.png

It is rendered centred at the top of the generated **REQUISITION FORM**
(above the government and ministry names). PNG, roughly square, ~256×256 px or
larger works best.

Two ways to supply it:

1. **This file** — drop `coat-of-arms.png` in and rebuild the API image.
2. **No rebuild** — set the `org_logo` setting to a base64-encoded PNG (no
   `data:` prefix). The setting takes precedence over this file. For example,
   in the Supabase SQL editor:

   ```sql
   UPDATE settings SET value = '<base64-png>' WHERE key = 'org_logo';
   ```

If neither is provided, the form still prints with the text header
(government + ministry name) and no image.
