# Daily Lottery Results

The scheduled workflow downloads the latest official PDF at 3:05 PM India time, parses its winning numbers, and updates `frontend/web/results.json`. GitHub Actions commits changes to the repository. Re-running the workflow for the same draw updates that entry instead of duplicating it.

## GitHub setup

1. Create a GitHub repository. Make it public if the app should read its results without authentication. Lottery results are public, but the source code will also be public.
2. Before pushing, check that `backend/.env`, the Python virtual environment, and the local SQLite database are ignored by `.gitignore`.
3. Push this folder to the repository's default branch and enable GitHub Actions. The workflow is in `.github/workflows/daily-lottery-results.yml`.
4. Open **Actions**, select **Update lottery results**, then choose **Run workflow** once to publish the initial JSON. Daily runs then happen at 3:05 PM India time. GitHub may delay scheduled runs during high load.
5. Configure the Flutter app with the repository's public raw JSON URL:

   ```text
   https://raw.githubusercontent.com/OWNER/REPOSITORY/main/frontend/web/results.json
   ```

   Run Flutter with:

   ```text
   --dart-define=RESULTS_JSON_URL=https://raw.githubusercontent.com/OWNER/REPOSITORY/main/frontend/web/results.json
   ```

When `RESULTS_JSON_URL` is set, the app reads draws and checks tickets from the published JSON. PDF upload and parsing still use the FastAPI backend. Without `RESULTS_JSON_URL`, the existing local API behavior remains unchanged.

This workspace is not currently a Git repository, so the workflow cannot run until the files are pushed to GitHub. GitHub Actions free usage is sufficient for one short daily run; private repositories have a monthly minutes allowance, while standard runner usage for public repositories is free.