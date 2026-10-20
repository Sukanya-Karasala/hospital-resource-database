"""
Build the hospital resource database in SQLite and run every business query.

    python build_database.py

Steps
  1. Create hospital.db from sql/01_schema.sql
  2. Load the 19 CSV files in data/ (in foreign-key-safe order)
  3. Run integrity checks (foreign keys, scheduling clashes)
  4. Run each query in sql/02_business_queries.sql and save the
     result to outputs/<query_name>.csv
"""

import re
import sqlite3
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).parent
DB_PATH = ROOT / "hospital.db"
DATA = ROOT / "data"
OUT = ROOT / "outputs"

# CSV file -> table, in parent-before-child order
LOAD_ORDER = [
    ("doctors.csv", "Doctors"),
    ("nurses.csv", "Nurses"),
    ("departments.csv", "Departments"),
    ("patients.csv", "Patients"),
    ("medicalproductcatalog.csv", "MedicalProductCatalog"),
    ("medicalequipmentcatalog.csv", "MedicalEquipmentCatalog"),
    ("operationrooms.csv", "OperationRooms"),
    ("appointments.csv", "Appointments"),
    ("operationscheduling.csv", "OperationScheduling"),
    ("doctorshifts.csv", "DoctorShifts"),
    ("nurseshifts.csv", "NurseShifts"),
    ("doctordepartment.csv", "DoctorDepartment"),
    ("nursedepartment.csv", "NurseDepartment"),
    ("doctorscheduledoperations.csv", "DoctorScheduledOperations"),
    ("nursescheduledoperations.csv", "NurseScheduledOperations"),
    ("productinventory.csv", "ProductInventory"),
    ("equipmentinventory.csv", "EquipmentInventory"),
    ("operationproductbooking.csv", "OperationProductBooking"),
    ("operationequipmentbooking.csv", "OperationEquipmentBooking"),
]


def load_csv(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path, dtype=str, keep_default_na=False, na_values=[""])
    df = df.loc[:, ~df.columns.str.startswith("Unnamed")]  # drop exported index column
    for col in ("start_time", "end_time", "appointment_time"):
        if col in df:
            df[col] = df[col].str.replace("T", " ", regex=False)  # ISO 'YYYY-MM-DD HH:MM:SS'
    return df.drop_duplicates()


def build() -> sqlite3.Connection:
    DB_PATH.unlink(missing_ok=True)
    con = sqlite3.connect(DB_PATH)
    con.executescript((ROOT / "sql" / "01_schema.sql").read_text())
    con.execute("PRAGMA foreign_keys = ON;")

    for csv_name, table in LOAD_ORDER:
        df = load_csv(DATA / csv_name)
        cols = ", ".join(df.columns)
        marks = ", ".join("?" * len(df.columns))
        rows = [tuple(None if pd.isna(v) else v for v in r) for r in df.itertuples(index=False)]
        con.executemany(f"INSERT INTO {table} ({cols}) VALUES ({marks})", rows)
        print(f"  loaded {len(df):>5,} rows -> {table}")
    con.commit()
    return con


def integrity_checks(con: sqlite3.Connection) -> None:
    fk = con.execute("PRAGMA foreign_key_check;").fetchall()
    print(f"  foreign-key violations: {len(fk)}")

    room_clash = con.execute("""
        SELECT COUNT(*) FROM OperationScheduling a
        JOIN OperationScheduling b
          ON a.room_id = b.room_id AND a.operation_id < b.operation_id
         AND a.start_time < b.end_time AND b.start_time < a.end_time
        WHERE a.status NOT IN ('Cancelled','Postponed')
          AND b.status NOT IN ('Cancelled','Postponed')
    """).fetchone()[0]
    print(f"  operating-room double bookings: {room_clash}")

    doc_clash = con.execute("""
        SELECT COUNT(*) FROM DoctorScheduledOperations x
        JOIN DoctorScheduledOperations y
          ON x.doctor_id = y.doctor_id AND x.operation_id < y.operation_id
        JOIN OperationScheduling a ON a.operation_id = x.operation_id
        JOIN OperationScheduling b ON b.operation_id = y.operation_id
        WHERE a.start_time < b.end_time AND b.start_time < a.end_time
          AND a.status NOT IN ('Cancelled','Postponed')
          AND b.status NOT IN ('Cancelled','Postponed')
    """).fetchone()[0]
    print(f"  doctor double bookings: {doc_clash}")


def run_queries(con: sqlite3.Connection) -> None:
    OUT.mkdir(exist_ok=True)
    text = (ROOT / "sql" / "02_business_queries.sql").read_text()
    # each query starts with a line like:  -- name: q01_appointments_by_doctor
    blocks = re.split(r"^-- name: (\S+)\s*$", text, flags=re.M)[1:]
    for name, sql in zip(blocks[0::2], blocks[1::2]):
        df = pd.read_sql_query(sql.strip().rstrip(";"), con)
        df.to_csv(OUT / f"{name}.csv", index=False)
        print(f"  {name:<40} {len(df):>5} rows")


if __name__ == "__main__":
    print("Building database...")
    con = build()
    print("Integrity checks...")
    integrity_checks(con)
    print("Running business queries...")
    run_queries(con)
    con.close()
    print(f"Done -> {DB_PATH.name} and outputs/")
