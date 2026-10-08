from __future__ import annotations

from typing import Any

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from database import find_ticket_matches, init_db, list_latest_draws, save_draw_result, save_winner
from parser import extract_lottery_results
from result_fetcher import download_latest_result


def _download_and_store_latest_result() -> dict[str, Any]:
    result = download_latest_result()
    draw_id = save_draw_result(
        lottery_name=result.get("lottery_name", "Unknown"),
        draw_date=result.get("draw_date", "unknown"),
        source_url=result.get("source_url"),
        pdf_path=result.get("pdf_url"),
        draw_code=result.get("draw_code"),
    )

    for prize in result.get("winners", []):
        tier = prize.get("prize_tier", "Unknown")
        for number in prize.get("numbers", []):
            if number:
                save_winner(draw_id, tier, str(number), prize.get("prize_amount"))

    return {
        "draw_id": draw_id,
        "lottery_name": result.get("lottery_name", "Unknown"),
        "draw_code": result.get("draw_code"),
        "draw_date": result.get("draw_date", "unknown"),
        "source_url": result.get("source_url"),
        "pdf_url": result.get("pdf_url"),
    }


app = FastAPI(title="Kerala Lottery API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

init_db()

scheduler = BackgroundScheduler(timezone="Asia/Kolkata")
scheduler.add_job(
    _download_and_store_latest_result,
    CronTrigger(hour=16, minute=50, second=0, timezone="Asia/Kolkata"),
    id="daily_lottery_fetch",
    replace_existing=True,
)
if not scheduler.running:
    scheduler.start()


@app.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/parse")
def parse_lottery_pdf(file: UploadFile = File(...)) -> dict:
    if not file.filename or not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Upload a PDF file.")

    pdf_bytes = file.file.read()
    if not pdf_bytes.startswith(b"%PDF"):
        raise HTTPException(status_code=400, detail="The uploaded file is not a valid PDF.")

    try:
        result = extract_lottery_results(pdf_bytes)
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except ValueError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail="Gemini could not process this PDF.") from error

    if not result:
        raise HTTPException(status_code=502, detail="Gemini returned no lottery results.")

    return result


@app.post("/results/import")
def import_draw_result(file: UploadFile = File(...)) -> dict:
    if not file.filename or not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Upload a PDF file.")

    pdf_bytes = file.file.read()
    if not pdf_bytes.startswith(b"%PDF"):
        raise HTTPException(status_code=400, detail="The uploaded file is not a valid PDF.")

    try:
        result = extract_lottery_results(pdf_bytes)
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except ValueError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail="Gemini could not process this PDF.") from error

    draw_id = save_draw_result(
        lottery_name=result.get("lottery_name", "Unknown"),
        draw_date=result.get("draw_date", "unknown"),
        source_url=None,
        pdf_path=None,
        draw_code=result.get("draw_code"),
    )

    for prize in result.get("winners", []):
        tier = prize.get("prize_tier", "Unknown")
        numbers = prize.get("numbers", [])
        for number in numbers:
            if number:
                save_winner(draw_id, tier, str(number), prize.get("prize_amount"))

    return {
        "draw_id": draw_id,
        "lottery_name": result.get("lottery_name", "Unknown"),
        "draw_code": result.get("draw_code"),
        "draw_date": result.get("draw_date", "unknown"),
        "stored_winners": sum(1 for prize in result.get("winners", []) for _ in prize.get("numbers", [])),
    }


@app.post("/results/fetch-latest")
def fetch_latest_result() -> dict[str, Any]:
    try:
        return _download_and_store_latest_result()
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail=f"Unable to fetch latest result: {error}") from error


@app.get("/results")
def get_results() -> list[dict]:
    return list_latest_draws(limit=20)


@app.post("/check-ticket")
def check_ticket(ticket: dict) -> dict:
    ticket_code = str(ticket.get("ticket_code", "")).strip()
    if not ticket_code:
        raise HTTPException(status_code=400, detail="ticket_code is required.")

    draw_date = str(ticket.get("draw_date", "")).strip()
    if not draw_date:
        raise HTTPException(status_code=400, detail="draw_date is required.")

    matches = find_ticket_matches(ticket_code, draw_date)
    return {
        "ticket_code": ticket_code,
        "draw_date": draw_date,
        "matches": matches,
        "found": bool(matches),
    }
