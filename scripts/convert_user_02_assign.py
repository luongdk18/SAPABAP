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
    -> Outputs: excel-templates/converted/Template_User_02_Assign_converted.csv
"""

import os
import sys
import re
import csv
import glob
import openpyxl

# --- Safe Console Output on Windows ---
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')


def convert_user_02_assign(input_path, output_dir=None):
    """
    Reads User Role Assignment matrix Excel file and converts to flat CSV format.
    Row 1: Role Names (Columns 2..N)
    Column 1: Username (Rows 2..N)
    Matrix Cells: 'Y', 'y', 'X', 'x' indicator flags
    Output is saved to <parent_dir>/converted/ by default.
    """
    # --- Path & File Resolution ---
    if not os.path.splitext(input_path)[1]:
        input_path = input_path + ".xlsx"

    if not os.path.exists(input_path):
        print(f"[ERROR] Input file not found: {input_path}")
        sys.exit(1)

    base_name = os.path.basename(input_path)
    stem, _ = os.path.splitext(base_name)

    if stem.endswith('_02_Assign') or stem.endswith('02_Assign') or stem.endswith('_Assign') or stem.endswith('Assign'):
        out_csv_name = f"{stem}_converted.csv"
    elif stem.endswith('_converted'):
        out_csv_name = f"{stem}.csv"
    else:
        out_csv_name = f"{stem}_02_Assign_converted.csv"

    if output_dir is None:
        dir_name = os.path.dirname(input_path) or "."
        output_dir = os.path.join(dir_name, "converted")

    if output_dir.endswith('.csv'):
        out_csv_path = output_dir
        if os.path.dirname(out_csv_path):
            os.makedirs(os.path.dirname(out_csv_path), exist_ok=True)
    else:
        os.makedirs(output_dir, exist_ok=True)
        out_csv_path = os.path.join(output_dir, out_csv_name)

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
        if 'assign' in low_name or 'asignment' in low_name or 'asign' in low_name or 'gan' in low_name or 'gán' in low_name or 'role' in low_name or 'vai trò' in low_name or 'user' in low_name:
            target_sheet = wb_in[name]
            break

    if target_sheet is None:
        target_sheet = wb_in.active
        print(f"[INFO] Using active sheet '{target_sheet.title}'.")
    else:
        print(f"[INFO] Processing sheet: '{target_sheet.title}'")

    ws = target_sheet

    # --- Read Headers: Classify User Info Columns vs Role Columns ---
    col_user = None
    col_email = None
    col_name = None
    role_columns = []

    user_info_kws = [
        'user id', 'userid', 'username', 'tài khoản', 'tai khoan', 'bname', 'mã nv', 'user',
        'full name', 'fullname', 'họ và tên', 'họ tên', 'họ & tên', 'name', 'tên',
        'email', 'e-mail', 'mail',
        'phone', 'điện thoại', 'dien thoai', 'tel', 'sđt', 'mobile',
        'department', 'dept', 'phòng ban', 'phong ban', 'bộ phận', 'bo phan',
        'function', 'chức danh', 'chuc danh', 'chức vụ', 'chuc vu', 'vị trí', 'vi tri', 'title',
        'password', 'pwd', 'pass', 'mật khẩu', 'mat khau',
        'note', 'notes', 'ghi chú', 'ghi chu', 'comment', 'comments'
    ]

    for col in range(1, ws.max_column + 1):
        v = str(ws.cell(1, col).value or '').strip()
        if not v:
            continue
        low = v.lower()
        is_u = any(kw in low for kw in user_info_kws)
        if is_u:
            if any(k in low for k in ['user id', 'userid', 'username', 'tài khoản', 'tai khoan', 'bname']) and col_user is None:
                col_user = col
            elif any(k in low for k in ['email', 'mail']) and col_email is None:
                col_email = col
            elif any(k in low for k in ['name', 'họ']) and col_name is None:
                col_name = col
        else:
            role_columns.append((col, v.upper()))

    # Fallback if no specific column identified: Column 1 is user, Col 2..N are roles
    if col_user is None and col_email is None and col_name is None:
        col_user = 1
        role_columns = [(c, r) for c, r in role_columns if c > 1]

    print(f"[INFO] Found {len(role_columns)} Role column(s) in header.")

    records = []
    skipped_empty = 0
    unique_users = set()
    unique_roles = set()
    users_with_assignments = 0
    users_without_assignments = 0

    # --- Matrix Scanning (Rows 2..N) ---
    for row in range(2, ws.max_row + 1):
        username_val = None
        if col_user and ws.cell(row, col_user).value:
            username_val = str(ws.cell(row, col_user).value).strip().upper()
        elif col_email and ws.cell(row, col_email).value:
            raw_email = str(ws.cell(row, col_email).value).strip()
            if '@' in raw_email:
                username_val = raw_email.split('@')[0].strip().upper()
            elif any(kw in raw_email.lower() for kw in ('không gán mail', 'khong gan mail', 'tránh spam', 'trainh spam', 'tranh spam')):
                # Directive cell: fall back to col_name
                username_val = None
            else:
                username_val = raw_email.strip().upper()
        if not username_val and col_name and ws.cell(row, col_name).value:
            raw_name = str(ws.cell(row, col_name).value).strip()
            clean = re.sub(r'[^a-zA-Z0-9]', '', raw_name)
            username_val = clean[:12].upper() if clean else f"USER_{row}"

        if not username_val:
            skipped_empty += 1
            continue

        assigned_for_user = 0
        for col_idx, role_name in role_columns:
            cell_val = str(ws.cell(row, col_idx).value or '').strip().upper()
            if cell_val in ('Y', 'X', '1', 'YES', 'TRUE'):
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

    return out_csv_path, len(records)


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
            os.path.join("excel-working", "Assign_User.xlsx"),
            os.path.join("excel-working", "User_02_Assign.xlsx"),
            os.path.join("excel-working", "User_Assign_Role.xlsx"),
            os.path.join("excel-templates", "Assign_User.xlsx"),
            os.path.join("excel-templates", "Template_User_02_Assign.xlsx"),
            os.path.join("excel-templates", "Template_User_Assign_Role.xlsx"),
            "Assign_User.xlsx",
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
