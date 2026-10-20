-- ============================================================
-- QUERY 1: Appointment Volume and Status Breakdown per Doctor
-- Business Question: Which doctors have the highest patient
--   volume, and what proportion of their appointments are
--   completed, cancelled, or still scheduled?
-- Insight: Identifies high-demand clinicians and flags
--   potential cancellation patterns for HR intervention.
-- ============================================================

SELECT
    d.doctor_code,
    CONCAT(d.f_name, ' ', d.l_name)                              AS doctor_name,
    COUNT(a.appointment_id)                                       AS total_appointments,
    SUM(a.status = 'Completed')                                   AS completed,
    SUM(a.status = 'Cancelled')                                   AS cancelled,
    SUM(a.status = 'Scheduled')                                   AS scheduled,
    ROUND(
        100.0 * SUM(a.status = 'Completed') / COUNT(a.appointment_id), 1
    )                                                             AS completion_rate_pct
FROM Appointments  a
JOIN Doctors       d ON d.doctor_id = a.doctor_id
GROUP BY d.doctor_id, d.doctor_code, d.f_name, d.l_name
ORDER BY total_appointments DESC;


-- ============================================================
-- QUERY 2: Department-Level Operation Load Analysis
-- Business Question: How many operations has each department
--   handled, and what are their completion/cancellation rates?
-- Insight: Drives resource allocation; highlights departments
--   with high postponement/cancellation rates for review.
-- ============================================================

SELECT
    dep.department_code,
    dep.department_name,
    dep.specialisation,
    COUNT(os.operation_id)                                         AS total_operations,
    SUM(os.status = 'Completed')                                   AS completed,
    SUM(os.status = 'Cancelled')                                   AS cancelled,
    SUM(os.status = 'Postponed')                                   AS postponed,
    SUM(os.status = 'Scheduled')                                   AS scheduled,
    SUM(os.status = 'In Progress')                                 AS in_progress,
    ROUND(
        100.0 * SUM(os.status = 'Completed') / COUNT(os.operation_id), 1
    )                                                              AS completion_rate_pct
FROM OperationScheduling os
JOIN Departments          dep ON dep.department_id = os.department_id
GROUP BY dep.department_id, dep.department_code, dep.department_name, dep.specialisation
ORDER BY total_operations DESC;




-- ============================================================
-- QUERY 3: Doctor Workload – Shift Hours and Operation Count
-- Business Question: How many hours have doctors worked, and
--   how many operations have they participated in?
-- Insight: Detects overworked or underutilised clinicians to
--   inform fair rota planning.
-- ============================================================

-- FIX: aggregate shifts and operations separately; joining both to
-- Doctors at once multiplies every shift by every operation (fan-out).
SELECT
    d.doctor_code,
    CONCAT(d.f_name, ' ', d.l_name)                               AS doctor_name,
    COALESCE(s.total_shifts, 0)                                    AS total_shifts,
    ROUND(COALESCE(s.minutes, 0) / 60.0, 1)                        AS total_shift_hours,
    COALESCE(o.operations, 0)                                      AS operations_participated,
    ROUND(s.minutes / 60.0 / NULLIF(o.operations, 0), 1)           AS shift_hours_per_operation
FROM Doctors d
LEFT JOIN (
    SELECT doctor_id, COUNT(*) AS total_shifts,
           SUM(TIMESTAMPDIFF(MINUTE, start_time, end_time)) AS minutes
    FROM DoctorShifts GROUP BY doctor_id
) s ON s.doctor_id = d.doctor_id
LEFT JOIN (
    SELECT doctor_id, COUNT(DISTINCT operation_id) AS operations
    FROM DoctorScheduledOperations GROUP BY doctor_id
) o ON o.doctor_id = d.doctor_id
ORDER BY total_shift_hours DESC;


-- ============================================================
-- QUERY 4: Nurse Workload – Shifts vs Operations
-- Business Question: How does nurse shift coverage compare to
--   their surgical operation involvement?
-- Insight: Reveals nurses who may be underassigned to
--   operations relative to hours worked (or vice versa).
-- ============================================================

-- FIX: same fan-out correction as Query 3.
SELECT
    n.nurse_code,
    CONCAT(n.f_name, ' ', n.l_name)                               AS nurse_name,
    COALESCE(s.total_shifts, 0)                                    AS total_shifts,
    ROUND(COALESCE(s.minutes, 0) / 60.0, 1)                        AS total_shift_hours,
    COALESCE(o.operations, 0)                                      AS operations_assisted
FROM Nurses n
LEFT JOIN (
    SELECT nurse_id, COUNT(*) AS total_shifts,
           SUM(TIMESTAMPDIFF(MINUTE, start_time, end_time)) AS minutes
    FROM NurseShifts GROUP BY nurse_id
) s ON s.nurse_id = n.nurse_id
LEFT JOIN (
    SELECT nurse_id, COUNT(DISTINCT operation_id) AS operations
    FROM NurseScheduledOperations GROUP BY nurse_id
) o ON o.nurse_id = n.nurse_id
ORDER BY total_shift_hours DESC;


-- ============================================================
-- QUERY 5: Monthly Operation Trend
-- Business Question: How does operation throughput vary
--   month-over-month? Are there seasonal demand peaks?
-- Insight: Guides capacity planning and demand forecasting
--   for staffing and resource procurement.
-- ============================================================

SELECT
    DATE_FORMAT(os.operation_date, '%Y-%m')                        AS op_month,
    COUNT(os.operation_id)                                         AS total_operations,
    SUM(os.status = 'Completed')                                   AS completed,
    SUM(os.status = 'Cancelled')                                   AS cancelled,
    SUM(os.status = 'Postponed')                                   AS postponed,
    SUM(os.status = 'Scheduled')                                   AS scheduled,
    ROUND(
        100.0 * SUM(os.status = 'Completed') / COUNT(os.operation_id), 1
    )                                                              AS monthly_completion_pct
FROM OperationScheduling os
GROUP BY DATE_FORMAT(os.operation_date, '%Y-%m')
ORDER BY DATE_FORMAT(os.operation_date, '%Y-%m');





-- ============================================================
-- QUERY 6: Inventory Expiry Risk Assessment (next 90 days)
-- Business Question: How many product lots are expiring
--   within 90 days and how much stock is at risk?
-- Insight: Enables proactive stock rotation, emergency
--   procurement, and waste reduction.
-- ============================================================

SELECT
    mpc.product_code,
    mpc.product_name,
    mpc.manufacturer,
    pi.lot_number,
    pi.expiry_date,
    pi.quantity                                                    AS qty_at_risk,
    DATEDIFF(pi.expiry_date, CURDATE())                            AS days_until_expiry,
    CASE
        WHEN pi.expiry_date < CURDATE()
             THEN 'EXPIRED'
        WHEN DATEDIFF(pi.expiry_date, CURDATE()) <= 30
             THEN 'CRITICAL (<=30 days)'
        WHEN DATEDIFF(pi.expiry_date, CURDATE()) <= 60
             THEN 'HIGH (31-60 days)'
        ELSE     'MODERATE (61-90 days)'
    END                                                            AS expiry_risk_band
FROM ProductInventory      pi
JOIN MedicalProductCatalog mpc ON mpc.product_id = pi.product_id
WHERE DATEDIFF(pi.expiry_date, CURDATE()) <= 90
ORDER BY days_until_expiry ASC;


-- ============================================================
-- QUERY 7: Inventory Specialist – Next-Week Fulfilment Gap
-- Role:     Inventory Specialist
-- Business Question: Which upcoming operations scheduled for
--   next week have an unfulfilled product allocation gap
--   (qty_allocated < qty_reserved)?
-- Insight:  Gives the inventory team an advance view of
--   shortfall items so they can raise urgent purchase orders
--   before the operation date.
-- Date range used: CURDATE()+1 to CURDATE()+7  (rolling 7 days
--   from tomorrow, i.e. "next week" regardless of run date).
-- ============================================================

-- ── PART A: Product shortfalls ─────────────────────────────
SELECT
    'Product'                                                      AS resource_type,
    os.operation_code,
    os.operation_date,
    os.start_time,
    dep.department_name,
    dep.specialisation,
    mpc.product_code                                               AS resource_code,
    mpc.product_name                                               AS resource_name,
    mpc.manufacturer,
    pi.lot_number,
    pi.expiry_date,
    opb.quantity_reserved,
    opb.quantity_allocated,
    (opb.quantity_reserved - opb.quantity_allocated)               AS unfulfilled_qty,
    ROUND(
        100.0 * opb.quantity_allocated
        / NULLIF(opb.quantity_reserved, 0), 1
    )                                                              AS allocation_pct,
    CASE
        WHEN opb.quantity_allocated = 0 THEN 'NOT ALLOCATED — ORDER NOW'
        WHEN (opb.quantity_reserved - opb.quantity_allocated) > 0
             THEN 'PARTIAL — TOP UP REQUIRED'
    END                                                            AS action_required
FROM OperationScheduling     os
JOIN Departments             dep ON dep.department_id   = os.department_id
JOIN OperationProductBooking opb ON opb.operation_id    = os.operation_id
JOIN ProductInventory        pi  ON pi.inventory_id     = opb.inventory_id
JOIN MedicalProductCatalog   mpc ON mpc.product_id      = pi.product_id
WHERE os.operation_date BETWEEN DATE_ADD(CURDATE(), INTERVAL 1 DAY)
                            AND DATE_ADD(CURDATE(), INTERVAL 7 DAY)
  AND os.status IN ('Scheduled', 'In Progress')
  AND opb.quantity_allocated < opb.quantity_reserved      -- ← fulfilment gap filter
ORDER BY os.operation_date ASC, os.start_time ASC, unfulfilled_qty DESC;


-- ── PART B: Equipment shortfalls ───────────────────────────
SELECT
    'Equipment'                                                    AS resource_type,
    os.operation_code,
    os.operation_date,
    os.start_time,
    dep.department_name,
    dep.specialisation,
    mec.equipment_code                                             AS resource_code,
    mec.equipment_name                                             AS resource_name,
    NULL                                                           AS manufacturer,
    NULL                                                           AS lot_number,
    NULL                                                           AS expiry_date,
    oeb.quantity_reserved,
    oeb.quantity_allocated,
    (oeb.quantity_reserved - oeb.quantity_allocated)               AS unfulfilled_qty,
    ROUND(
        100.0 * oeb.quantity_allocated
        / NULLIF(oeb.quantity_reserved, 0), 1
    )                                                              AS allocation_pct,
    CASE
        WHEN oeb.quantity_allocated = 0 THEN 'NOT ALLOCATED — ORDER NOW'
        WHEN (oeb.quantity_reserved - oeb.quantity_allocated) > 0
             THEN 'PARTIAL — TOP UP REQUIRED'
    END                                                            AS action_required
FROM OperationScheduling        os
JOIN Departments                dep ON dep.department_id    = os.department_id
JOIN OperationEquipmentBooking  oeb ON oeb.operation_id     = os.operation_id
JOIN EquipmentInventory         ei  ON ei.equipment_inv_id  = oeb.equipment_inv_id
JOIN MedicalEquipmentCatalog    mec ON mec.equipment_id     = ei.equipment_id
WHERE os.operation_date BETWEEN DATE_ADD(CURDATE(), INTERVAL 1 DAY)
                            AND DATE_ADD(CURDATE(), INTERVAL 7 DAY)
  AND os.status IN ('Scheduled', 'In Progress')
  AND oeb.quantity_allocated < oeb.quantity_reserved      -- ← fulfilment gap filter
ORDER BY os.operation_date ASC, os.start_time ASC, unfulfilled_qty DESC;


-- ============================================================
-- QUERY 8: Monthly Medical Product Demand Patterns
-- Business Question: Which products experience the highest
--   demand each month, and are there recurring seasonal peaks?
-- Insight: Enables procurement teams to pre-order stock ahead
--   of high-demand months and avoid last-minute shortfalls.
-- ============================================================

WITH monthly_demand AS (
    SELECT
        DATE_FORMAT(os.operation_date, '%Y-%m')    AS op_month,
        MONTH(os.operation_date)                   AS month_num,
        YEAR(os.operation_date)                    AS year_num,
        mpc.product_id,
        mpc.product_code,
        mpc.product_name,
        mpc.manufacturer,
        COUNT(DISTINCT opb.operation_id)           AS operations_using_product,
        SUM(opb.quantity_reserved)                 AS monthly_qty_reserved,
        SUM(opb.quantity_allocated)                AS monthly_qty_allocated
    FROM OperationProductBooking opb
    JOIN ProductInventory        pi  ON pi.inventory_id  = opb.inventory_id
    JOIN MedicalProductCatalog   mpc ON mpc.product_id   = pi.product_id
    JOIN OperationScheduling     os  ON os.operation_id  = opb.operation_id
    WHERE os.status IN ('Completed', 'In Progress', 'Scheduled')
    GROUP BY
        op_month, month_num, year_num,
        mpc.product_id, mpc.product_code, mpc.product_name, mpc.manufacturer
)
SELECT
    md.op_month,
    md.product_code,
    md.product_name,
    md.manufacturer,
    md.operations_using_product,
    md.monthly_qty_reserved,
    md.monthly_qty_allocated,
    ROUND(
        100.0 * md.monthly_qty_allocated
        / NULLIF(md.monthly_qty_reserved, 0), 1
    )                                              AS fulfillment_rate_pct,
    -- 3-month rolling average for trend smoothing
    ROUND(
        AVG(md.monthly_qty_reserved) OVER (
            PARTITION BY md.product_id
            ORDER BY md.year_num, md.month_num
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 1
    )                                              AS rolling_3m_avg_qty,
    CASE
        WHEN md.monthly_qty_reserved > AVG(md.monthly_qty_reserved) OVER (
                PARTITION BY md.product_id
             )
        THEN 'ABOVE AVERAGE'
        ELSE 'NORMAL / BELOW'
    END                                            AS demand_flag
FROM monthly_demand md
ORDER BY md.product_code, md.op_month;


-- ============================================================
-- QUERY 9: Doctors Available on a Given Date
-- Role:     Scheduling Coordinator / Department Manager
-- Business Question: Which doctors have a recorded shift on
--   a specific date, and what hours are they working?
-- Usage:    Change the date in the WHERE clause to the date
--           you want to check.
-- ============================================================

SELECT
    d.doctor_code,
    CONCAT(d.f_name, ' ', d.l_name)               AS doctor_name,
    GROUP_CONCAT(dep.department_name
        ORDER BY dep.department_name SEPARATOR ', ')
                                                   AS departments,
    GROUP_CONCAT(dd.role
        ORDER BY dep.department_name SEPARATOR ', ')
                                                   AS roles,
    ds.shift_date,
    DATE_FORMAT(ds.start_time, '%H:%i')            AS shift_start,
    DATE_FORMAT(ds.end_time,   '%H:%i')            AS shift_end,
    ROUND(
        TIMESTAMPDIFF(MINUTE, ds.start_time, ds.end_time) / 60.0, 1
    )                                              AS shift_hours
FROM DoctorShifts     ds
JOIN Doctors          d   ON d.doctor_id      = ds.doctor_id
LEFT JOIN DoctorDepartment dd  ON dd.doctor_id = d.doctor_id
LEFT JOIN Departments      dep ON dep.department_id = dd.department_id
WHERE ds.shift_date = '2026-03-25'          -- ← change date here
GROUP BY
    d.doctor_id, d.doctor_code, d.f_name, d.l_name,
    ds.shift_id, ds.shift_date, ds.start_time, ds.end_time
ORDER BY ds.start_time ASC, d.l_name ASC;


-- ============================================================
-- QUERY 10: Nurses Available on a Given Date
-- Role:     Scheduling Coordinator / Ward Manager
-- Business Question: Which nurses have a recorded shift on
--   a specific date, and what hours are they covering?
-- Usage:    Change the date in the WHERE clause to the date
--           you want to check.
-- ============================================================

SELECT
    n.nurse_code,
    CONCAT(n.f_name, ' ', n.l_name)               AS nurse_name,
    GROUP_CONCAT(dep.department_name
        ORDER BY dep.department_name SEPARATOR ', ')
                                                   AS departments,
    GROUP_CONCAT(nd.role
        ORDER BY dep.department_name SEPARATOR ', ')
                                                   AS roles,
    ns.shift_date,
    DATE_FORMAT(ns.start_time, '%H:%i')            AS shift_start,
    DATE_FORMAT(ns.end_time,   '%H:%i')            AS shift_end,
    ROUND(
        TIMESTAMPDIFF(MINUTE, ns.start_time, ns.end_time) / 60.0, 1
    )                                              AS shift_hours
FROM NurseShifts      ns
JOIN Nurses           n   ON n.nurse_id       = ns.nurse_id
LEFT JOIN NurseDepartment  nd  ON nd.nurse_id  = n.nurse_id
LEFT JOIN Departments      dep ON dep.department_id = nd.department_id
WHERE ns.shift_date = '2026-03-25'          -- ← change date here
GROUP BY
    n.nurse_id, n.nurse_code, n.f_name, n.l_name,
    ns.shift_id, ns.shift_date, ns.start_time, ns.end_time
ORDER BY ns.start_time ASC, n.l_name ASC;


-- ============================================================
-- QUERY 11: Operating Rooms Free on a Given Date
-- Role:     Theatre Scheduler / Operations Manager
-- Business Question: Which operating rooms have NO active or
--   scheduled operations on a specific date, and are therefore
--   available for new bookings?
-- Usage:    Change the date literal to the date you want to
--           check. Rooms with zero bookings on that date are
--           returned. A room with only Cancelled/Postponed ops
--           is also treated as free.
-- ============================================================

SELECT
    orr.room_code,
    orr.room_location,
    orr.description,
    COALESCE(busy.booked_ops, 0)                   AS active_ops_that_day,
    CASE
        WHEN COALESCE(busy.booked_ops, 0) = 0 THEN 'FREE — Available to book'
        ELSE                                       'BUSY'
    END                                            AS availability_status
FROM OperationRooms orr
LEFT JOIN (
    -- count active (non-cancelled, non-postponed) ops per room for the target date
    SELECT
        or_room_id,
        COUNT(*) AS booked_ops
    FROM OperationScheduling
    WHERE operation_date = '2026-03-25'     -- ← change date here
      AND status NOT IN ('Cancelled', 'Postponed')
    GROUP BY or_room_id
) busy ON busy.or_room_id = orr.room_id
WHERE COALESCE(busy.booked_ops, 0) = 0      -- only return free rooms
ORDER BY orr.room_code ASC;


-- ============================================================
-- QUERY 12: Doctor Scheduling Conflict Check
-- Role:     Booking System / Scheduling Coordinator
-- Purpose:  Before assigning a doctor to a new operation,
--           verify they are not already assigned to another
--           active operation whose time window overlaps.
-- Overlap rule (standard interval logic):
--             new_start < existing_end
--             AND new_end > existing_start
-- Result:   ROWS RETURNED  → conflict exists, do NOT book.
--           NO ROWS        → doctor is free, safe to book.
-- Usage:    Replace the three values marked ← below.
-- ============================================================

SELECT
    os.operation_id,
    os.operation_code,
    os.operation_date,
    os.start_time                                  AS existing_op_start,
    os.end_time                                    AS existing_op_end,
    os.status                                      AS existing_op_status,
    dep.department_name,
    dso.doctor_role                                AS assigned_role,
    CONCAT(d.f_name, ' ', d.l_name)               AS doctor_name,
    d.doctor_code
FROM DoctorScheduledOperations dso
JOIN OperationScheduling       os  ON os.operation_id   = dso.operation_id
JOIN Doctors                   d   ON d.doctor_id       = dso.doctor_id
JOIN Departments               dep ON dep.department_id = os.department_id
WHERE dso.doctor_id = 5                              -- ← target doctor_id
  AND os.status NOT IN ('Cancelled', 'Postponed')    -- skip inactive ops
  AND '2026-04-01 09:00:00' < os.end_time            -- ← proposed new start
  AND '2026-04-01 12:00:00' > os.start_time          -- ← proposed new end
ORDER BY os.start_time ASC;

-- Zero rows  → CLEAR: safe to add the new booking.
-- Any rows   → CONFLICT: clashing operation details are returned
--              so the coordinator can reschedule accordingly.


-- ============================================================
-- QUERY 13: Equipment Demand-to-Availability Ratio
-- Business Question: For each piece of medical equipment, how
--   much of the total available stock is currently reserved
--   by active/upcoming operations?
-- Insight: A ratio close to or above 1.0 means the equipment
--   is fully committed — procurement or maintenance teams
--   should be alerted before accepting new operation bookings.
-- ============================================================

SELECT
    mec.equipment_code,
    mec.equipment_name,
    -- total units held in inventory across all inventory records
    SUM(ei.quantity)                                           AS total_stock,
    -- total units reserved by active/upcoming operations
    COALESCE(demand.total_reserved, 0)                        AS total_reserved,
    -- units still uncommitted
    SUM(ei.quantity) - COALESCE(demand.total_reserved, 0)     AS available_stock,
    -- ratio: 1.0 = fully committed, >1.0 = overbooked
    ROUND(
        COALESCE(demand.total_reserved, 0)
        / NULLIF(SUM(ei.quantity), 0), 3
    )                                                         AS demand_to_availability_ratio,
    CASE
        WHEN SUM(ei.quantity) = 0
             THEN 'NO STOCK'
        WHEN COALESCE(demand.total_reserved, 0) >= SUM(ei.quantity)
             THEN 'OVERCOMMITTED ⚠'
        WHEN COALESCE(demand.total_reserved, 0) >= SUM(ei.quantity) * 0.80
             THEN 'HIGH PRESSURE (>=80%)'
        WHEN COALESCE(demand.total_reserved, 0) >= SUM(ei.quantity) * 0.50
             THEN 'MODERATE (50-79%)'
        ELSE 'LOW (<50%)'
    END                                                       AS pressure_level
FROM MedicalEquipmentCatalog mec
JOIN EquipmentInventory      ei      ON ei.equipment_id   = mec.equipment_id
-- aggregate reserved quantities only for active/upcoming operations
LEFT JOIN (
    SELECT
        ei2.equipment_id,
        SUM(oeb.quantity_reserved)  AS total_reserved
    FROM OperationEquipmentBooking oeb
    JOIN EquipmentInventory        ei2 ON ei2.equipment_inv_id = oeb.equipment_inv_id
    JOIN OperationScheduling       os  ON os.operation_id      = oeb.operation_id
    WHERE os.status IN ('Scheduled', 'In Progress')
    GROUP BY ei2.equipment_id
) demand ON demand.equipment_id = mec.equipment_id
GROUP BY mec.equipment_id, mec.equipment_code, mec.equipment_name, demand.total_reserved
ORDER BY demand_to_availability_ratio DESC;
