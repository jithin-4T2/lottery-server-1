import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from database import find_ticket_matches, init_db, list_latest_draws, save_draw_result, save_winner
from parser import _parse_lottery_text
from result_fetcher import _find_latest_result_url
from update_public_results import merge_results


class FindLatestResultUrlTests(unittest.TestCase):
    def test_selects_draw_page_instead_of_generic_pdf(self):
        html = """
        <html><body>
            <a href="http://example.org/draw.pdf">Generic PDF</a>
            <a href="viewlotisresult.php?drawserial=75393">Latest draw</a>
            <a href="viewlotisresult.php?drawserial=75392">Older draw</a>
        </body></html>
        """
        self.assertEqual(
            _find_latest_result_url(html, "https://result.keralalotteries.com/"),
            "https://result.keralalotteries.com/viewlotisresult.php?drawserial=75393",
        )

    def test_returns_none_when_no_draw_links_exist(self):
        self.assertIsNone(_find_latest_result_url("<a href='report.pdf'>PDF</a>", "https://example.com/"))


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

                draws = list_latest_draws(limit=1)
                matches = find_ticket_matches("901174")

            self.assertEqual(draws[0]["winners"][0]["prize_amount"], 10000000)
            self.assertEqual(matches[0]["winning_number"], "PH901174")
            self.assertEqual(matches[0]["prize_amount"], 10000000)


if __name__ == "__main__":
    unittest.main()
