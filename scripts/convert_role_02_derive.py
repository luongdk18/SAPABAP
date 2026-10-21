#!/usr/bin/env python3
"""
Convert Derived Roles Matrix Excel file to flat row format for SAP upload.
Output format matches the CSV requirements for the SAP ABAP Derived Role Creation program.

Columns:
1. Master Role
2. Derived Role
3. Derived Role Description

Output:
- <filename>_converted.csv (UTF-8 with BOM for SAP GUI import)

Usage:
    python scripts/convert_role_02_derive.py [input_excel_file]

Example:
    python scripts/convert_role_02_derive.py excel-templates/Template_Role_02_Derived.xlsx
    -> Outputs: excel-templates/Template_Role_02_Derived_converted.csv
"""

import os
import sys
import csv
import openpyxl

# --- Safe Console Output on Windows ---
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')


def convert_role_02_derive(input_path):
    """
    Reads Derived Roles Excel file and converts to flat CSV format.
    Expects columns:
    - Master Role (contains 'master')
    - Derived Role (contains 'derive')
    - Derived Role Description (contains 'desc' or 'description')
    """
    # --- Path & File Resolution ---
    if not os.path.splitext(input_path)[1]:
        input_path = input_path + ".xlsx"

    if not os.path.exists(input_path):
        print(f"[ERROR] Input file not found: {input_path}")
        sys.exit(1)

    dir_name = os.path.dirname(input_path)
    base_name = os.path.basename(input_path)
    stem, _ = os.path.splitext(base_name)

    out_csv_name = f"{stem}_converted.csv"
    out_csv_path = os.path.join(dir_name, out_csv_name) if dir_name else out_csv_name

    # --- Load Workbook ---
    try:
        wb_in = openpyxl.load_workbook(input_path, data_only=True)
    except Exception as e:
        print(f"[ERROR] Could not read Excel workbook '{input_path}': {e}")
        sys.exit(1)

    # Locate target sheet: prefer sheet with 'derive' in name, else active sheet
    target_sheet = None
    for name in wb_in.sheetnames:
        if 'derive' in name.strip().lower():
            target_sheet = wb_in[name]
            break

    if target_sheet is None:
        target_sheet = wb_in.active
        print(f"[INFO] Using active sheet '{target_sheet.title}'.")
    else:
        print(f"[INFO] Processing sheet: '{target_sheet.title}'")

    ws = target_sheet

    # --- Detect Header Columns ---
    header_row = 1
    col_master = None
    col_derived = None
    col_desc = None

    for col in range(1, ws.max_column + 1):
        val = str(ws.cell(header_row, col).value or '').strip().lower()
        if 'master' in val and col_master is None:
            col_master = col
        elif 'derive' in val and ('desc' in val or 'description' in val) and col_desc is None:
            col_desc = col
        elif 'derive' in val and col_derived is None:
            col_derived = col

    # Fallback default positions: Col 1 = Master, Col 2 = Derived, Col 3 = Description
    if col_master is None:
        col_master = 1
    if col_derived is None:
        col_derived = 2
    if col_desc is None:
        col_desc = 3

    print(f"[INFO] Column mappings -> Master: Col {col_master}, Derived: Col {col_derived}, Desc: Col {col_desc}")

    records = []
    skipped_empty = 0
    unique_masters = set()
    unique_derived = set()

    # --- Read Data Rows ---
    for row in range(2, ws.max_row + 1):
        val_master = str(ws.cell(row, col_master).value or '').strip()
        val_derived = str(ws.cell(row, col_derived).value or '').strip()
        cell_desc_val = ws.cell(row, col_desc).value
        val_desc = str(cell_desc_val).strip() if cell_desc_val is not None else ''

        # Skip rows where both master and derived are blank
        if not val_master and not val_derived:
            skipped_empty += 1
            continue

        records.append({
            'master_role': val_master,
            'derived_role': val_derived,
            'derived_desc': val_desc
        })

        if val_master:
            unique_masters.add(val_master)
        if val_derived:
            unique_derived.add(val_derived)

    # --- CSV Export (UTF-8 with BOM) ---
    try:
        with open(out_csv_path, 'w', newline='', encoding='utf-8-sig') as f:
            writer = csv.writer(f)
            writer.writerow(["Master Role", "Derived Role", "Derived Role Description"])
            for r in records:
                writer.writerow([r['master_role'], r['derived_role'], r['derived_desc']])
    except PermissionError:
        print(f"[ERROR] Permission denied when writing to '{out_csv_path}'. Please close the file in Excel and try again.")
        sys.exit(1)

    # --- Execution Summary ---
    print(f"\n--- Execution Summary ---")
    print(f"[OK] Input File       : {input_path}")
    print(f"[OK] Output CSV       : {out_csv_path} ({len(records)} data rows)")
    print(f"[OK] Master Roles     : {len(unique_masters)} unique")
    print(f"[OK] Derived Roles    : {len(unique_derived)} unique")
    if skipped_empty > 0:
        print(f"[INFO] Empty Rows     : {skipped_empty} empty row(s) skipped")


# Compatibility alias
convert_role_derived_excel = convert_role_02_derive


# --- CLI Entrypoint ---
if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ('-h', '--help'):
        print("Usage: python scripts/convert_role_02_derive.py [path_to_excel_file]")
        print("Example: python scripts/convert_role_02_derive.py excel-templates/Template_Role_02_Derived.xlsx")
        sys.exit(0)

    target_file = None

    if len(sys.argv) > 1:
        target_file = sys.argv[1]
    else:
        # Default candidates lookup
        candidates = [
            os.path.join("excel-working", "FICO_Role_02_Derived.xlsx"),
            os.path.join("excel-working", "FICO_Roles_Derived.xlsx"),
            os.path.join("excel-templates", "Template_Role_02_Derived.xlsx"),
            os.path.join("excel-templates", "Template_Roles_Derived.xlsx"),
            "Template_Role_02_Derived.xlsx",
            "FICO_Role_02_Derived.xlsx",
            "FICO_Roles_Derived.xlsx",
            "Roles_Derived.xlsx"
        ]
        for cand in candidates:
            if os.path.exists(cand):
                target_file = cand
                break

    if not target_file:
        print("[ERROR] No input file provided or found in default locations.")
        print("Usage: python scripts/convert_role_02_derive.py <path_to_excel_file>")
        print("Example: python scripts/convert_role_02_derive.py excel-templates/Template_Role_02_Derived.xlsx")
        sys.exit(1)

    convert_role_02_derive(target_file)
