#!/usr/bin/env python3
"""
Convert Composite Roles Matrix Excel file to flat row format for SAP upload.
Filters Derived Roles where cell value is marked with an indicator ('Y', 'y', 'X', 'x').
If a composite role (column) has no indicator values, generates 1 row with Derived Role = 'N/A'.

Output columns:
1. Composite Role Name
2. Composite Role Description
3. Derived Role

Output:
- <filename>_converted.csv (UTF-8 with BOM for SAP GUI import)

Usage:
    python scripts/convert_role_04_composite.py [input_excel_file]

Example:
    python scripts/convert_role_04_composite.py excel-templates/Template_Role_04_Composite.xlsx
    -> Outputs: excel-templates/Template_Role_04_Composite_converted.csv
"""

import os
import sys
import csv
import openpyxl

# --- Safe Console Output on Windows ---
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')


def convert_role_04_composite(input_path):
    """
    Reads Composite Role matrix Excel file and converts to flat CSV format.
    Row 1: Composite Role Description (preserves exact spacing)
    Row 2: Composite Role Name
    Row 3+: Derived Roles (Column 1) and indicator flags ('Y', 'y', 'X', 'x') (Columns 2..N)
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

    # Locate target sheet: prefer sheet with 'composite' in title, else active sheet
    target_sheet = None
    for name in wb_in.sheetnames:
        if 'composite' in name.strip().lower():
            target_sheet = wb_in[name]
            break

    if target_sheet is None:
        target_sheet = wb_in.active
        print(f"[INFO] Using active sheet '{target_sheet.title}'.")
    else:
        print(f"[INFO] Processing sheet: '{target_sheet.title}'")

    ws = target_sheet

    roles_flat = []
    roles_with_derived = 0
    roles_without_derived = 0
    no_flag_role_names = []

    # --- Matrix Scanning & Flag Filtering ('Y', 'y', 'X', 'x') ---
    # Iterate over columns (each column starting from col 2 is a Composite Role)
    for col in range(2, ws.max_column + 1):
        cell_desc_val = ws.cell(1, col).value
        role_desc = str(cell_desc_val) if cell_desc_val is not None else ''
        role_name = str(ws.cell(2, col).value or '').strip()

        if not role_name:
            continue

        found_flag = False
        for row in range(3, ws.max_row + 1):
            derived_role = str(ws.cell(row, 1).value or '').strip()
            val = str(ws.cell(row, col).value or '').strip().upper()

            # Filter criteria: accepts Y, y, X, x
            if val in ('Y', 'X') and derived_role:
                roles_flat.append({
                    'role_name': role_name,
                    'role_desc': role_desc,
                    'derived_role': derived_role
                })
                found_flag = True

        # If no indicator ('Y'/'X') was found for this role column, create 1 fallback row with Derived Role = 'N/A'
        if not found_flag:
            roles_flat.append({
                'role_name': role_name,
                'role_desc': role_desc,
                'derived_role': 'N/A'
            })
            roles_without_derived += 1
            no_flag_role_names.append(role_name)
        else:
            roles_with_derived += 1

    # --- CSV Export (UTF-8 with BOM) ---
    try:
        with open(out_csv_path, 'w', newline='', encoding='utf-8-sig') as f:
            writer = csv.writer(f)
            writer.writerow(["Composite Role Name", "Composite Role Description", "Derived Role"])
            for item in roles_flat:
                writer.writerow([item['role_name'], item['role_desc'], item['derived_role']])
    except PermissionError:
        print(f"[ERROR] Permission denied when writing to '{out_csv_path}'. Please close the file in Excel and try again.")
        sys.exit(1)

    # --- Execution Summary ---
    total_roles = roles_with_derived + roles_without_derived
    print(f"\n--- Execution Summary ---")
    print(f"[OK] Input File       : {input_path}")
    print(f"[OK] Total Roles      : {total_roles} ({roles_with_derived} with Derived Roles, {roles_without_derived} set to 'N/A')")
    if no_flag_role_names:
        print(f"[INFO] Empty Roles    : {', '.join(no_flag_role_names)} -> assigned 'N/A'")
    print(f"[OK] Output CSV       : {out_csv_path} ({len(roles_flat)} data rows)")


# Compatibility alias
convert_role_composite_excel = convert_role_04_composite


# --- CLI Entrypoint ---
if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ('-h', '--help'):
        print("Usage: python scripts/convert_role_04_composite.py [path_to_excel_file]")
        print("Example: python scripts/convert_role_04_composite.py excel-templates/Template_Role_04_Composite.xlsx")
        sys.exit(0)

    target_file = None

    if len(sys.argv) > 1:
        target_file = sys.argv[1]
    else:
        # Default candidates lookup
        candidates = [
            os.path.join("excel-working", "FICO_Role_04_Composite.xlsx"),
            os.path.join("excel-working", "FICO_Roles_Composite.xlsx"),
            os.path.join("excel-templates", "Template_Role_04_Composite.xlsx"),
            os.path.join("excel-templates", "Template_Roles_Composite.xlsx"),
            "Template_Role_04_Composite.xlsx",
            "FICO_Role_04_Composite.xlsx",
            "FICO_Roles_Composite.xlsx",
            "Roles_Composite.xlsx"
        ]
        for cand in candidates:
            if os.path.exists(cand):
                target_file = cand
                break

    if not target_file:
        print("[ERROR] No input file provided or found in default locations.")
        print("Usage: python scripts/convert_role_04_composite.py <path_to_excel_file>")
        print("Example: python scripts/convert_role_04_composite.py excel-templates/Template_Role_04_Composite.xlsx")
        sys.exit(1)

    convert_role_04_composite(target_file)
