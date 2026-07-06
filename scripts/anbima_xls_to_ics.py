#!/usr/bin/env python3
"""Convert ANBIMA's national banking-holiday spreadsheet to an iCalendar file.

Usage:
    python3 anbima_xls_to_ics.py feriados_nacionais.xls feriados_anbima.ics

Source spreadsheet: https://www.anbima.com.br/feriados/arqs/feriados_nacionais.xls
(sheet "Feriados": Data | Dia da Semana | Feriado, one row per holiday,
2001 through 2099, footnote rows at the bottom).

Each holiday becomes an all-day VEVENT with a half-open [DTSTART, DTEND)
day span, which is both the RFC 5545 semantic for date-valued DTEND and
the convention business-day counting (BUS/252) requires.

Output is deterministic: fixed DTSTAMP, stable UIDs keyed on the date, so
regenerated files diff cleanly against the previous version.

The generated file loads directly via `Tempo.ICal.from_ical_file/1` — see the
"Business/252" recipe in guides/cookbook.md for the year-fraction pipeline
built on it.

Requires: pip install xlrd
"""

import sys
from datetime import date, timedelta

import xlrd

# Fixed timestamp so regeneration is reproducible; bump when ANBIMA
# republishes the spreadsheet.
DTSTAMP = "20231222T000000Z"


def escape_text(value):
    """Escape TEXT per RFC 5545 section 3.3.11."""
    return (
        value.replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\n", "\\n")
    )


def fold(line):
    """Fold a content line at 75 octets per RFC 5545 section 3.1."""
    encoded = line.encode("utf-8")
    if len(encoded) <= 75:
        return [line]
    parts = []
    while encoded:
        take = 75 if not parts else 74
        # Do not split inside a UTF-8 sequence.
        while take > 1 and (encoded[take - 1 : take][0] & 0xC0) == 0x80:
            take -= 1
        chunk, encoded = encoded[:take], encoded[take:]
        parts.append(("" if not parts else " ") + chunk.decode("utf-8"))
    return parts


def read_holidays(xls_path):
    """Yield (date, name) for every holiday row in the spreadsheet."""
    book = xlrd.open_workbook(xls_path)
    sheet = book.sheet_by_name("Feriados")
    for row in range(sheet.nrows):
        if sheet.cell_type(row, 0) != xlrd.XL_CELL_DATE:
            continue  # header and footnote rows
        serial = sheet.cell_value(row, 0)
        year, month, day, *_ = xlrd.xldate_as_tuple(serial, book.datemode)
        name = str(sheet.cell_value(row, 2)).strip()
        yield date(year, month, day), name


def build_ics(holidays):
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//anbima-feriados//xls-to-ics//PT",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "X-WR-CALNAME:Feriados Bancários Nacionais (ANBIMA)",
        "X-WR-TIMEZONE:America/Sao_Paulo",
    ]
    for day, name in holidays:
        lines += [
            "BEGIN:VEVENT",
            f"UID:anbima-{day:%Y%m%d}@anbima.com.br",
            f"DTSTAMP:{DTSTAMP}",
            f"DTSTART;VALUE=DATE:{day:%Y%m%d}",
            f"DTEND;VALUE=DATE:{day + timedelta(days=1):%Y%m%d}",
            f"SUMMARY:{escape_text(name)}",
            "TRANSP:TRANSPARENT",
            "END:VEVENT",
        ]
    lines.append("END:VCALENDAR")
    return "\r\n".join(folded for line in lines for folded in fold(line)) + "\r\n"


def main():
    if len(sys.argv) != 3:
        sys.exit(f"usage: {sys.argv[0]} <feriados.xls> <output.ics>")
    xls_path, ics_path = sys.argv[1], sys.argv[2]

    holidays = sorted(read_holidays(xls_path))
    if not holidays:
        sys.exit("no holiday rows found — has the spreadsheet layout changed?")

    with open(ics_path, "w", encoding="utf-8", newline="") as out:
        out.write(build_ics(holidays))

    first, last = holidays[0][0], holidays[-1][0]
    print(f"{len(holidays)} holidays from {first} to {last} written to {ics_path}")


if __name__ == "__main__":
    main()
