import sqlite3
from contextlib import contextmanager
from collections.abc import Iterator
from pathlib import Path

DB_PATH = Path(__file__).with_name("lottery_results.db")


@contextmanager
def get_connection() -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_db() -> None:
    with get_connection() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS draws (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                lottery_name TEXT NOT NULL,
                draw_code TEXT,
                draw_date TEXT NOT NULL,
                source_url TEXT,
                pdf_path TEXT,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        draw_columns = {row["name"] for row in conn.execute("PRAGMA table_info(draws)")}
        if "draw_code" not in draw_columns:
            conn.execute("ALTER TABLE draws ADD COLUMN draw_code TEXT")
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS prize_winners (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                draw_id INTEGER NOT NULL,
                prize_tier TEXT NOT NULL,
                winning_number TEXT NOT NULL,
                prize_amount INTEGER,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (draw_id) REFERENCES draws(id)
            )
            """
        )
        winner_columns = {row["name"] for row in conn.execute("PRAGMA table_info(prize_winners)")}
        if "prize_amount" not in winner_columns:
            conn.execute("ALTER TABLE prize_winners ADD COLUMN prize_amount INTEGER")
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_prize_winners_number ON prize_winners(winning_number)"
        )


def normalize_number(value: str) -> str:
    return "".join(ch for ch in (value or "").upper() if ch.isalnum())


def save_draw_result(
    lottery_name: str,
    draw_date: str,
    source_url: str | None = None,
    pdf_path: str | None = None,
    draw_code: str | None = None,
) -> int:
    with get_connection() as conn:
        cursor = conn.execute(
            """
            INSERT INTO draws (lottery_name, draw_code, draw_date, source_url, pdf_path)
            VALUES (?, ?, ?, ?, ?)
            """,
            (lottery_name, draw_code, draw_date, source_url, pdf_path),
        )
        return int(cursor.lastrowid)


def save_winner(
    draw_id: int,
    prize_tier: str,
    winning_number: str,
    prize_amount: int | None = None,
) -> None:
    with get_connection() as conn:
        conn.execute(
            """
            INSERT INTO prize_winners (draw_id, prize_tier, winning_number, prize_amount)
            VALUES (?, ?, ?, ?)
            """,
            (draw_id, prize_tier, normalize_number(winning_number), prize_amount),
        )


def list_latest_draws(limit: int = 10) -> list[dict]:
    with get_connection() as conn:
        rows = conn.execute(
            """
                SELECT id, lottery_name, draw_code, draw_date, source_url, pdf_path
            FROM draws
            ORDER BY draw_date DESC, id DESC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()
        results = []
        for row in rows:
            winners = conn.execute(
                """
                SELECT prize_tier, winning_number, prize_amount
                FROM prize_winners
                WHERE draw_id = ?
                ORDER BY id ASC
                """,
                (row["id"],),
            ).fetchall()
            results.append(
                {
                    "id": row["id"],
                    "lottery_name": row["lottery_name"],
                    "draw_code": row["draw_code"],
                    "draw_date": row["draw_date"],
                    "source_url": row["source_url"],
                    "pdf_path": row["pdf_path"],
                    "winners": [
                        {
                            "prize_tier": item["prize_tier"],
                            "winning_number": item["winning_number"],
                            "prize_amount": item["prize_amount"],
                        }
                        for item in winners
                    ],
                }
            )
        return results


def find_ticket_matches(ticket_code: str, draw_date: str | None = None) -> list[dict]:
    normalized = normalize_number(ticket_code)
    if len(normalized) < 4:
        return []

    with get_connection() as conn:
        rows = conn.execute(
            """
                 SELECT d.id, d.lottery_name, d.draw_date, pw.prize_tier,
                     pw.winning_number, pw.prize_amount
            FROM prize_winners pw
            JOIN draws d ON d.id = pw.draw_id
                        WHERE (? IS NULL OR d.draw_date = ?)
                            AND (
                                     pw.winning_number = ?
                                     OR (length(pw.winning_number) = 8 AND pw.winning_number LIKE ?)
                                     OR (length(pw.winning_number) = 4 AND pw.winning_number = substr(?, -4))
                            )
            ORDER BY d.draw_date DESC, d.id DESC
            """,
            (draw_date, draw_date, normalized, f"%{normalized}", normalized),
        ).fetchall()
        return [
            {
                "draw_id": row["id"],
                "lottery_name": row["lottery_name"],
                "draw_date": row["draw_date"],
                "prize_tier": row["prize_tier"],
                "winning_number": row["winning_number"],
                "prize_amount": row["prize_amount"],
            }
            for row in rows
        ]
