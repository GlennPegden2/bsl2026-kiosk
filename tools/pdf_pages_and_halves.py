#!/usr/bin/env python3
"""Export PDF pages as high-res images, then split each page into left/right halves.

Designed for running on Windows from this repository.

Usage examples (from repo root):
    py tools\\pdf_pages_and_halves.py --pdf .\\myfile.pdf
    py tools\\pdf_pages_and_halves.py --pdf .\\myfile.pdf --dpi 400 --format jpg --jpeg-quality 95

If --pdf is omitted, the script will auto-detect a single PDF in the repository root.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


try:
    import pypdfium2 as pdfium
except ImportError:
    print(
        "Missing dependency: pypdfium2\n"
        "Install with: py -m pip install pypdfium2 pillow",
        file=sys.stderr,
    )
    raise


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Extract every PDF page as a high-resolution image, then save left/right halves "
            "for each page."
        )
    )
    parser.add_argument(
        "--pdf",
        type=Path,
        default=None,
        help="Path to input PDF. If omitted, auto-detects one PDF in repo root.",
    )
    parser.add_argument(
        "--dpi",
        type=int,
        default=400,
        help="Render DPI for exported page images (default: 400).",
    )
    parser.add_argument(
        "--format",
        choices=("png", "jpg"),
        default="png",
        help="Output image format (default: png).",
    )
    parser.add_argument(
        "--jpeg-quality",
        type=int,
        default=95,
        help="JPEG quality (1-100) used only when --format jpg (default: 95).",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("output_pdf_images"),
        help="Output directory (default: output_pdf_images).",
    )
    return parser.parse_args()


def resolve_pdf_path(requested_pdf: Path | None, repo_root: Path) -> Path:
    if requested_pdf is not None:
        pdf_path = requested_pdf if requested_pdf.is_absolute() else (repo_root / requested_pdf)
        if not pdf_path.exists():
            raise FileNotFoundError(f"PDF not found: {pdf_path}")
        if pdf_path.suffix.lower() != ".pdf":
            raise ValueError(f"Input file is not a PDF: {pdf_path}")
        return pdf_path

    root_pdfs = sorted(repo_root.glob("*.pdf"))
    if len(root_pdfs) == 1:
        return root_pdfs[0]
    if not root_pdfs:
        raise FileNotFoundError(
            "No PDF found in repository root. Provide one with --pdf <path-to-pdf>."
        )
    raise ValueError(
        "Multiple PDFs found in repository root. Please pick one with --pdf <path-to-pdf>."
    )


def save_image(image, path: Path, fmt: str, jpeg_quality: int) -> None:
    if fmt == "jpg":
        image = image.convert("RGB")
        image.save(path, "JPEG", quality=jpeg_quality, optimize=True)
    else:
        image.save(path, "PNG", optimize=True)


def main() -> int:
    args = parse_args()

    if args.dpi < 72:
        print("DPI below 72 is not recommended. Please use 72 or higher.", file=sys.stderr)
        return 2

    if not (1 <= args.jpeg_quality <= 100):
        print("--jpeg-quality must be between 1 and 100.", file=sys.stderr)
        return 2

    repo_root = Path(__file__).resolve().parent.parent

    try:
        pdf_path = resolve_pdf_path(args.pdf, repo_root)
    except (FileNotFoundError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 2

    out_root = args.out if args.out.is_absolute() else (repo_root / args.out)
    full_dir = out_root / "full_pages"
    half_dir = out_root / "halves"
    full_dir.mkdir(parents=True, exist_ok=True)
    half_dir.mkdir(parents=True, exist_ok=True)

    doc = pdfium.PdfDocument(str(pdf_path))
    page_count = len(doc)
    if page_count == 0:
        print(f"No pages found in PDF: {pdf_path}", file=sys.stderr)
        return 2

    ext = args.format
    scale = args.dpi / 72.0

    print(f"Input PDF: {pdf_path}")
    print(f"Pages: {page_count}")
    print(f"DPI: {args.dpi}")
    print(f"Output: {out_root}")

    for i in range(page_count):
        page_num = i + 1
        page = doc[i]
        pil_image = page.render(scale=scale).to_pil()

        full_path = full_dir / f"page_{page_num:03d}.{ext}"
        save_image(pil_image, full_path, ext, args.jpeg_quality)

        width, height = pil_image.size
        mid_x = width // 2

        left_img = pil_image.crop((0, 0, mid_x, height))
        right_img = pil_image.crop((mid_x, 0, width, height))

        left_path = half_dir / f"page_{page_num:03d}_left.{ext}"
        right_path = half_dir / f"page_{page_num:03d}_right.{ext}"

        save_image(left_img, left_path, ext, args.jpeg_quality)
        save_image(right_img, right_path, ext, args.jpeg_quality)

        print(f"Processed page {page_num}/{page_count}")

    print("Done.")
    print(f"Full pages: {full_dir}")
    print(f"Halves: {half_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
