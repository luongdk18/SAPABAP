#!/usr/bin/env python3
"""
Convert SAP Authorization Matrix (User Assignment workbook) to flat CSV format
for ABAP batch role assignment program Z_USER_02_ASSIGN_ROLE.

Supports full multi-header Authorization Matrix layouts with banner/explanation rows
above the main table header row and extended user metadata columns preceding the
role assignment matrix.

Output columns:
1. Username
2. Role

Output:
- <parent_dir>/converted/<stem>_02_Assign_converted.csv (UTF-8 with BOM)

Usage:
    python scripts/convert_user_matrix_02_assign.py [input_excel_file] [--output-dir <dir>]
"""

import os
import sys
import re
import csv
import argparse
import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

from convert_user_matrix_01_create import (
    SUPPRESS_EMAIL_KEYWORDS,
    detect_header_row,
    find_target_sheet,
    normalize_header,
    resolve_default_matrix_file,
    resolve_output_path,
)

# Preserves exact user-info keyword filtering plus extended matrix metadata headers
USER_INFO_KEYWORDS = (
    'user id', 'userid', 'username', 'tài khoản', 'tai khoan', 'bname', 'mã nv', 'user',
    'full name', 'fullname', 'họ và tên', 'họ tên', 'họ & tên', 'name', 'tên',
    'email', 'e-mail', 'mail',
    'phone', 'điện thoại', 'dien thoai', 'tel', 'sđt', 'mobile',
    'department', 'dept', 'phòng ban', 'phong ban', 'bộ phận', 'bo phan',
    'function', 'chức danh', 'chuc danh', 'chức vụ', 'chuc vu', 'vị trí', 'vi tri', 'title',
    'password', 'pwd', 'pass', 'mật khẩu', 'mat khau',
    'note', 'notes', 'ghi chú', 'ghi chu', 'comment', 'comments',
    '#', 'employee id', 'emp id', 'location', 'organization', 'user type', 'tdi',
)


def classify_columns(ws, header_row):
    """Separates identity/metadata columns from SAP Role assignment columns."""
    col_user = None
    col_email = None
    col_name = None
    role_columns = []

    for col in range(1, ws.max_column + 1):
        raw_hdr = str(ws.cell(header_row, col).value or '').strip()
        if not raw_hdr:
            continue

        low = normalize_header(raw_hdr).lower()
        is_user_info = any(kw in low for kw in USER_INFO_KEYWORDS)

        if is_user_info:
            is_user_col = (
                low == 'user'
                or low.startswith('user ')
                or low.startswith('user(')
                or any(k in low for k in ('user id', 'userid', 'username', 'tài khoản', 'tai khoan', 'bname'))
            ) and 'type' not in low

            if is_user_col and col_user is None:
                col_user = col
            elif any(k in low for k in ('email', 'e-mail', 'mail')) and col_email is None:
                col_email = col
            elif (
                any(k in low for k in ('full name', 'fullname', 'họ và tên', 'họ tên', 'họ & tên'))
                or (('name' in low or 'họ' in low) and 'organization' not in low)
            ) and col_name is None:
                col_name = col
        else:
            role_columns.append((col, raw_hdr.upper()))

    if col_user is None and col_email is None and col_name is None:
        col_user = 1
        role_columns = [(c, r) for c, r in role_columns if c > 1]

    return col_user, col_email, col_name, role_columns


def derive_username(ws, row, col_email, col_user, col_name):
    """Derives SAP Username consistently with Z_USER_01_CREATE user creation rules."""
    if col_email and ws.cell(row, col_email).value:
        raw_email = str(ws.cell(row, col_email).value).strip()
        if '@' in raw_email:
            return raw_email.split('@')[0].strip().upper()
        if not any(kw in raw_email.lower() for kw in SUPPRESS_EMAIL_KEYWORDS):
            return raw_email.upper()

    if col_user and ws.cell(row, col_user).value:
        return str(ws.cell(row, col_user).value).strip().upper()

    if col_name and ws.cell(row, col_name).value:
        raw_name = str(ws.cell(row, col_name).value).strip()
        clean = re.sub(r'[^a-zA-Z0-9]', '', raw_name)
        return clean[:12].upper() if clean else f"USER_{row}"

    return None


def convert_user_matrix_02_assign(input_path, output_dir=None):
    """Reads an Authorization Matrix workbook and exports Z_USER_02_ASSIGN_ROLE flat CSV."""
    if not os.path.splitext(input_path)[1]:
        input_path = input_path + ".xlsx"

    if not os.path.exists(input_path):
        print(f"[ERROR] Input file not found: {input_path}")
        sys.exit(1)

    out_csv_path = resolve_output_path(input_path, output_dir, "_02_Assign")

    try:
        wb_in = openpyxl.load_workbook(input_path, data_only=True)
    except Exception as e:
        print(f"[ERROR] Could not read Excel workbook '{input_path}': {e}")
        sys.exit(1)

    ws = find_target_sheet(wb_in)
    header_row = detect_header_row(ws)
    col_user, col_email, col_name, role_columns = classify_columns(ws, header_row)

    print(f"[INFO] Processing sheet: '{ws.title}' (Header row: {header_row})")
    print(f"[INFO] Found {len(role_columns)} Role column(s) in header.")

    records = []
    skipped_empty = 0
    unique_users = set()
    unique_roles = set()
    users_with_assignments = 0
    users_without_assignments = 0

    for row in range(header_row + 1, ws.max_row + 1):
        username_val = derive_username(ws, row, col_email, col_user, col_name)
        if not username_val:
            skipped_empty += 1
            continue

        assigned_for_user = 0
        for col_idx, role_name in role_columns:
            cell_val = str(ws.cell(row, col_idx).value or '').strip().upper()
            if cell_val in ('Y', 'X', '1', 'YES', 'TRUE'):
                records.append({
                    'username': username_val,
                    'role': role_name,
                })
                unique_roles.add(role_name)
                assigned_for_user += 1

        unique_users.add(username_val)
        if assigned_for_user > 0:
            users_with_assignments += 1
        else:
            users_without_assignments += 1

    try:
        with open(out_csv_path, 'w', newline='', encoding='utf-8-sig') as f:
            writer = csv.writer(f)
            writer.writerow(["Username", "Role"])
            for r in records:
                writer.writerow([r['username'], r['role']])
    except PermissionError:
        print(f"[ERROR] Permission denied when writing to '{out_csv_path}'. Please close the file in Excel and try again.")
        sys.exit(1)

    print("\n--- Execution Summary ---")
    print(f"[OK] Input File       : {input_path}")
    print(f"[OK] Output CSV       : {out_csv_path} ({len(records)} assignment rows)")
    print(f"[OK] Total Users      : {len(unique_users)} ({users_with_assignments} with roles, {users_without_assignments} without)")
    print(f"[OK] Total Roles Used : {len(unique_roles)} distinct roles assigned")
    if skipped_empty > 0:
        print(f"[INFO] Empty Rows     : {skipped_empty} empty row(s) skipped")

    return out_csv_path, len(records)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert Authorization Matrix Excel to Z_USER_02_ASSIGN_ROLE CSV.")
    parser.add_argument("input_file", nargs="?", default=None, help="Path to Authorization Matrix Excel file")
    parser.add_argument("--output-dir", "-o", default=None, help="Custom output directory or .csv path")
    args = parser.parse_args()

    target_file = args.input_file or resolve_default_matrix_file()
    if not target_file:
        print("[ERROR] No Authorization Matrix Excel file provided or found in excel-working/.")
        sys.exit(1)

    convert_user_matrix_02_assign(target_file, args.output_dir)
