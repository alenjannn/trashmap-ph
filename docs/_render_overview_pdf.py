"""Render docs/SYSTEM_OVERVIEW.md to docs/SYSTEM_OVERVIEW.pdf.

Usage:
    python docs/_render_overview_pdf.py

Run from the trashmap-ph project root. Idempotent.
"""
from __future__ import annotations

import re
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


HERE = Path(__file__).resolve().parent
SRC = HERE / "SYSTEM_OVERVIEW.md"
OUT = HERE / "SYSTEM_OVERVIEW.pdf"


def _styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    title = ParagraphStyle(
        "DocTitle", parent=base["Title"], fontSize=22, spaceAfter=14,
        textColor=colors.HexColor("#0F172A"),
    )
    h1 = ParagraphStyle(
        "H1", parent=base["Heading1"], fontSize=16, spaceBefore=14, spaceAfter=8,
        textColor=colors.HexColor("#0F172A"),
    )
    h2 = ParagraphStyle(
        "H2", parent=base["Heading2"], fontSize=13, spaceBefore=10, spaceAfter=6,
        textColor=colors.HexColor("#1E40AF"),
    )
    h3 = ParagraphStyle(
        "H3", parent=base["Heading3"], fontSize=11, spaceBefore=8, spaceAfter=4,
        textColor=colors.HexColor("#334155"),
    )
    body = ParagraphStyle(
        "Body", parent=base["BodyText"], fontSize=10, leading=14, spaceAfter=6,
        textColor=colors.HexColor("#1F2937"),
    )
    bullet = ParagraphStyle(
        "Bullet", parent=body, leftIndent=14, bulletIndent=4, spaceAfter=2,
    )
    code = ParagraphStyle(
        "Code", parent=body, fontName="Courier", fontSize=9, leading=11,
        textColor=colors.HexColor("#0F172A"), backColor=colors.HexColor("#F1F5F9"),
        leftIndent=8, rightIndent=8, spaceBefore=4, spaceAfter=8,
    )
    quote = ParagraphStyle(
        "Quote", parent=body, leftIndent=12, textColor=colors.HexColor("#475569"),
        backColor=colors.HexColor("#F8FAFC"),
    )
    return {
        "title": title, "h1": h1, "h2": h2, "h3": h3,
        "body": body, "bullet": bullet, "code": code, "quote": quote,
    }


def _inline(text: str) -> str:
    """Convert simple Markdown inline syntax to ReportLab mini-XML."""
    s = escape(text)
    s = re.sub(r"`([^`]+)`", r'<font face="Courier" size="9">\1</font>', s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"\*([^*]+)\*", r"<i>\1</i>", s)
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<link href="\2"><font color="#1D4ED8">\1</font></link>', s)
    return s


def _table_from_md(rows: list[list[str]], styles: dict[str, ParagraphStyle]) -> Table:
    body = styles["body"]
    cells = [[Paragraph(_inline(c), body) for c in row] for row in rows]
    col_count = max(len(r) for r in cells)
    cells = [r + [Paragraph("", body)] * (col_count - len(r)) for r in cells]
    page_w = LETTER[0] - 1.5 * inch
    col_w = page_w / col_count
    t = Table(cells, colWidths=[col_w] * col_count, repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#0F172A")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.whitesmoke),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, 0), 10),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 6),
        ("TOPPADDING", (0, 0), (-1, 0), 6),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F8FAFC")]),
        ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#CBD5E1")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 1), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 1), (-1, -1), 4),
    ]))
    return t


def parse(md: str, styles: dict[str, ParagraphStyle]) -> list:
    flow: list = []
    lines = md.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            buf = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1
            block = "<br/>".join(escape(x).replace(" ", "&nbsp;") for x in buf)
            flow.append(Paragraph(block, styles["code"]))
            continue
        if line.startswith("|") and i + 1 < len(lines) and re.match(r"^\|[\s\-:|]+\|$", lines[i + 1]):
            tbl_rows: list[list[str]] = []
            while i < len(lines) and lines[i].startswith("|"):
                if re.match(r"^\|[\s\-:|]+\|$", lines[i]):
                    i += 1
                    continue
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                tbl_rows.append(cells)
                i += 1
            flow.append(_table_from_md(tbl_rows, styles))
            flow.append(Spacer(1, 6))
            continue
        if line.startswith("# "):
            flow.append(Paragraph(_inline(line[2:]), styles["title"]))
        elif line.startswith("## "):
            flow.append(Paragraph(_inline(line[3:]), styles["h1"]))
        elif line.startswith("### "):
            flow.append(Paragraph(_inline(line[4:]), styles["h2"]))
        elif line.startswith("#### "):
            flow.append(Paragraph(_inline(line[5:]), styles["h3"]))
        elif line.startswith("> "):
            flow.append(Paragraph(_inline(line[2:]), styles["quote"]))
        elif line.startswith("- ") or line.startswith("* "):
            flow.append(Paragraph(_inline(line[2:]), styles["bullet"], bulletText="\u2022"))
        elif re.match(r"^\d+\.\s", line):
            flow.append(Paragraph(_inline(line.split(" ", 1)[1]), styles["bullet"], bulletText=line.split(".", 1)[0] + "."))
        elif line.strip() == "---":
            flow.append(Spacer(1, 6))
        elif line.strip() == "":
            flow.append(Spacer(1, 4))
        else:
            flow.append(Paragraph(_inline(line), styles["body"]))
        i += 1
    return flow


def main() -> None:
    md = SRC.read_text(encoding="utf-8")
    styles = _styles()
    flow = parse(md, styles)
    doc = SimpleDocTemplate(
        str(OUT),
        pagesize=LETTER,
        leftMargin=0.75 * inch,
        rightMargin=0.75 * inch,
        topMargin=0.75 * inch,
        bottomMargin=0.75 * inch,
        title="TrashMap PH — System Overview & Developer Guide",
        author="TrashMap PH team",
    )
    doc.build(flow)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
