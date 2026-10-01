import re
from datetime import datetime
from io import BytesIO

from pypdf import PdfReader

_DRAW_HEADER = re.compile(
    r"(?P<name>[A-Z][A-Z '\-&]*?)\s+LOTTERY\s+NO\.\s*"
    r"[A-Z]{2}-\d+(?:ST|ND|RD|TH)\s+DRAW\s+HELD\s+ON\s*:-?\s*"
    r"(?P<date>\d{2}/\d{2}/\d{4})",
    re.IGNORECASE,
)
_PRIZE_HEADER = re.compile(
    r"(?P<tier>\d+(?:ST|ND|RD|TH)|CONS(?:OLATION)?)\s*"
    r"PRIZE\s*-?\s*RS\s*:?\s*[\d,]+\s*/-?",
    re.IGNORECASE,
)
_SERIAL_NUMBER = re.compile(r"\b[A-Z]{2}\s+\d{6}\b", re.IGNORECASE)
_ENDING_NUMBER = re.compile(r"\b\d{4}\b")
_PAGE_FOOTER = re.compile(
    r"PAGE\s+\d+\s*MODERNIZATION\s*&\s*IT\s*SOFTWARE\s*DIVISION\s*:\s*"
    r"DEPARTMENT\s*OF\s*STATE\s*LOTTERIES\s*\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}:\d{2}",
    re.IGNORECASE,
)
_NEXT_DRAW_NOTE = re.compile(r"\bNEXT\s+.+?\s+DRAW\s+WILL\s+BE\s+HELD\s+ON\b.*", re.IGNORECASE)


def _parse_lottery_text(text: str) -> dict:
    normalized_text = " ".join(text.split())
    normalized_text = _PAGE_FOOTER.sub(" ", normalized_text)
    normalized_text = _NEXT_DRAW_NOTE.sub(" ", normalized_text)
    draw = _DRAW_HEADER.search(normalized_text)
    if not draw:
        raise ValueError("Could not identify the draw name and date in the result PDF.")

    prize_headers = list(_PRIZE_HEADER.finditer(normalized_text))
    winners = []
    for index, header in enumerate(prize_headers):
        end = prize_headers[index + 1].start() if index + 1 < len(prize_headers) else len(normalized_text)
        section = normalized_text[header.end():end]
        tier = header.group("tier")
        if tier.lower().startswith("cons"):
            prize_tier = "Consolation"
            numbers = _SERIAL_NUMBER.findall(section)
        elif tier[0].isdigit() and int(re.match(r"\d+", tier).group()) <= 3:
            prize_tier = tier.lower()
            numbers = _SERIAL_NUMBER.findall(section)
        else:
            prize_tier = tier.lower()
            numbers = _ENDING_NUMBER.findall(section)

        if numbers:
            winners.append({"prize_tier": prize_tier, "numbers": numbers})

    if not winners:
        raise ValueError("No winning numbers were found in the result PDF.")

    lottery_name = re.sub(r"^in\s+", "", draw.group("name").strip(), flags=re.IGNORECASE)
    return {
        "lottery_name": lottery_name,
        "draw_date": datetime.strptime(draw.group("date"), "%d/%m/%Y").date().isoformat(),
        "winners": winners,
    }


def extract_lottery_results(pdf_bytes: bytes) -> dict:
    try:
        reader = PdfReader(BytesIO(pdf_bytes))
        text = "\n".join(page.extract_text() or "" for page in reader.pages)
    except Exception as error:
        raise ValueError("Could not read the official result PDF.") from error

    if not text.strip():
        raise ValueError("The result PDF contains no selectable text; OCR is required.")
    return _parse_lottery_text(text)
