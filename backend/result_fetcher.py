from __future__ import annotations

import os
from html.parser import HTMLParser
from typing import Any
from urllib.parse import urljoin

import requests

from parser import extract_lottery_results

DEFAULT_SOURCE_URL = "https://result.keralalotteries.com/"


class _ResultLinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.result_links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "a":
            return
        href = dict(attrs).get("href")
        if href and "viewlotisresult.php" in href.lower():
            self.result_links.append(href)


def _find_latest_result_url(html: str, source_url: str) -> str | None:
    parser = _ResultLinkParser()
    parser.feed(html)
    if not parser.result_links:
        return None
    return urljoin(source_url, parser.result_links[0])


def _parse_result_pdf(pdf_url: str) -> dict[str, Any]:
    pdf_response = requests.get(
        pdf_url,
        timeout=60,
        headers={"User-Agent": "Mozilla/5.0"},
    )
    pdf_response.raise_for_status()
    if not pdf_response.content.startswith(b"%PDF"):
        raise ValueError(f"Downloaded content from {pdf_url} is not a PDF.")
    return extract_lottery_results(pdf_response.content)


def download_draw_code(pdf_url: str) -> str | None:
    return _parse_result_pdf(pdf_url).get("draw_code")


def download_latest_result() -> dict[str, Any]:
    source_url = os.getenv("KERALA_LOTTERY_SOURCE_URL", DEFAULT_SOURCE_URL)
    response = requests.get(
        source_url,
        timeout=30,
        headers={"User-Agent": "Mozilla/5.0"},
    )
    response.raise_for_status()

    pdf_url = _find_latest_result_url(response.text, source_url)
    if not pdf_url:
        raise ValueError(f"No draw-result link found on {source_url}.")

    result = _parse_result_pdf(pdf_url)
    return {
        "lottery_name": result.get("lottery_name", "Unknown"),
        "draw_code": result.get("draw_code"),
        "draw_date": result.get("draw_date", "unknown"),
        "source_url": source_url,
        "pdf_url": pdf_url,
        "winners": result.get("winners", []),
    }