from __future__ import annotations

import os
import time
from typing import Any
from urllib.parse import quote, urlencode

import requests

from parser import extract_lottery_results

DEFAULT_PDF_REPOSITORY = "jithin-4T2/pdf-downloader"
_GITHUB_API_URL = "https://api.github.com"
_GITHUB_RAW_URL = "https://raw.githubusercontent.com"
_RESULTS_DIRECTORY = "lottery_results"
_MAX_GET_ATTEMPTS = 3
_GITHUB_HEADERS = {
    "Accept": "application/vnd.github+json",
    "User-Agent": "KeralaLotteryResults/1.0",
}


def _get_with_retry(
    url: str,
    *,
    timeout: int,
    headers: dict[str, str],
) -> requests.Response:
    for attempt in range(_MAX_GET_ATTEMPTS):
        try:
            response = requests.get(url, timeout=timeout, headers=headers)
            response.raise_for_status()
            return response
        except (requests.ConnectionError, requests.Timeout):
            if attempt == _MAX_GET_ATTEMPTS - 1:
                raise
            time.sleep(2**attempt)
    raise RuntimeError("GET retry loop exited unexpectedly.")


def _find_latest_pdf_path(files: list[dict[str, Any]]) -> str:
    pdf_paths = [
        str(changed_file["filename"])
        for changed_file in files
        if isinstance(changed_file, dict)
        and isinstance(changed_file.get("filename"), str)
        and changed_file["filename"].startswith(f"{_RESULTS_DIRECTORY}/")
        and changed_file["filename"].lower().endswith(".pdf")
        and changed_file.get("status") != "removed"
    ]
    if not pdf_paths:
        raise ValueError(
            f"The latest commit in {_RESULTS_DIRECTORY} does not publish a PDF."
        )
    if len(pdf_paths) != 1:
        raise ValueError(
            f"The latest commit in {_RESULTS_DIRECTORY} changes multiple PDFs; "
            "publish one result PDF per commit."
        )

    path = pdf_paths[0]
    if any(part in {".", ".."} for part in path.split("/")):
        raise ValueError("The published PDF path is invalid.")
    return path


def _parse_result_pdf(pdf_url: str) -> dict[str, Any]:
    pdf_response = _get_with_retry(
        pdf_url,
        timeout=60,
        headers={"User-Agent": "Mozilla/5.0"},
    )
    if not pdf_response.content.startswith(b"%PDF"):
        raise ValueError(f"Downloaded content from {pdf_url} is not a PDF.")
    return extract_lottery_results(pdf_response.content)


def download_draw_code(pdf_url: str) -> str | None:
    return _parse_result_pdf(pdf_url).get("draw_code")


def download_latest_result() -> dict[str, Any]:
    repository = os.getenv(
        "KERALA_LOTTERY_PDF_REPOSITORY",
        DEFAULT_PDF_REPOSITORY,
    )
    commits_url = (
        f"{_GITHUB_API_URL}/repos/{repository}/commits?"
        f"{urlencode({'path': _RESULTS_DIRECTORY, 'per_page': 1})}"
    )
    commits_response = _get_with_retry(
        commits_url,
        timeout=30,
        headers=_GITHUB_HEADERS,
    )
    commits = commits_response.json()
    if (
        not isinstance(commits, list)
        or not commits
        or not isinstance(commits[0], dict)
    ):
        raise ValueError(
            f"No PDF publication commit was found in {repository}/{_RESULTS_DIRECTORY}."
        )

    commit_sha = commits[0].get("sha")
    if not isinstance(commit_sha, str) or not commit_sha:
        raise ValueError("GitHub did not return a commit SHA for the latest PDF.")

    commit_url = f"{_GITHUB_API_URL}/repos/{repository}/commits/{commit_sha}"
    commit_response = _get_with_retry(
        commit_url,
        timeout=30,
        headers=_GITHUB_HEADERS,
    )
    commit = commit_response.json()
    files = commit.get("files", []) if isinstance(commit, dict) else []
    if not isinstance(files, list):
        raise ValueError("GitHub returned an invalid file list for the latest commit.")

    pdf_path = _find_latest_pdf_path(files)
    encoded_path = quote(pdf_path, safe="/")
    pdf_url = f"{_GITHUB_RAW_URL}/{repository}/{commit_sha}/{encoded_path}"
    result = _parse_result_pdf(pdf_url)

    return {
        "lottery_name": result.get("lottery_name", "Unknown"),
        "draw_code": result.get("draw_code"),
        "draw_date": result.get("draw_date", "unknown"),
        "source_url": f"https://github.com/{repository}/blob/{commit_sha}/{encoded_path}",
        "pdf_url": pdf_url,
        "winners": result.get("winners", []),
    }