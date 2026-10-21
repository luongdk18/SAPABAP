import json
import csv
import os

# SAP S/4HANA Standard Organizational Levels extracted from USVART (Language: 'E')
# Sorted strictly by SAP standard primary key order: VARBL ascending (matching SORT T_STORG BY VARBL and table USVAR)
sap_org_levels = [
    ("Business Partner for Provider of Information", "$/ECRS/POIB"),
    ("Activity Area", "$/SCWM/AREA"),
    ("Authorized Drawer", "$/SCWM/ENTL"),
    ("Warehouse number / warehouse complex", "$/SCWM/LGNU"),
    ("Storage type", "$/SCWM/LGTY"),
    ("Chart of Depreciation", "$AFAPL"),
    ("Asset Class", "$ANLKL"),
    ("Applicant Group", "$APGRP"),
    ("Applicant Range", "$APTYP"),
    ("Work Center", "$ARBPL"),
    ("Aspect (application area)", "$ASPET"),
    ("Order Type", "$AUFART"),
    ("Bank Area", "$BKKRS"),
    ("Company Code", "$BUKRS"),
    ("Consolidation Unit", "$BUNIT"),
    ("Valuation area", "$BWKEY"),
    ("Aspect", "$CFASPET"),
    ("User Group", "$CLASS"),
    ("Condition Area", "$CONDAREA"),
    ("Consolidation Group", "$CONGR"),
    ("View", "$DIMEN"),
    ("MRP Controller", "$DISPO"),
    ("Purchasing Group", "$EKGRP"),
    ("Purchasing Organization", "$EKORG"),
    ("Operating Concern", "$ERKRS"),
    ("FM area", "$FIKRS"),
    ("Functional Area", "$FKBER"),
    ("Business Area", "$GSBER"),
    ("User Group", "$HIEID"),
    ("Maintenance planning plant", "$IWERK"),
    ("Credit Control Area", "$KKBER"),
    ("Costing Variant", "$KLVAR"),
    ("Account Type", "$KOART"),
    ("Controlling Area", "$KOKRS"),
    ("Cost Element", "$KSTAR"),
    ("Contact Type", "$KTAAR"),
    ("Chart of Accounts", "$KTOPL"),
    ("Cost Object Category", "$KTRAT"),
    ("Warehouse Number / Warehouse Complex", "$LGNUM"),
    ("Storage type", "$LGTYP"),
    ("Location", "$LTRM_LOCAT"),
    ("Personnel Area", "$PERSA"),
    ("Employee Group", "$PERSG"),
    ("Employee Subgroup", "$PERSK"),
    ("Plan Version", "$PLVAR"),
    ("Profit Centers", "$PRCTR"),
    ("Company", "$RCOMP"),
    ("Personnel officer for the job application", "$RESRF"),
    ("Ledger", "$RLDNR"),
    ("Payroll Administrator", "$SACHA"),
    ("Administrator for HR Master Data", "$SACHP"),
    ("Administrator for Time Recording", "$SACHZ"),
    ("Administrator Group", "$SBMOD"),
    ("Division", "$SPART"),
    ("Maintenance plant", "$SWERK"),
    ("Transportation Planning Point", "$TPLST"),
    ("Organizational Key", "$VDSK1"),
    ("Sales Office", "$VKBUR"),
    ("Sales Group", "$VKGRP"),
    ("Sales Organization", "$VKORG"),
    ("Shipping Point", "$VSTEL"),
    ("Distribution Channel", "$VTWEG"),
    ("Plant", "$WERKS"),
    ("Enterprise Organization", "$XCORG"),
    ("Planning and Execution Group", "$XEGRP"),
    ("Planning and Execution Organization", "$XEORG"),
    ("Purchasing Group", "$XPGRP"),
    ("Purchasing Organization", "$XPORG"),
    ("Sales Group", "$XSGRP"),
    ("Sales Office", "$XSOFF"),
    ("Sales Organization", "$XSORG"),
]

output_csv = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'excel-templates', 'Org_Levels.csv')

with open(output_csv, 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    writer.writerow(['Org Level Description', 'Org Level Variable'])
    for desc, var in sap_org_levels:
        writer.writerow([desc, var])

print(f"Successfully generated {len(sap_org_levels)} SAP Organizational Levels sorted by VARBL into: {output_csv}")
