import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import requests

from database import find_ticket_matches, init_db, list_latest_draws, save_draw_result, save_winner
from parser import _parse_lottery_text
from result_fetcher import _find_latest_pdf_path, _get_with_retry, download_latest_result
from update_public_results import backfill_missing_draw_codes, merge_results


class HttpRetryTests(unittest.TestCase):
    @mock.patch("result_fetcher.time.sleep")
    @mock.patch("result_fetcher.requests.get")
    def test_retries_a_temporary_connection_failure(self, get, sleep):
        response = mock.Mock()
        get.side_effect = [requests.ConnectionError("connection refused"), response]

        result = _get_with_retry("https://example.com/", timeout=30, headers={})

        self.assertIs(result, response)
        self.assertEqual(get.call_count, 2)
        sleep.assert_called_once_with(1)

    @mock.patch("result_fetcher.time.sleep")
    @mock.patch("result_fetcher.requests.get", side_effect=requests.ConnectionError)
    def test_raises_after_retries_are_exhausted(self, get, sleep):
        with self.assertRaises(requests.ConnectionError):
            _get_with_retry("https://example.com/", timeout=30, headers={})

        self.assertEqual(get.call_count, 3)
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [1, 2])


class LatestPdfCommitTests(unittest.TestCase):
    def test_selects_the_pdf_published_by_the_latest_commit(self):
        self.assertEqual(
            _find_latest_pdf_path(
                [
                    {"filename": "README.md", "status": "modified"},
                    {
                        "filename": "lottery_results/KARUNYA PLUS.pdf",
                        "status": "added",
                    },
                ]
            ),
            "lottery_results/KARUNYA PLUS.pdf",
        )

    def test_rejects_a_commit_without_a_pdf(self):
        with self.assertRaisesRegex(ValueError, "does not publish a PDF"):
            _find_latest_pdf_path([{"filename": "README.md", "status": "modified"}])

    def test_rejects_commits_that_publish_multiple_pdfs(self):
        with self.assertRaisesRegex(ValueError, "changes multiple PDFs"):
            _find_latest_pdf_path(
                [
                    {"filename": "lottery_results/one.pdf", "status": "added"},
                    {"filename": "lottery_results/two.pdf", "status": "added"},
                ]
            )

    @mock.patch("result_fetcher.extract_lottery_results")
    @mock.patch("result_fetcher._get_with_retry")
    def test_downloads_and_parses_the_pdf_from_the_latest_commit(
        self, get, extract_results
    ):
        commits_response = mock.Mock()
        commits_response.json.return_value = [{"sha": "abc123"}]
        commit_response = mock.Mock()
        commit_response.json.return_value = {
            "files": [
                {
                    "filename": "lottery_results/KARUNYA PLUS.pdf",
                    "status": "added",
                }
            ]
        }
        pdf_response = mock.Mock()
        pdf_response.content = b"%PDF-1.7 test"
        get.side_effect = [commits_response, commit_response, pdf_response]
        extract_results.return_value = {
            "lottery_name": "KARUNYA PLUS",
            "draw_code": "KN-644",
            "draw_date": "2026-10-08",
            "winners": [],
        }

        result = download_latest_result()

        pdf_url = (
            "https://raw.githubusercontent.com/jithin-4T2/pdf-downloader/"
            "abc123/lottery_results/KARUNYA%20PLUS.pdf"
        )
        self.assertEqual(result["pdf_url"], pdf_url)
        self.assertEqual(
            result["source_url"],
            "https://github.com/jithin-4T2/pdf-downloader/blob/"
            "abc123/lottery_results/KARUNYA%20PLUS.pdf",
        )
        self.assertEqual(result["draw_code"], "KN-644")
        extract_results.assert_called_once_with(pdf_response.content)


class LotteryTextParserTests(unittest.TestCase):
    def test_parses_draw_header_prizes_and_ending_numbers(self):
        text = (
            "KERALA STATE LOTTERIES - RESULT EMAIL:- cru.dir.lotteries@kerala.gov.in "
            "BHAGYATHARA LOTTERY NO.BT-73rd DRAW held on:- 28/09/2026,3:00 PM "
            "1st Prize Rs :10000000/- 1) BB 814615 (KOLLAM) "
            "Cons Prize-Rs :5000/- BA 814615 BC 814615 "
            "2nd Prize Rs :3000000/- 1) BG 977056 (KAYAMKULAM) "
            "3rd Prize Rs :500000/- 1) BC 914492 (KASARAGOD) "
            "FOR THE TICKETS ENDING WITH THE FOLLOWING NUMBERS "
            "4th Prize-Rs :5000/- 0026 0817 0855 "
            "Page 1Modernization & IT Software Division : Department of State Lotteries01/10/2026 16:38:01 "
            "5th Prize-Rs :2000/- 1460 3507 "
            "Next BHAGYATHARA Draw will be held on 05/10/2026 at Thiruvananthapuram"
        )

        result = _parse_lottery_text(text)

        self.assertEqual(result["lottery_name"], "BHAGYATHARA")
        self.assertEqual(result["draw_code"], "BT-73")
        self.assertEqual(result["draw_date"], "2026-09-28")
        self.assertEqual(
            result["winners"][0],
            {"prize_tier": "1st", "prize_amount": 10000000, "numbers": ["BB 814615"]},
        )
        self.assertEqual(
            result["winners"][1],
            {
                "prize_tier": "Consolation",
                "prize_amount": 5000,
                "numbers": ["BA 814615", "BC 814615"],
            },
        )
        self.assertEqual(result["winners"][0]["prize_amount"], 10000000)
        self.assertEqual(result["winners"][4]["prize_tier"], "4th")
        self.assertEqual(result["winners"][4]["prize_amount"], 5000)
        self.assertEqual(result["winners"][4]["numbers"], ["0026", "0817", "0855"])
        self.assertEqual(
            result["winners"][5],
            {"prize_tier": "5th", "prize_amount": 2000, "numbers": ["1460", "3507"]},
        )


class PublicResultsTests(unittest.TestCase):
    def test_backfills_missing_draw_codes_without_replacing_existing_codes(self):
        draws = [
            {"draw_date": "2026-10-01", "pdf_path": "https://example.com/old.pdf"},
            {"draw_date": "2026-10-02", "draw_code": "DL-71", "pdf_path": "https://example.com/new.pdf"},
        ]
        lookup = mock.Mock(return_value="KN-643")

        backfill_missing_draw_codes(draws, lookup)

        self.assertEqual(draws[0]["draw_code"], "KN-643")
        self.assertEqual(draws[1]["draw_code"], "DL-71")
        lookup.assert_called_once_with("https://example.com/old.pdf")

    def test_merge_replaces_same_draw_and_normalizes_winning_numbers(self):
        existing = [
            {
                "id": 1,
                "lottery_name": "KARUNYA PLUS",
                "draw_date": "2026-10-01",
                "winners": [],
            }
        ]
        latest = {
            "lottery_name": "KARUNYA PLUS",
            "draw_code": "KN-643",
            "draw_date": "2026-10-01",
            "source_url": "https://example.com/",
            "pdf_url": "https://example.com/result.pdf",
            "winners": [{"prize_tier": "1st", "prize_amount": 10000000, "numbers": ["PH 901174"]}],
        }

        draws = merge_results(existing, latest)

        self.assertEqual(len(draws), 1)
        self.assertEqual(draws[0]["id"], 1)
        self.assertEqual(
            draws[0]["winners"],
            [{"prize_tier": "1st", "prize_amount": 10000000, "winning_number": "PH901174"}],
        )
        self.assertEqual(draws[0]["draw_code"], "KN-643")

    def test_existing_database_stores_prize_amounts_and_matches_ticket_suffix(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            database_path = Path(temp_dir) / "results.db"
            connection = sqlite3.connect(database_path)
            try:
                connection.executescript(
                    """
                    CREATE TABLE draws (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        lottery_name TEXT NOT NULL,
                        draw_date TEXT NOT NULL,
                        source_url TEXT,
                        pdf_path TEXT,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );
                    CREATE TABLE prize_winners (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        draw_id INTEGER NOT NULL,
                        prize_tier TEXT NOT NULL,
                        winning_number TEXT NOT NULL,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );
                    """
                )
            finally:
                connection.close()

            with mock.patch("database.DB_PATH", database_path):
                init_db()
                draw_id = save_draw_result("KARUNYA PLUS", "2026-10-01")
                save_winner(draw_id, "1st", "PH 901174", 10000000)
                older_draw_id = save_draw_result("KARUNYA PLUS", "2026-09-24")
                save_winner(older_draw_id, "2nd", "PH 901174", 3000000)

                draws = list_latest_draws(limit=1)
                matches = find_ticket_matches("901174", "2026-10-01")
                other_date_matches = find_ticket_matches("901174", "2026-09-24")

            self.assertEqual(draws[0]["winners"][0]["prize_amount"], 10000000)
            self.assertEqual(len(matches), 1)
            self.assertEqual(matches[0]["winning_number"], "PH901174")
            self.assertEqual(matches[0]["prize_amount"], 10000000)
            self.assertEqual(other_date_matches[0]["prize_tier"], "2nd")


if __name__ == "__main__":
    unittest.main()
