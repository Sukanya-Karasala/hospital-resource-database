-- =====================================================================
-- Hospital Resource Management Database — SQLite schema
-- 19 tables: master data, inventory, operational and junction tables.
-- Normalised to 3NF; referential integrity enforced with foreign keys.
-- Run with:  PRAGMA foreign_keys = ON;
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ── Master / catalogue tables ────────────────────────────────────────

CREATE TABLE Doctors (
    doctor_id          INTEGER PRIMARY KEY,
    doctor_code        TEXT    NOT NULL UNIQUE,          -- e.g. D-00001
    f_name             TEXT    NOT NULL,
    l_name             TEXT    NOT NULL,
    gender             TEXT,
    country_code       TEXT,
    phone_number       TEXT,
    official_email_id  TEXT    NOT NULL UNIQUE
);

CREATE TABLE Nurses (
    nurse_id           INTEGER PRIMARY KEY,
    nurse_code         TEXT    NOT NULL UNIQUE,          -- e.g. N-00001
    f_name             TEXT    NOT NULL,
    l_name             TEXT    NOT NULL,
    gender             TEXT,
    country_code       TEXT,
    phone_number       TEXT,
    official_email_id  TEXT    NOT NULL UNIQUE
);

CREATE TABLE Departments (
    department_id        INTEGER PRIMARY KEY,
    department_code      TEXT NOT NULL UNIQUE,           -- e.g. DEPT-001
    department_name      TEXT NOT NULL,
    specialisation       TEXT NOT NULL,
    department_email_id  TEXT UNIQUE,
    UNIQUE (department_name, specialisation)
);

CREATE TABLE Patients (
    patient_id    INTEGER PRIMARY KEY,
    patient_code  TEXT NOT NULL UNIQUE,
    f_name        TEXT NOT NULL,
    l_name        TEXT NOT NULL,
    gender        TEXT,
    country_code  TEXT,
    phone_number  TEXT,
    email_id      TEXT
);

CREATE TABLE MedicalProductCatalog (
    product_id    INTEGER PRIMARY KEY,
    product_code  TEXT NOT NULL UNIQUE,                  -- FDA NDC code
    product_name  TEXT NOT NULL,
    manufacturer  TEXT NOT NULL,
    description   TEXT
);

CREATE TABLE MedicalEquipmentCatalog (
    equipment_id    INTEGER PRIMARY KEY,
    equipment_code  TEXT NOT NULL UNIQUE,
    equipment_name  TEXT NOT NULL,
    description     TEXT
);

CREATE TABLE OperationRooms (
    room_id        INTEGER PRIMARY KEY,
    room_code      TEXT NOT NULL UNIQUE,
    room_location  TEXT NOT NULL,
    floor          TEXT,
    description    TEXT
);

-- ── Operational tables ──────────────────────────────────────────────

CREATE TABLE Appointments (
    appointment_id    INTEGER PRIMARY KEY,
    patient_id        INTEGER NOT NULL REFERENCES Patients(patient_id),
    doctor_id         INTEGER NOT NULL REFERENCES Doctors(doctor_id),
    appointment_time  TEXT    NOT NULL,                  -- ISO datetime
    status            TEXT    NOT NULL
                      CHECK (status IN ('Scheduled','Completed','Cancelled'))
);

CREATE TABLE OperationScheduling (
    operation_id    INTEGER PRIMARY KEY,
    operation_code  TEXT    NOT NULL UNIQUE,
    operation_date  TEXT    NOT NULL,                    -- ISO date
    start_time      TEXT    NOT NULL,                    -- ISO datetime
    end_time        TEXT    NOT NULL,
    room_id         INTEGER NOT NULL REFERENCES OperationRooms(room_id),
    department_id   INTEGER NOT NULL REFERENCES Departments(department_id),
    appointment_id  INTEGER REFERENCES Appointments(appointment_id),  -- NULL for emergencies
    status          TEXT    NOT NULL
                    CHECK (status IN ('Scheduled','In Progress','Completed','Cancelled','Postponed')),
    CHECK (end_time > start_time)
);

CREATE TABLE DoctorShifts (
    shift_id    INTEGER PRIMARY KEY,
    doctor_id   INTEGER NOT NULL REFERENCES Doctors(doctor_id),
    shift_date  TEXT    NOT NULL,
    start_time  TEXT    NOT NULL,
    end_time    TEXT    NOT NULL,
    CHECK (end_time > start_time)
);

CREATE TABLE NurseShifts (
    shift_id    INTEGER PRIMARY KEY,
    nurse_id    INTEGER NOT NULL REFERENCES Nurses(nurse_id),
    shift_date  TEXT    NOT NULL,
    start_time  TEXT    NOT NULL,
    end_time    TEXT    NOT NULL,
    CHECK (end_time > start_time)
);

-- ── Many-to-many junction tables ────────────────────────────────────

CREATE TABLE DoctorDepartment (
    doctor_id      INTEGER NOT NULL REFERENCES Doctors(doctor_id),
    department_id  INTEGER NOT NULL REFERENCES Departments(department_id),
    role           TEXT    NOT NULL,
    PRIMARY KEY (doctor_id, department_id)
);

CREATE TABLE NurseDepartment (
    nurse_id       INTEGER NOT NULL REFERENCES Nurses(nurse_id),
    department_id  INTEGER NOT NULL REFERENCES Departments(department_id),
    role           TEXT    NOT NULL,
    PRIMARY KEY (nurse_id, department_id)
);

CREATE TABLE DoctorScheduledOperations (
    operation_id  INTEGER NOT NULL REFERENCES OperationScheduling(operation_id),
    doctor_id     INTEGER NOT NULL REFERENCES Doctors(doctor_id),
    doctor_role   TEXT    NOT NULL,
    PRIMARY KEY (operation_id, doctor_id)
);

CREATE TABLE NurseScheduledOperations (
    operation_id  INTEGER NOT NULL REFERENCES OperationScheduling(operation_id),
    nurse_id      INTEGER NOT NULL REFERENCES Nurses(nurse_id),
    nurse_role    TEXT    NOT NULL,
    PRIMARY KEY (operation_id, nurse_id)
);

-- ── Inventory tables ────────────────────────────────────────────────

CREATE TABLE ProductInventory (
    inventory_id  INTEGER PRIMARY KEY,
    product_id    INTEGER NOT NULL REFERENCES MedicalProductCatalog(product_id),
    lot_number    TEXT    NOT NULL,
    expiry_date   TEXT    NOT NULL,
    quantity      INTEGER NOT NULL CHECK (quantity >= 0),
    UNIQUE (product_id, lot_number)
);

CREATE TABLE EquipmentInventory (
    equipment_inv_id  INTEGER PRIMARY KEY,
    equipment_id      INTEGER NOT NULL REFERENCES MedicalEquipmentCatalog(equipment_id),
    quantity          INTEGER NOT NULL CHECK (quantity >= 0)
);

-- ── Booking tables ──────────────────────────────────────────────────

CREATE TABLE OperationProductBooking (
    booking_id          INTEGER PRIMARY KEY,
    operation_id        INTEGER NOT NULL REFERENCES OperationScheduling(operation_id),
    inventory_id        INTEGER NOT NULL REFERENCES ProductInventory(inventory_id),
    quantity_reserved   INTEGER NOT NULL CHECK (quantity_reserved > 0),
    quantity_allocated  INTEGER NOT NULL DEFAULT 0
                        CHECK (quantity_allocated BETWEEN 0 AND quantity_reserved)
);

CREATE TABLE OperationEquipmentBooking (
    booking_id          INTEGER PRIMARY KEY,
    operation_id        INTEGER NOT NULL REFERENCES OperationScheduling(operation_id),
    equipment_inv_id    INTEGER NOT NULL REFERENCES EquipmentInventory(equipment_inv_id),
    quantity_reserved   INTEGER NOT NULL CHECK (quantity_reserved > 0),
    quantity_allocated  INTEGER NOT NULL DEFAULT 0
                        CHECK (quantity_allocated BETWEEN 0 AND quantity_reserved)
);

-- ── Indexes for common joins and filters ────────────────────────────

CREATE INDEX idx_ops_date        ON OperationScheduling(operation_date);
CREATE INDEX idx_ops_status      ON OperationScheduling(status);
CREATE INDEX idx_dshift_doctor   ON DoctorShifts(doctor_id, shift_date);
CREATE INDEX idx_nshift_nurse    ON NurseShifts(nurse_id, shift_date);
CREATE INDEX idx_opb_operation   ON OperationProductBooking(operation_id);
CREATE INDEX idx_oeb_operation   ON OperationEquipmentBooking(operation_id);
