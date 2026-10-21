#!/usr/bin/env python3
"""
Convert User Role Assignment Matrix Excel file to flat row format for SAP upload.
Filters user-role assignments where cell value is marked with an indicator ('Y', 'y', 'X', 'x').
Generates normalized flat CSV format: Username, Role.
Prepares input file for ABAP batch role assignment program Z_USER_02_ASSIGN_ROLE (via BAPI_USER_ACTGROUPS_ASSIGN / AGR_USERS).

Output columns:
1. Username
2. Role

Output:
- <filename>_converted.csv (UTF-8 with BOM for SAP GUI import)

Usage:
    python scripts/convert_user_02_assign.py [input_excel_file]

Example:
    python scripts/convert_user_02_assign.py excel-templates/Template_User_02_Assign.xlsx
    -> Outputs: excel-templates/Template_User_02_Assign_converted.csv
"""

import os
import sys
import csv
import openpyxl

# --- Safe Console Output on Windows ---
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')


def convert_user_02_assign(input_path):
    """
    Reads User Role Assignment matrix Excel file and converts to flat CSV format.
    Row 1: Role Names (Columns 2..N)
    Column 1: Username (Rows 2..N)
    Matrix Cells: 'Y', 'y', 'X', 'x' indicator flags
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

    # Sheet discovery: look for 'assign' or 'user' or active sheet
    target_sheet = None
    for name in wb_in.sheetnames:
        low_name = name.strip().lower()
        if 'assign' in low_name or 'gan' in low_name:
            target_sheet = wb_in[name]
            break

    if target_sheet is None:
        target_sheet = wb_in.active
        print(f"[INFO] Using active sheet '{target_sheet.title}'.")
    else:
        print(f"[INFO] Processing sheet: '{target_sheet.title}'")

    ws = target_sheet

    # --- Read Headers (Row 1: Role Names from Col 2..N) ---
    role_columns = []
    for col in range(2, ws.max_column + 1):
        role_val = str(ws.cell(1, col).value or '').strip().upper()
        if role_val:
            role_columns.append((col, role_val))

    print(f"[INFO] Found {len(role_columns)} Role column(s) in header.")

    records = []
    skipped_empty = 0
    unique_users = set()
    unique_roles = set()
    users_with_assignments = 0
    users_without_assignments = 0

    # --- Matrix Scanning (Rows 2..N) ---
    for row in range(2, ws.max_row + 1):
        username_val = str(ws.cell(row, 1).value or '').strip().upper()

        if not username_val:
            skipped_empty += 1
            continue

        assigned_for_user = 0
        for col_idx, role_name in role_columns:
            cell_val = str(ws.cell(row, col_idx).value or '').strip().upper()
            if cell_val in ('Y', 'X'):
                records.append({
                    'username': username_val,
                    'role': role_name
                })
                unique_roles.add(role_name)
                assigned_for_user += 1

        unique_users.add(username_val)
        if assigned_for_user > 0:
            users_with_assignments += 1
        else:
            users_without_assignments += 1

    # --- CSV Export (UTF-8 with BOM) ---
    try:
        with open(out_csv_path, 'w', newline='', encoding='utf-8-sig') as f:
            writer = csv.writer(f)
            writer.writerow(["Username", "Role"])
            for r in records:
                writer.writerow([r['username'], r['role']])
    except PermissionError:
        print(f"[ERROR] Permission denied when writing to '{out_csv_path}'. Please close the file in Excel and try again.")
        sys.exit(1)

    # --- Execution Summary ---
    print(f"\n--- Execution Summary ---")
    print(f"[OK] Input File       : {input_path}")
    print(f"[OK] Output CSV       : {out_csv_path} ({len(records)} assignment rows)")
    print(f"[OK] Total Users      : {len(unique_users)} ({users_with_assignments} with roles, {users_without_assignments} without)")
    print(f"[OK] Total Roles Used : {len(unique_roles)} distinct roles assigned")
    if skipped_empty > 0:
        print(f"[INFO] Empty Rows     : {skipped_empty} empty row(s) skipped")


# Compatibility alias
convert_users_assign_roles_excel = convert_user_02_assign


# --- CLI Entrypoint ---
if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ('-h', '--help'):
        print("Usage: python scripts/convert_user_02_assign.py [path_to_excel_file]")
        print("Example: python scripts/convert_user_02_assign.py excel-templates/Template_User_02_Assign.xlsx")
        sys.exit(0)

    target_file = None

    if len(sys.argv) > 1:
        target_file = sys.argv[1]
    else:
        # Default candidates lookup
        candidates = [
            os.path.join("excel-working", "User_02_Assign.xlsx"),
            os.path.join("excel-working", "User_Assign_Role.xlsx"),
            os.path.join("excel-templates", "Template_User_02_Assign.xlsx"),
            os.path.join("excel-templates", "Template_User_Assign_Role.xlsx"),
            "Template_User_02_Assign.xlsx",
            "User_02_Assign.xlsx",
            "User_Assign_Role.xlsx"
        ]
        for cand in candidates:
            if os.path.exists(cand):
                target_file = cand
                break

    if not target_file:
        print("[ERROR] No input file provided or found in default locations.")
        print("Usage: python scripts/convert_user_02_assign.py <path_to_excel_file>")
        print("Example: python scripts/convert_user_02_assign.py excel-templates/Template_User_02_Assign.xlsx")
        sys.exit(1)

    convert_user_02_assign(target_file)
