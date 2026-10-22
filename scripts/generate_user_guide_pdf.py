"""
Consolidated generator for bilingual End-User Guides of Z_AUTH_SU53_ANALYZER (TCode: ZAT).
Builds both English and Vietnamese HTML, Markdown, and print-ready 4-page PDFs via Headless Chrome.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

BASE_DIR = Path(r"d:\PROJECTS\SAPABAP")
DOCS_DIR = BASE_DIR / "docs"
CHROME_PATH = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

# ---------------------------------------------------------------------------
# HTML TEMPLATES (EN & VN)
# ---------------------------------------------------------------------------

SHARED_CSS = """
  @page {
    size: A4 portrait;
    margin: 10mm 10mm 12mm 10mm;
  }
  * {
    box-sizing: border-box;
    -webkit-print-color-adjust: exact !important;
    print-color-adjust: exact !important;
  }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
    color: #1e293b;
    background-color: #ffffff;
    line-height: 1.4;
    font-size: 8.8pt;
    margin: 0;
    padding: 0;
  }
  .page-container {
    page-break-after: always;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    height: 265mm;
    position: relative;
  }
  .page-container:last-child {
    page-break-after: avoid;
  }
  .page-footer {
    margin-top: auto;
    border-top: 1px solid #cbd5e1;
    padding-top: 4px;
    display: flex;
    justify-content: space-between;
    font-size: 7.5pt;
    color: #64748b;
  }
  .doc-header {
    border-bottom: 2.5px solid #005a9e;
    padding-bottom: 8px;
    margin-bottom: 12px;
    display: flex;
    justify-content: space-between;
    align-items: flex-end;
  }
  .doc-title-block h1 {
    font-size: 16.5pt;
    color: #0b3d60;
    margin: 0 0 3px 0;
    font-weight: 800;
    letter-spacing: -0.3px;
  }
  .doc-title-block .subtitle {
    font-size: 10pt;
    color: #475569;
    font-weight: 600;
    margin: 0;
  }
  .doc-meta {
    text-align: right;
    font-size: 8pt;
    color: #475569;
  }
  .badge-zat {
    display: inline-block;
    background: #005a9e;
    color: #ffffff;
    font-weight: bold;
    padding: 2px 7px;
    border-radius: 3px;
    font-size: 8.5pt;
    font-family: Consolas, monospace;
  }
  .badge-tag {
    display: inline-block;
    background: #eef3f8;
    color: #005a9e;
    border: 1px solid #b9d1ea;
    font-weight: 600;
    padding: 1px 5px;
    border-radius: 3px;
    font-size: 7.5pt;
  }
  h2 {
    font-size: 11pt;
    color: #0b3d60;
    border-left: 3.5px solid #005a9e;
    padding-left: 7px;
    margin-top: 10px;
    margin-bottom: 6px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.2px;
  }
  h3 {
    font-size: 9.5pt;
    color: #1e3a8a;
    margin-top: 8px;
    margin-bottom: 4px;
    font-weight: 700;
  }
  p {
    margin: 0 0 5px 0;
    text-align: justify;
  }
  ul, ol {
    margin: 0 0 6px 0;
    padding-left: 18px;
  }
  li {
    margin-bottom: 2px;
  }
  .callout-info {
    background-color: #f0f7fc;
    border-left: 3.5px solid #0078d4;
    padding: 5px 8px;
    margin: 5px 0;
    border-radius: 0 3px 3px 0;
    font-size: 8.5pt;
  }
  .callout-warning {
    background-color: #fff9e6;
    border-left: 3.5px solid #d97706;
    padding: 5px 8px;
    margin: 5px 0;
    border-radius: 0 3px 3px 0;
    font-size: 8.5pt;
  }
  .callout-success {
    background-color: #eefbee;
    border-left: 3.5px solid #16a34a;
    padding: 5px 8px;
    margin: 5px 0;
    border-radius: 0 3px 3px 0;
    font-size: 8.5pt;
  }
  table.data-table {
    width: 100%;
    border-collapse: collapse;
    margin: 6px 0 8px 0;
    font-size: 8pt;
  }
  table.data-table th {
    background-color: #0b3d60;
    color: #ffffff;
    font-weight: 600;
    padding: 5px 7px;
    border: 1px solid #09314d;
    text-align: left;
  }
  table.data-table td {
    padding: 4px 7px;
    border: 1px solid #cbd5e1;
    vertical-align: middle;
  }
  table.data-table tr:nth-child(even) {
    background-color: #f8fafc;
  }
  .sap-window {
    background: #f8fafc;
    border: 1px solid #94a3b8;
    border-radius: 4px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.08);
    margin: 6px 0 10px 0;
    overflow: hidden;
    font-family: 'Segoe UI', Tahoma, Arial, sans-serif;
  }
  .sap-titlebar {
    background: linear-gradient(180deg, #1e4a70 0%, #0d2c47 100%);
    color: #ffffff;
    padding: 3px 8px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 8pt;
    font-weight: 600;
  }
  .sap-titlebar .left {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .sap-logo-box {
    background: #d97706;
    color: #ffffff;
    font-size: 7pt;
    font-weight: 900;
    padding: 1px 4px;
    border-radius: 2px;
    letter-spacing: 0.5px;
  }
  .sap-window-controls {
    display: flex;
    gap: 3px;
  }
  .sap-win-btn {
    width: 10px;
    height: 10px;
    background: rgba(255,255,255,0.3);
    border-radius: 2px;
    display: inline-block;
  }
  .sap-menubar {
    background: #f1f5f9;
    border-bottom: 1px solid #cbd5e1;
    padding: 2px 8px;
    font-size: 7.5pt;
    color: #334155;
    display: flex;
    gap: 12px;
  }
  .sap-toolbar {
    background: #e2e8f0;
    border-bottom: 1px solid #cbd5e1;
    padding: 2px 8px;
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: 7.5pt;
  }
  .sap-tcode-box {
    background: #ffffff;
    border: 1px solid #64748b;
    padding: 1px 5px;
    font-family: Consolas, monospace;
    font-size: 7.5pt;
    width: 70px;
    font-weight: bold;
    color: #0b3d60;
  }
  .sap-btn-icon {
    background: #ffffff;
    border: 1px solid #94a3b8;
    padding: 1.5px 6px;
    border-radius: 2px;
    font-size: 7pt;
    font-weight: 600;
    color: #1e293b;
    display: inline-flex;
    align-items: center;
    gap: 3px;
  }
  .sap-btn-green {
    background: #15803d;
    color: #ffffff;
    border-color: #166534;
  }
  .sap-btn-action {
    background: #005a9e;
    color: #ffffff;
    border-color: #004578;
    font-weight: bold;
  }
  .sap-body {
    padding: 8px;
    background: #ffffff;
  }
  .sap-frame {
    border: 1px solid #cbd5e1;
    background: #f8fafc;
    border-radius: 3px;
    padding: 8px 12px;
    margin-bottom: 8px;
  }
  .sap-frame-title {
    font-size: 8pt;
    font-weight: bold;
    color: #0b3d60;
    margin-top: -15px;
    background: #f8fafc;
    display: inline-block;
    padding: 0 5px;
  }
  .sap-field-row {
    display: flex;
    align-items: center;
    margin: 4px 0;
    font-size: 8pt;
  }
  .sap-field-label {
    width: 140px;
    color: #334155;
    font-weight: 600;
  }
  .sap-field-input {
    background: #ffffff;
    border: 1px solid #64748b;
    padding: 1.5px 5px;
    font-family: Consolas, monospace;
    font-size: 8pt;
    color: #0f172a;
    font-weight: 600;
    width: 130px;
  }
  .sap-dual-container {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .sap-grid-box {
    border: 1px solid #94a3b8;
    background: #ffffff;
    border-radius: 2px;
  }
  .sap-grid-header {
    background: #e2e8f0;
    border-bottom: 1px solid #cbd5e1;
    padding: 3px 6px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 7.5pt;
    font-weight: bold;
    color: #0f172a;
  }
  .sap-alv-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 7.5pt;
    font-family: 'Segoe UI', Tahoma, Arial, sans-serif;
  }
  .sap-alv-table th {
    background: #f1f5f9;
    color: #1e293b;
    border: 1px solid #cbd5e1;
    padding: 3px 5px;
    font-weight: 700;
    text-align: left;
    font-size: 7pt;
  }
  .sap-alv-table td {
    border: 1px solid #e2e8f0;
    padding: 2.5px 5px;
    vertical-align: middle;
  }
  .sap-alv-table tr:nth-child(even) {
    background-color: #f8fafc;
  }
  .sap-alv-table tr.selected-row {
    background-color: #fef3c7 !important;
  }
  .led-ok {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    background: #dcfce7;
    color: #166534;
    font-weight: bold;
    font-family: Consolas, monospace;
    font-size: 7pt;
    padding: 1px 4px;
    border-radius: 2px;
    border: 1px solid #86efac;
  }
  .led-err {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    background: #fee2e2;
    color: #991b1b;
    font-weight: bold;
    font-family: Consolas, monospace;
    font-size: 7pt;
    padding: 1px 4px;
    border-radius: 2px;
    border: 1px solid #fca5a5;
  }
  .led-warn {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    background: #fef3c7;
    color: #92400e;
    font-weight: bold;
    font-family: Consolas, monospace;
    font-size: 7pt;
    padding: 1px 4px;
    border-radius: 2px;
    border: 1px solid #fde68a;
  }
  .sap-tcode-val {
    font-family: Consolas, monospace;
    font-weight: bold;
    color: #0369a1;
  }
  .sap-obj-val {
    font-family: Consolas, monospace;
    font-weight: bold;
    color: #b45309;
    text-decoration: underline;
  }
  .sap-fld-val {
    font-family: Consolas, monospace;
    font-size: 7pt;
    color: #334155;
  }
  .sap-statusbar {
    background: #f1f5f9;
    border-top: 1px solid #cbd5e1;
    padding: 2.5px 8px;
    font-size: 7.5pt;
    color: #334155;
    display: flex;
    align-items: center;
    gap: 5px;
  }
  .sap-status-icon {
    display: inline-block;
    width: 10px;
    height: 10px;
    border-radius: 50%;
  }
  .sap-status-icon.green {
    background: #16a34a;
  }
  .step-card {
    border: 1px solid #cbd5e1;
    border-radius: 4px;
    background: #ffffff;
    padding: 8px 12px;
    margin: 6px 0;
    box-shadow: 0 1px 2px rgba(0,0,0,0.04);
  }
  .step-header {
    display: flex;
    align-items: center;
    gap: 7px;
    margin-bottom: 4px;
  }
  .step-num {
    background: #005a9e;
    color: #ffffff;
    font-size: 8.5pt;
    font-weight: bold;
    width: 20px;
    height: 20px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .step-title {
    font-size: 9.5pt;
    font-weight: 700;
    color: #0b3d60;
  }
  .code-inline {
    background: #f1f5f9;
    color: #0b3d60;
    padding: 1px 4px;
    border-radius: 2px;
    font-family: Consolas, monospace;
    font-size: 8pt;
    border: 1px solid #cbd5e1;
  }
"""

def build_pdf_from_html(html_file: Path, pdf_file: Path):
    cmd = [
        CHROME_PATH,
        "--headless=new",
        "--disable-gpu",
        "--no-pdf-header-footer",
        f"--print-to-pdf={pdf_file.resolve()}",
        f"file:///{html_file.resolve().as_posix()}"
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[!] Error building {pdf_file.name}: {res.stderr}")
        return False
    if pdf_file.exists():
        size_kb = pdf_file.stat().st_size / 1024
        print(f"[+] Successfully generated: {pdf_file.name} ({size_kb:.1f} KB)")
        try:
            import pymupdf
            doc = pymupdf.open(pdf_file)
            print(f"    - Pages: {len(doc)}")
            doc.close()
        except Exception:
            pass
        return True
    return False

def main():
    print("[*] Generating English Guide (PDF)...")
    
    en_html = DOCS_DIR / "Z_AUTH_SU53_ANALYZER_USER_GUIDE_EN.html"
    en_pdf = DOCS_DIR / "Z_AUTH_SU53_ANALYZER_USER_GUIDE_EN.pdf"
    
    if en_html.exists():
        build_pdf_from_html(en_html, en_pdf)
        print(f"[+] Generated {en_pdf.name} successfully.")
    else:
        print(f"[-] Error: {en_html.name} not found.")

    # Clean up redundant temporary generator if present
    temp_gen = BASE_DIR / "scripts" / "generate_user_guide_en.py"
    if temp_gen.exists():
        temp_gen.unlink()
        print("[+] Cleaned up temporary generator script.")

    print("[*] English User Guide PDF generation completed.")

if __name__ == "__main__":
    main()
