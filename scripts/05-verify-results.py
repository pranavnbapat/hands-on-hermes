#!/usr/bin/env python3
"""Check a workshop sales CSV and work out the real figures, no LLM involved.

Every row is validated (quantity x unit_price must equal total_revenue, in
exact Decimal arithmetic), then totals per product and category are printed.
With --report it compares an agent-written Markdown report against them, which
is how you catch made-up or mis-added numbers.

    python3 scripts/05-verify-results.py --dataset data/sales-sample.csv
    python3 scripts/05-verify-results.py --dataset data/sales-sample.csv \\
        --report ~/hermes-workshop-lab/reports/first-report.md

Standard library only, Python 3.8+.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import defaultdict
from datetime import date
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from pathlib import Path

REQUIRED_COLUMNS = (
    "transaction_id", "date", "product", "category", "quantity", "unit_price", "total_revenue",
)
CENT = Decimal("0.01")
MAX_ERRORS_SHOWN = 20


class DatasetError(Exception):
    """The CSV can't be trusted; .problems lists everything wrong with it."""

    def __init__(self, problems):
        super().__init__(f"{len(problems)} problem(s) found")
        self.problems = problems


def parse_money(raw: str, field: str, line: int, problems: list):
    """Parse a non-negative amount with at most two decimal places."""
    try:
        value = Decimal(raw)
    except InvalidOperation:
        problems.append(f"line {line}: {field} '{raw}' is not a number")
        return None
    if not value.is_finite() or value < 0:
        problems.append(f"line {line}: {field} '{raw}' must be a non-negative number")
        return None
    if value != value.quantize(CENT):
        problems.append(f"line {line}: {field} '{raw}' has more than two decimal places")
        return None
    return value


def load_dataset(path: Path):
    """Read and validate the CSV. Returns a list of row dicts with typed values."""
    if not path.is_file():
        raise DatasetError([f"file not found: {path}"])
    problems, rows, seen_ids = [], [], {}
    try:
        with path.open(newline="", encoding="utf-8-sig") as stream:
            reader = csv.DictReader(stream)
            header = [name.strip() for name in (reader.fieldnames or [])]
            missing = [col for col in REQUIRED_COLUMNS if col not in header]
            if missing:
                raise DatasetError([f"missing column(s): {', '.join(missing)}; found: {', '.join(header) or 'none'}"])
            reader.fieldnames = header
            for line, raw in enumerate(reader, start=2):  # line 1 is the header
                if None in raw:
                    problems.append(f"line {line}: more fields than the header")
                    continue
                row = {key: (raw.get(key) or "").strip() for key in REQUIRED_COLUMNS}
                empty = [key for key, value in row.items() if not value]
                if empty:
                    problems.append(f"line {line}: empty value(s) in {', '.join(empty)}")
                    continue
                if row["transaction_id"] in seen_ids:
                    problems.append(
                        f"line {line}: duplicate transaction_id {row['transaction_id']} "
                        f"(first seen on line {seen_ids[row['transaction_id']]})")
                seen_ids.setdefault(row["transaction_id"], line)
                try:
                    day = date.fromisoformat(row["date"])
                except ValueError:
                    problems.append(f"line {line}: date '{row['date']}' is not ISO format YYYY-MM-DD")
                    day = None
                try:
                    quantity = int(row["quantity"])
                    if quantity <= 0:
                        raise ValueError
                except ValueError:
                    problems.append(f"line {line}: quantity '{row['quantity']}' must be a positive integer")
                    quantity = None
                price = parse_money(row["unit_price"], "unit_price", line, problems)
                total = parse_money(row["total_revenue"], "total_revenue", line, problems)
                if None in (day, quantity, price, total):
                    continue
                if price * quantity != total:
                    problems.append(
                        f"line {line}: {row['transaction_id']} total_revenue {total} != "
                        f"quantity {quantity} x unit_price {price} = {price * quantity}")
                    continue
                rows.append({**row, "date": day, "quantity": quantity, "unit_price": price, "total_revenue": total})
    except UnicodeDecodeError as exc:
        raise DatasetError([f"file is not valid UTF-8 text: {exc}"]) from exc
    except csv.Error as exc:
        raise DatasetError([f"CSV parsing error: {exc}"]) from exc
    if not rows and not problems:
        problems.append("the file has a header but no data rows")
    if problems:
        raise DatasetError(problems)
    return rows


def ranked(mapping: dict, key):
    """Sort by value descending, then name ascending (deterministic ties)."""
    return sorted(mapping.items(), key=lambda item: (-key(item[1]), item[0]))


def summarise(rows, top_n: int) -> dict:
    """Compute every reference figure from validated rows."""
    by_product = defaultdict(lambda: {"revenue": Decimal("0.00"), "units": 0, "transactions": 0, "category": None})
    by_category = defaultdict(lambda: {"revenue": Decimal("0.00"), "units": 0})
    categories_seen = defaultdict(set)
    prices_seen = defaultdict(set)
    for row in rows:
        product = by_product[row["product"]]
        product["revenue"] += row["total_revenue"]
        product["units"] += row["quantity"]
        product["transactions"] += 1
        product["category"] = row["category"]
        categories_seen[row["product"]].add(row["category"])
        prices_seen[row["product"]].add(row["unit_price"])
        by_category[row["category"]]["revenue"] += row["total_revenue"]
        by_category[row["category"]]["units"] += row["quantity"]

    total = sum((r["total_revenue"] for r in rows), Decimal("0.00"))
    units = sum(r["quantity"] for r in rows)
    warnings = [f"product '{name}' appears under several categories: {', '.join(sorted(cats))}"
                for name, cats in sorted(categories_seen.items()) if len(cats) > 1]
    notes = [f"product '{name}' is sold at several unit prices: {', '.join(str(p) for p in sorted(prices))}"
             for name, prices in sorted(prices_seen.items()) if len(prices) > 1]

    def share(value: Decimal) -> str:
        return str((value * 100 / total).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP)) if total else "0.0"

    products = [
        {"product": name, "category": info["category"], "revenue": str(info["revenue"]),
         "units": info["units"], "transactions": info["transactions"], "share_percent": share(info["revenue"])}
        for name, info in ranked(by_product, lambda info: info["revenue"])
    ]
    categories = [
        {"category": name, "revenue": str(info["revenue"]), "units": info["units"],
         "share_percent": share(info["revenue"])}
        for name, info in ranked(by_category, lambda info: info["revenue"])
    ]
    by_units = [{"product": name, "units": info["units"]}
                for name, info in ranked(by_product, lambda info: info["units"])]

    top_revenue = products[:top_n]
    if len(products) > top_n and products[top_n - 1]["revenue"] == products[top_n]["revenue"]:
        warnings.append(f"tie at position {top_n}: the top-{top_n} list by revenue is not unique")

    return {
        "rows": len(rows),
        "first_date": min(r["date"] for r in rows).isoformat(),
        "last_date": max(r["date"] for r in rows).isoformat(),
        "total_revenue": str(total),
        "total_units": units,
        "average_transaction_value": str((total / len(rows)).quantize(CENT, rounding=ROUND_HALF_UP)),
        "products": products,
        "categories": categories,
        "top_products_by_revenue": [p["product"] for p in top_revenue],
        "top_products_by_units": [p["product"] for p in by_units[:top_n]],
        "warnings": warnings,
        "notes": notes,
    }


def money(value) -> str:
    return f"{Decimal(value):,.2f}"


def short(name: str, limit: int = 40) -> str:
    """Shorten long names for display; the maths always uses the full name."""
    return name if len(name) <= limit else name[: limit - 1] + "…"


def render_text(summary: dict, dataset: Path) -> str:
    width = max(len(short(p["product"])) for p in summary["products"])
    cat_width = max(len(c["category"]) for c in summary["categories"])
    lines = [
        f"Dataset:          {dataset}",
        "Validation:       PASS (every row satisfies quantity x unit_price == total_revenue)",
        f"Rows:             {summary['rows']}",
        f"Date range:       {summary['first_date']} to {summary['last_date']}",
        f"Total revenue:    {money(summary['total_revenue'])}",
        f"Total units:      {summary['total_units']}",
        f"Avg transaction:  {money(summary['average_transaction_value'])}",
        "",
        "Revenue by product (highest first):",
    ]
    for rank, p in enumerate(summary["products"], start=1):
        lines.append(f"  {rank:>2}. {short(p['product']):<{width}}  {money(p['revenue']):>10}  "
                     f"{p['share_percent']:>5}%  units={p['units']}")
    lines += ["", "Revenue by category:"]
    for c in summary["categories"]:
        lines.append(f"      {c['category']:<{cat_width}}  {money(c['revenue']):>10}  {c['share_percent']:>5}%")
    lines += [
        "",
        f"Top products by revenue: {', '.join(short(n) for n in summary['top_products_by_revenue'])}",
        f"Top products by units:   {', '.join(short(n) for n in summary['top_products_by_units'])}",
    ]
    lines += [f"WARNING: {w}" for w in summary["warnings"]]
    lines += [f"NOTE: {n}" for n in summary["notes"]]
    return "\n".join(lines)


def render_markdown(summary: dict, dataset: Path) -> str:
    lines = [
        f"# Sales report: {dataset.name}",
        "",
        "> Reference report generated deterministically by `scripts/05-verify-results.py`.",
        "> An agent-written report will be worded differently, but its figures must match these.",
        "",
        "## Dataset",
        "",
        f"- File: `{dataset.name}`",
        f"- Transactions (rows): {summary['rows']}",
        f"- Period: {summary['first_date']} to {summary['last_date']}",
        "- Row check: every row satisfies `quantity x unit_price = total_revenue`",
        "",
        "## Headline figures",
        "",
        "| Metric | Value |",
        "|---|---:|",
        f"| Total revenue | {money(summary['total_revenue'])} |",
        f"| Units sold | {summary['total_units']} |",
        f"| Average transaction value | {money(summary['average_transaction_value'])} |",
        "",
        "## Revenue by product",
        "",
        "| Rank | Product | Category | Units | Revenue | Share |",
        "|---:|---|---|---:|---:|---:|",
    ]
    for rank, p in enumerate(summary["products"], start=1):
        lines.append(f"| {rank} | {p['product']} | {p['category']} | {p['units']} | "
                     f"{money(p['revenue'])} | {p['share_percent']}% |")
    lines += ["", "## Revenue by category", "", "| Category | Units | Revenue | Share |", "|---|---:|---:|---:|"]
    for c in summary["categories"]:
        lines.append(f"| {c['category']} | {c['units']} | {money(c['revenue'])} | {c['share_percent']}% |")
    top_rev, top_units = summary["top_products_by_revenue"], summary["top_products_by_units"]
    lines += [
        "",
        "## Highest-performing products",
        "",
        f"- By revenue: {', '.join(top_rev)}.",
        f"- By units sold: {', '.join(top_units)}.",
    ]
    if top_rev[0] != top_units[0]:
        lines.append(f"- Note: the revenue leader ({top_rev[0]}) is not the volume leader ({top_units[0]}). "
                     "A report must say which definition of \"highest-performing\" it uses.")
    lines += ["", "## Verification and limitations", "",
              "- Figures computed with exact decimal arithmetic; no rounding until display.",
              "- The data is fictional and contains no customer, discount, tax or currency fields.",
              "- Amounts are shown without a currency symbol because the dataset does not specify one."]
    lines += [f"- Warning: {w}" for w in summary["warnings"]]
    return "\n".join(lines) + "\n"


# Report checks
_NUMBER = re.compile(r"(?<![\w.])-?\d+(?:\.\d+)?(?![\w])")
_THOUSANDS = re.compile(r"(?<=\d),(?=\d{3}\b)")
_TOP_WORDS = re.compile(r"\b(top|highest|best|leading|leader|largest|number one|#1)\b", re.IGNORECASE)


def numbers_in(line: str):
    """Extract numbers from a line, tolerating '1,234.56', currency symbols and '%'."""
    cleaned = _THOUSANDS.sub("", line)
    cleaned = re.sub(r"[€$£¥*_`|]", " ", cleaned)
    values = []
    for token in _NUMBER.findall(cleaned):
        try:
            values.append(Decimal(token))
        except InvalidOperation:
            pass
    return values


def check_report(report: Path, summary: dict):
    """Return (checks, failed) where checks is a list of (status, message)."""
    text = report.read_text(encoding="utf-8")
    lines = text.splitlines()
    all_numbers = [n for line in lines for n in numbers_in(line)]
    checks = []

    def lines_mentioning(name: str):
        pattern = re.compile(r"(?<![\w-])" + re.escape(name) + r"(?![\w-])", re.IGNORECASE)
        return [line for line in lines if pattern.search(line)]

    total = Decimal(summary["total_revenue"])
    checks.append(("PASS", f"grand total {money(total)} found") if total in all_numbers
                  else ("FAIL", f"grand total {money(total)} not found anywhere in the report"))

    rows = Decimal(summary["rows"])
    checks.append(("PASS", f"row count {summary['rows']} found") if rows in all_numbers
                  else ("WARN", f"row count {summary['rows']} not found (fine if written in words)"))

    for p in summary["products"]:
        expected = Decimal(p["revenue"])
        mentions = lines_mentioning(p["product"])
        if not mentions:
            checks.append(("FAIL", f"product '{p['product']}' is missing from the report"))
            continue
        if any(expected in numbers_in(line) for line in mentions):
            checks.append(("PASS", f"{p['product']}: revenue {money(expected)} matches"))
        else:
            seen = sorted({str(n) for line in mentions for n in numbers_in(line)}, key=lambda s: Decimal(s))
            checks.append(("FAIL", f"{p['product']}: expected revenue {money(expected)}; numbers next to it "
                                   f"in the report: {', '.join(seen) or 'none'}"))

    for c in summary["categories"]:
        expected = Decimal(c["revenue"])
        if any(expected in numbers_in(line) for line in lines_mentioning(c["category"])):
            checks.append(("PASS", f"category {c['category']}: revenue {money(expected)} matches"))
        else:
            checks.append(("WARN", f"category {c['category']}: total {money(expected)} not found "
                                   "(fine if the report has no category breakdown)"))

    leader = summary["top_products_by_revenue"][0]
    claim_lines = [line for line in lines if _TOP_WORDS.search(line)]
    if any(leader.lower() in line.lower() for line in claim_lines):
        checks.append(("PASS", f"revenue leader '{leader}' is named in a top/highest statement"))
    else:
        checks.append(("WARN", f"could not find '{leader}' named as the top product by revenue; "
                               "read the report's claims manually"))

    failed = sum(1 for status, _ in checks if status == "FAIL")
    return checks, failed


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate a workshop sales CSV and compute reference figures without an LLM.",
        epilog="Exit codes: 0 OK, 1 report mismatch, 2 invalid input.")
    parser.add_argument("--dataset", type=Path, required=True, help="path to a sales CSV file")
    parser.add_argument("--report", type=Path, help="agent-written Markdown report to check against the data")
    parser.add_argument("--format", choices=("text", "json", "markdown"), default="text",
                        help="output format for the reference figures (default: text)")
    parser.add_argument("--top", type=int, default=3, help="how many top products to list (default: 3)")
    args = parser.parse_args(argv)

    if args.top < 1:
        parser.error("--top must be at least 1")
    dataset = args.dataset.expanduser()
    try:
        rows = load_dataset(dataset)
    except DatasetError as exc:
        print(f"Dataset:    {dataset}", file=sys.stderr)
        print(f"Validation: FAIL ({len(exc.problems)} problem(s))", file=sys.stderr)
        for problem in exc.problems[:MAX_ERRORS_SHOWN]:
            print(f"  - {problem}", file=sys.stderr)
        if len(exc.problems) > MAX_ERRORS_SHOWN:
            print(f"  ... and {len(exc.problems) - MAX_ERRORS_SHOWN} more", file=sys.stderr)
        print("Do not trust any report produced from this file until the data is fixed.", file=sys.stderr)
        return 2

    summary = summarise(rows, args.top)

    if args.report is None:
        if args.format == "json":
            print(json.dumps(summary, indent=2))
        elif args.format == "markdown":
            sys.stdout.write(render_markdown(summary, dataset))
        else:
            print(render_text(summary, dataset))
        return 0

    report = args.report.expanduser()
    if not report.is_file():
        print(f"Report not found: {report}", file=sys.stderr)
        return 2
    try:
        checks, failed = check_report(report, summary)
    except UnicodeDecodeError:
        print(f"Report is not valid UTF-8 text: {report}", file=sys.stderr)
        return 2
    print(f"Dataset: {dataset}")
    print(f"Report:  {report}")
    print()
    for status, message in checks:
        print(f"  [{status}] {message}")
    print()
    warned = sum(1 for status, _ in checks if status == "WARN")
    if failed:
        print(f"RESULT: {failed} check(s) FAILED, {warned} warning(s). "
              "Do not trust this report; ask the agent to recompute using a tool, then re-check.")
        return 1
    print(f"RESULT: all required figures match ({warned} warning(s) to review manually).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
