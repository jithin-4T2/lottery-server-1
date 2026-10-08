# Daily Lottery Results

After the latest PDF is manually uploaded to `jithin-4T2/pdf-downloader/lottery_results`, the scheduled workflow checks the latest PDF publication commit at 4:50 PM India time, parses its winning numbers, and updates `frontend/web/results.json`. Disable the downloader repository's scheduled CAPTCHA automation; this workflow only reads a manually published PDF. GitHub Actions commits changes to this repository. Re-running the workflow for the same draw updates that entry instead of duplicating it. Publish one PDF per commit so the importer can unambiguously identify the new result.

## GitHub setup

1. Create a GitHub repository. Make it public if the app should read its results without authentication. Lottery results are public, but the source code will also be public.
2. Before pushing, check that `backend/.env`, the Python virtual environment, and the local SQLite database are ignored by `.gitignore`.
3. Push this folder to the repository's default branch and enable GitHub Actions. The workflow is in `.github/workflows/daily-lottery-results.yml`.
4. Open **Actions**, select **Update lottery results**, then choose **Run workflow** once to publish the initial JSON. Daily runs then happen at 4:50 PM India time, after the expected 4:40 PM PDF upload. GitHub may delay scheduled runs during high load.
5. Configure the Flutter app with the repository's public raw JSON URL:

   ```text
   https://raw.githubusercontent.com/OWNER/REPOSITORY/main/frontend/web/results.json
   ```

   Run Flutter with:

   ```text
   --dart-define=RESULTS_JSON_URL=https://raw.githubusercontent.com/OWNER/REPOSITORY/main/frontend/web/results.json
   ```

When `RESULTS_JSON_URL` is set, the app reads draws and checks tickets from the published JSON. PDF upload and parsing still use the FastAPI backend. Without `RESULTS_JSON_URL`, the existing local API behavior remains unchanged.

The scheduled workflow runs after the expected 4:40 PM PDF upload. GitHub Actions can delay scheduled runs during high load, so use **Run workflow** manually if an upload is late. GitHub Actions free usage is sufficient for one short daily run; private repositories have a monthly minutes allowance, while standard runner usage for public repositories is free.