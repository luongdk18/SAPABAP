#!/usr/bin/env python3
"""
Convert SAP Users Creation Excel list to flat normalized CSV format for SAP User Batch Upload.
Prepares input file for ABAP batch user creation program (via BAPI_USER_CREATE1).

Key transformations:
1. Column 1: 'Username' - extracted from prefix before '@' in Email (or raw value if not an email), uppercased.
2. Column 2: 'Initial Password' - generated cryptographically secure 12-character password compliant with SAP S/4HANA 2023.
3. Column 3: 'Full Name' - trimmed and normalized.
4. Column 4: 'Email' - trimmed.
5. Column 5: 'Phone No.' - standardized to unified format (+<CountryCode>)<Number> (e.g. (+84)985176887).
6. Column 6: 'Department' - typo and casing corrections.
7. Column 7: 'Function' - typo, casing, and title-case corrections.

Output columns:
1. Username
2. Initial Password
3. Full Name
4. Email
5. Phone No.
6. Department
7. Function

Output:
- <filename>_converted.csv (UTF-8 with BOM for SAP GUI import)

Usage:
    python scripts/convert_users_excel.py [input_excel_file]

Example:
    python scripts/convert_users_excel.py excel-working/Users_Create.xlsx
    -> Outputs: excel-working/Users_Create_converted.csv
"""

import os
import sys
import re
import csv
import string
import secrets
import openpyxl

# --- Safe Console Output on Windows ---
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

# Safe special characters for SAP S/4HANA passwords and CSV upload (no commas, quotes, or slashes)
SAFE_SPECIALS = "!@#$%*-_=+"

# Department spelling & casing corrections
DEPT_CORRECTIONS = {
    'operation': 'Operation',
    'administration': 'Administration',
}

# Function spelling & casing corrections
FUNC_CORRECTIONS = {
    'planing director': 'Planning Director',
    'civil engineer': 'Civil Engineer',
    'hse & materials controller': 'HSE & Materials Controller',
    'quality control (qa/qc) and document': 'Quality Control (QA/QC) & Document',
    'quality control ( qa/qc) and document': 'Quality Control (QA/QC) & Document',
    'qs': 'Quantity Surveyor',
}


# --- Helper Functions ---
def generate_sap_password(length=12, username=""):
    """
    Generates a secure 12-character initial password compliant with SAP S/4HANA 2023:
    - Starts with an uppercase letter (A-Z) to avoid legacy SAP issues with leading '?' or '!'.
    - Contains at least 2 uppercase letters, 2 lowercase letters, 2 digits, and 2 special characters.
    - Contains no 3 identical consecutive characters.
    - Does not contain the username or substring of the username.
    """
    while True:
        first_char = secrets.choice(string.ascii_uppercase)
        parts = [
            first_char,
            secrets.choice(string.ascii_uppercase),
            secrets.choice(string.ascii_lowercase),
            secrets.choice(string.ascii_lowercase),
            secrets.choice(string.digits),
            secrets.choice(string.digits),
            secrets.choice(SAFE_SPECIALS),
            secrets.choice(SAFE_SPECIALS),
        ]

        all_allowed = string.ascii_letters + string.digits + SAFE_SPECIALS
        for _ in range(length - len(parts)):
            parts.append(secrets.choice(all_allowed))

        sub = parts[1:]
        secrets.SystemRandom().shuffle(sub)
        pwd = first_char + "".join(sub)

        # Check no 3 identical consecutive characters
        if any(pwd[i] == pwd[i+1] == pwd[i+2] for i in range(len(pwd) - 2)):
            continue

        # Check does not contain username
        if username and len(username) >= 3 and username.upper() in pwd.upper():
            continue

        return pwd


def normalize_phone(raw_phone):
    """
    Normalizes phone numbers to standard format (+<CountryCode>)<Number> for SAP upload.
    Handles Vietnam (+84) and Kyrgyzstan (+996) prefixes.
    Ensures format (+<mã quốc gia>)<số điện thoại>, stripping leading zeros from subscriber number.
    """
    if raw_phone is None:
        return ""

    s = str(raw_phone).replace('\xa0', ' ').strip()
    if not s:
        return ""

    # Extract digits only
    digits = re.sub(r'[^\d]', '', s)
    if not digits:
        return ""

    country_code = ""
    sub_number = ""

    # Case 1: Starts with country code 996 (Kyrgyzstan)
    if digits.startswith('996'):
        country_code = "996"
        sub_number = digits[3:]
    # Case 2: Starts with country code 84 (Vietnam)
    elif digits.startswith('84'):
        country_code = "84"
        sub_number = digits[2:]
    # Case 3: 12 digits starting with 099 -> Kyrgyzstan operator 500
    elif len(digits) == 12 and digits.startswith('099'):
        country_code = "996"
        sub_number = digits[3:]
    # Case 4: Starts with national trunk prefix 0
    elif digits.startswith('0'):
        # 10 digits starting with 03, 05, 07, 08, 09 -> Vietnam (+84)
        if len(digits) == 10 and digits[1] in '35789':
            country_code = "84"
            sub_number = digits[1:]
        # Kyrgyzstan national format (9 or 10 digits)
        elif len(digits) == 10 and digits[1] in '2579':
            country_code = "996"
            sub_number = digits[1:]
        elif len(digits) == 9:
            country_code = "996"
            sub_number = digits
        else:
            country_code = "84"
            sub_number = digits[1:]
    # Case 5: 9 digits starting with 3, 5, 7, 8, 9 -> Vietnam mobile without leading 0
    elif len(digits) == 9 and digits[0] in '35789':
        country_code = "84"
        sub_number = digits
    else:
        # Fallback to Vietnam (+84)
        country_code = "84"
        sub_number = digits

    # Remove any leading zeros from subscriber number
    sub_number = sub_number.lstrip('0')

    return f"(+{country_code}){sub_number}"


def clean_department(raw_dept):
    """Standardizes department name casing and removes whitespace."""
    if not raw_dept:
        return ""
    d = str(raw_dept).strip()
    return DEPT_CORRECTIONS.get(d.lower(), d)


def clean_function(raw_func):
    """Standardizes job function / title spelling, casing, and removes whitespace."""
    if not raw_func or str(raw_func).strip().lower() == 'none':
        return ""
    f = str(raw_func).strip()
    # Normalize common internal whitespace issues like '( QA/QC)'
    f_clean = re.sub(r'\(\s+', '(', f)
    f_clean = re.sub(r'\s+\)', ')', f_clean)
    low = f_clean.lower()
    return FUNC_CORRECTIONS.get(low, FUNC_CORRECTIONS.get(f.lower(), f_clean))


def extract_username(raw_email, raw_name):
    """
    Extracts SAP Username:
    - If email has '@', takes part before '@', trimmed and uppercase.
    - If email has no '@', uses raw value trimmed and uppercase.
    - Fallback: derives initials from Full Name if email is empty.
    """
    if raw_email:
        s = str(raw_email).strip()
        if '@' in s:
            u = s.split('@')[0].strip().upper()
        else:
            u = s.strip().upper()
        if u:
            return u

    # Fallback to name if email completely missing
    if raw_name:
        parts = str(raw_name).strip().split()
        return "".join(p[0] for p in parts).upper()

    return "USER"


# --- Main Converter Function ---
def convert_users_excel(input_path):
    """
    Reads Users Creation Excel file and converts to normalized CSV format.
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

    # Locate 'User Asignment' / 'Users' sheet or fallback to active sheet
    target_sheet = None
    for name in wb_in.sheetnames:
        clean_name = name.strip().lower()
        if 'user' in clean_name and ('asign' in clean_name or 'assign' in clean_name):
            target_sheet = wb_in[name]
            break

    if target_sheet is None:
        for name in wb_in.sheetnames:
            if 'user' in name.strip().lower():
                target_sheet = wb_in[name]
                break

    if target_sheet is None:
        target_sheet = wb_in.active
        print(f"[INFO] Using active sheet '{target_sheet.title}'.")
    else:
        print(f"[INFO] Processing sheet: '{target_sheet.title}'")

    ws = target_sheet

    # --- Dynamic Column Detection ---
    col_name = None
    col_email = None
    col_phone = None
    col_dept = None
    col_func = None

    for col in range(1, ws.max_column + 1):
        val = str(ws.cell(1, col).value or '').strip().lower()
        if 'name' in val:
            col_name = col
        elif 'email' in val or 'mail' in val:
            col_email = col
        elif 'phone' in val or 'tel' in val or 'mobile' in val:
            col_phone = col
        elif 'dept' in val or 'department' in val or 'phòng' in val or 'ban' in val:
            col_dept = col
        elif 'func' in val or 'function' in val or 'title' in val or 'chức' in val or 'vị trí' in val:
            col_func = col

    # Fallback column positions (1: Name, 2: Email, 3: Phone, 4: Dept, 5: Func)
    col_name = col_name or 1
    col_email = col_email or 2
    col_phone = col_phone or 3
    col_dept = col_dept or 4
    col_func = col_func or 5

    print(f"[INFO] Detected Columns -> Name: Col {col_name}, Email: Col {col_email}, Phone: Col {col_phone}, Dept: Col {col_dept}, Func: Col {col_func}")

    # --- Data Processing & Normalization ---
    records = []
    skipped_empty = 0
    phone_formatted_count = 0
    missing_email_symbol_count = 0
    generated_usernames = set()

    for row in range(2, ws.max_row + 1):
        raw_name = ws.cell(row, col_name).value
        raw_email = ws.cell(row, col_email).value
        raw_phone = ws.cell(row, col_phone).value
        raw_dept = ws.cell(row, col_dept).value
        raw_func = ws.cell(row, col_func).value

        # Skip completely empty rows
        if not raw_name and not raw_email and not raw_dept:
            skipped_empty += 1
            continue

        full_name = str(raw_name or '').strip()
        email_str = str(raw_email or '').strip()

        # Track emails without '@'
        if email_str and '@' not in email_str:
            missing_email_symbol_count += 1

        # 1. Username
        username = extract_username(email_str, full_name)
        generated_usernames.add(username)

        # 2. Initial Password (12 characters, SAP S/4HANA 2023 compliant)
        password = generate_sap_password(length=12, username=username)

        # 3. Phone No. (E.164 formatted for SAP)
        phone_norm = normalize_phone(raw_phone)
        if phone_norm:
            phone_formatted_count += 1

        # 4. Department (cleaned)
        department = clean_department(raw_dept)

        # 5. Function (cleaned)
        function = clean_function(raw_func)

        records.append({
            'username': username,
            'password': password,
            'full_name': full_name,
            'email': email_str,
            'phone': phone_norm,
            'department': department,
            'function': function
        })

    # --- CSV Export (UTF-8 with BOM) ---
    headers = [
        "Username",
        "Initial Password",
        "Full Name",
        "Email",
        "Phone No.",
        "Department",
        "Function"
    ]

    try:
        with open(out_csv_path, 'w', newline='', encoding='utf-8-sig') as f:
            writer = csv.writer(f)
            writer.writerow(headers)
            for item in records:
                writer.writerow([
                    item['username'],
                    item['password'],
                    item['full_name'],
                    item['email'],
                    item['phone'],
                    item['department'],
                    item['function']
                ])
    except PermissionError:
        print(f"[ERROR] Permission denied when writing to '{out_csv_path}'. Please close the file in Excel and try again.")
        sys.exit(1)

    # --- Execution Summary ---
    print(f"\n--- Execution Summary ---")
    print(f"[OK] Input File       : {input_path}")
    print(f"[OK] Output CSV       : {out_csv_path} ({len(records)} data rows)")
    print(f"[OK] Total Users      : {len(records)} generated ({len(generated_usernames)} unique usernames)")
    print(f"[OK] Phones Formatted : {phone_formatted_count} normalized to SAP E.164 format")
    if missing_email_symbol_count > 0:
        print(f"[INFO] Non-@ Accounts : {missing_email_symbol_count} raw IDs directly converted to Username")
    if skipped_empty > 0:
        print(f"[INFO] Skipped Empty  : {skipped_empty} empty row(s)")


# --- CLI Entrypoint ---
if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ('-h', '--help'):
        print("Usage: python scripts/convert_users_excel.py [path_to_excel_file]")
        print("Example: python scripts/convert_users_excel.py excel-working/Users_Create.xlsx")
        sys.exit(0)

    target_file = None

    if len(sys.argv) > 1:
        target_file = sys.argv[1]
    else:
        # Default candidates lookup
        candidates = [
            os.path.join("excel-working", "Users_Create.xlsx"),
            os.path.join("excel-templates", "Template_Users_Create.xlsx"),
            "Users_Create.xlsx",
            "FICO_Users_Create.xlsx"
        ]
        for cand in candidates:
            if os.path.exists(cand):
                target_file = cand
                break

    if not target_file:
        print("[ERROR] No input file provided or found in default locations.")
        print("Usage: python scripts/convert_users_excel.py <path_to_excel_file>")
        print("Example: python scripts/convert_users_excel.py excel-working/Users_Create.xlsx")
        sys.exit(1)

    convert_users_excel(target_file)
