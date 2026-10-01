from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Callable

import requests

from result_fetcher import download_draw_code, download_latest_result

RESULTS_PATH = Path(__file__).resolve().parents[1] / "frontend" / "web" / "results.json"


def backfill_missing_draw_codes(
    draws: list[dict[str, Any]],
    lookup: Callable[[str], str | None] = download_draw_code,
) -> list[dict[str, Any]]:
    for draw in draws:
        pdf_url = draw.get("pdf_path")
        if draw.get("draw_code") or not pdf_url:
            continue
        try:
            draw_code = lookup(str(pdf_url))
        except (requests.RequestException, ValueError):
            continue
        if draw_code:
            draw["draw_code"] = draw_code
    return draws


def merge_results(
    existing_draws: list[dict[str, Any]],
    latest_result: dict[str, Any],
    limit: int = 20,
) -> list[dict[str, Any]]:
    draw_date = str(latest_result["draw_date"])
    lottery_name = str(latest_result["lottery_name"])
    existing_draw = next(
        (
            draw
            for draw in existing_draws
            if draw.get("draw_date") == draw_date
            and str(draw.get("lottery_name", "")).upper() == lottery_name.upper()
        ),
        None,
    )
    next_id = max((int(draw.get("id", 0)) for draw in existing_draws), default=0) + 1

    winners = [
        {
            "prize_tier": str(prize.get("prize_tier", "Unknown")),
            "prize_amount": prize.get("prize_amount"),
            "winning_number": "".join(
                character
                for character in str(number).upper()
                if character.isalnum()
            ),
        }
        for prize in latest_result.get("winners", [])
        for number in prize.get("numbers", [])
        if number
    ]
    current_draw = {
        "id": int(existing_draw["id"]) if existing_draw else next_id,
        "lottery_name": lottery_name,
        "draw_code": latest_result.get("draw_code") or (existing_draw or {}).get("draw_code"),
        "draw_date": draw_date,
        "source_url": latest_result.get("source_url"),
        "pdf_path": latest_result.get("pdf_url"),
        "winners": winners,
    }

    draws = [
        draw
        for draw in existing_draws
        if not (
            draw.get("draw_date") == draw_date
            and str(draw.get("lottery_name", "")).upper() == lottery_name.upper()
        )
    ]
    draws.append(current_draw)
    return sorted(
        draws,
        key=lambda draw: (str(draw.get("draw_date", "")), int(draw.get("id", 0))),
        reverse=True,
    )[:limit]


def update_public_results() -> dict[str, Any]:
    latest_result = download_latest_result()
    if RESULTS_PATH.exists():
        existing_draws = json.loads(RESULTS_PATH.read_text(encoding="utf-8"))
        if not isinstance(existing_draws, list):
            raise ValueError("Published results must be a JSON array.")
    else:
        existing_draws = []

    draws = merge_results(existing_draws, latest_result)
    backfill_missing_draw_codes(draws)
    RESULTS_PATH.parent.mkdir(parents=True, exist_ok=True)
    RESULTS_PATH.write_text(
        json.dumps(draws, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    return draws[0]


if __name__ == "__main__":
    print(json.dumps(update_public_results(), ensure_ascii=True))