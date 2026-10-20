-- =====================================================================
-- Hospital Resource Management — Business Insight Queries (SQLite)
--
-- Date-relative queries use a fixed reference date of 2026-03-25
-- (the date the analysis was run) so results are reproducible.
-- To run "live", replace DATE('2026-03-25') with DATE('now').
--
-- Each query starts with a "-- name:" line used by build_database.py
-- to save its result to outputs/<name>.csv.
-- =====================================================================


-- name: q01_appointments_by_doctor
-- Business question: Which doctors have the highest patient volume,
-- and what share of their appointments are completed or cancelled?
SELECT
    d.doctor_code,
    d.f_name || ' ' || d.l_name                                   AS doctor_name,
    COUNT(*)                                                      AS total_appointments,
    SUM(a.status = 'Completed')                                   AS completed,
    SUM(a.status = 'Cancelled')                                   AS cancelled,
    SUM(a.status = 'Scheduled')                                   AS scheduled,
    ROUND(100.0 * SUM(a.status = 'Completed') / COUNT(*), 1)      AS completion_rate_pct
FROM Appointments a
JOIN Doctors      d ON d.doctor_id = a.doctor_id
GROUP BY d.doctor_id
ORDER BY total_appointments DESC;


-- name: q02_department_operation_load
-- Business question: How many operations has each department handled,
-- and what are its cancellation and postponement rates?
SELECT
    dep.department_code,
    dep.department_name,
    COUNT(*)                                                      AS total_operations,
    SUM(os.status = 'Completed')                                  AS completed,
    SUM(os.status = 'Cancelled')                                  AS cancelled,
    SUM(os.status = 'Postponed')                                  AS postponed,
    SUM(os.status IN ('Scheduled','In Progress'))                 AS upcoming,
    ROUND(100.0 * SUM(os.status IN ('Cancelled','Postponed'))
          / NULLIF(SUM(os.status IN ('Completed','Cancelled','Postponed')), 0), 1)
                                                                  AS disruption_rate_pct
FROM OperationScheduling os
JOIN Departments         dep ON dep.department_id = os.department_id
GROUP BY dep.department_id
ORDER BY disruption_rate_pct DESC;


-- name: q03_doctor_workload
-- Business question: How many hours has each doctor worked, and how
-- many operations have they taken part in?
-- FIX: shifts and operations are aggregated separately before joining.
-- Joining both tables to Doctors first multiplies every shift by every
-- operation (row fan-out), which inflated hours by up to 62x.
WITH shift_hours AS (
    SELECT doctor_id,
           COUNT(*)                                                       AS total_shifts,
           SUM((julianday(end_time) - julianday(start_time)) * 24)        AS hours
    FROM DoctorShifts
    GROUP BY doctor_id
),
ops AS (
    SELECT doctor_id, COUNT(DISTINCT operation_id) AS operations
    FROM DoctorScheduledOperations
    GROUP BY doctor_id
)
SELECT
    d.doctor_code,
    d.f_name || ' ' || d.l_name                                   AS doctor_name,
    COALESCE(s.total_shifts, 0)                                   AS total_shifts,
    ROUND(COALESCE(s.hours, 0), 1)                                AS total_shift_hours,
    COALESCE(o.operations, 0)                                     AS operations_participated,
    ROUND(s.hours / NULLIF(o.operations, 0), 1)                   AS shift_hours_per_operation
FROM Doctors          d
LEFT JOIN shift_hours s ON s.doctor_id = d.doctor_id
LEFT JOIN ops         o ON o.doctor_id = d.doctor_id
ORDER BY total_shift_hours DESC;


-- name: q04_nurse_workload
-- Business question: How does each nurse's shift coverage compare with
-- the number of operations they assist?  (Same fan-out fix as q03.)
WITH shift_hours AS (
    SELECT nurse_id,
           COUNT(*)                                                       AS total_shifts,
           SUM((julianday(end_time) - julianday(start_time)) * 24)        AS hours
    FROM NurseShifts
    GROUP BY nurse_id
),
ops AS (
    SELECT nurse_id, COUNT(DISTINCT operation_id) AS operations
    FROM NurseScheduledOperations
    GROUP BY nurse_id
)
SELECT
    n.nurse_code,
    n.f_name || ' ' || n.l_name                                   AS nurse_name,
    COALESCE(s.total_shifts, 0)                                   AS total_shifts,
    ROUND(COALESCE(s.hours, 0), 1)                                AS total_shift_hours,
    COALESCE(o.operations, 0)                                     AS operations_assisted
FROM Nurses           n
LEFT JOIN shift_hours s ON s.nurse_id = n.nurse_id
LEFT JOIN ops         o ON o.nurse_id = n.nurse_id
ORDER BY total_shift_hours DESC;


-- name: q05_monthly_operation_trend
-- Business question: How does operation throughput vary month to month?
SELECT
    strftime('%Y-%m', operation_date)                             AS op_month,
    COUNT(*)                                                      AS total_operations,
    SUM(status = 'Completed')                                     AS completed,
    SUM(status = 'Cancelled')                                     AS cancelled,
    SUM(status = 'Postponed')                                     AS postponed,
    SUM(status IN ('Scheduled','In Progress'))                    AS upcoming
FROM OperationScheduling
GROUP BY op_month
ORDER BY op_month;


-- name: q06_inventory_expiry_risk
-- Business question: Which product lots are expired or expire within
-- 90 days, and how much stock is at risk?
SELECT
    mpc.product_code,
    mpc.product_name,
    mpc.manufacturer,
    pi.lot_number,
    pi.expiry_date,
    pi.quantity                                                   AS qty_at_risk,
    CAST(julianday(pi.expiry_date) - julianday(DATE('2026-03-25')) AS INTEGER)
                                                                  AS days_until_expiry,
    CASE
        WHEN pi.expiry_date < DATE('2026-03-25')                         THEN 'EXPIRED'
        WHEN julianday(pi.expiry_date) - julianday('2026-03-25') <= 30   THEN 'CRITICAL (<=30 days)'
        WHEN julianday(pi.expiry_date) - julianday('2026-03-25') <= 60   THEN 'HIGH (31-60 days)'
        ELSE                                                                  'MODERATE (61-90 days)'
    END                                                           AS expiry_risk_band
FROM ProductInventory      pi
JOIN MedicalProductCatalog mpc ON mpc.product_id = pi.product_id
WHERE julianday(pi.expiry_date) - julianday('2026-03-25') <= 90
ORDER BY days_until_expiry;


-- name: q07a_next_week_product_gaps
-- Business question (Inventory Specialist): which product bookings for
-- operations in the next 7 days are not yet fully allocated?
SELECT
    os.operation_code,
    os.operation_date,
    dep.department_name,
    mpc.product_name,
    pi.lot_number,
    opb.quantity_reserved,
    opb.quantity_allocated,
    opb.quantity_reserved - opb.quantity_allocated                AS unfulfilled_qty,
    CASE WHEN opb.quantity_allocated = 0 THEN 'NOT ALLOCATED - ORDER NOW'
         ELSE 'PARTIAL - TOP UP REQUIRED' END                     AS action_required
FROM OperationScheduling     os
JOIN Departments             dep ON dep.department_id = os.department_id
JOIN OperationProductBooking opb ON opb.operation_id  = os.operation_id
JOIN ProductInventory        pi  ON pi.inventory_id   = opb.inventory_id
JOIN MedicalProductCatalog   mpc ON mpc.product_id    = pi.product_id
WHERE os.operation_date BETWEEN DATE('2026-03-25', '+1 day') AND DATE('2026-03-25', '+7 day')
  AND os.status IN ('Scheduled','In Progress')
  AND opb.quantity_allocated < opb.quantity_reserved
ORDER BY os.operation_date, os.start_time, unfulfilled_qty DESC;


-- name: q07b_next_week_equipment_gaps
-- Business question: which equipment bookings for operations in the
-- next 7 days are not yet fully allocated?
SELECT
    os.operation_code,
    os.operation_date,
    dep.department_name,
    mec.equipment_name,
    oeb.quantity_reserved,
    oeb.quantity_allocated,
    oeb.quantity_reserved - oeb.quantity_allocated                AS unfulfilled_qty,
    CASE WHEN oeb.quantity_allocated = 0 THEN 'NOT ALLOCATED - ORDER NOW'
         ELSE 'PARTIAL - TOP UP REQUIRED' END                     AS action_required
FROM OperationScheduling        os
JOIN Departments                dep ON dep.department_id   = os.department_id
JOIN OperationEquipmentBooking  oeb ON oeb.operation_id    = os.operation_id
JOIN EquipmentInventory         ei  ON ei.equipment_inv_id = oeb.equipment_inv_id
JOIN MedicalEquipmentCatalog    mec ON mec.equipment_id    = ei.equipment_id
WHERE os.operation_date BETWEEN DATE('2026-03-25', '+1 day') AND DATE('2026-03-25', '+7 day')
  AND os.status IN ('Scheduled','In Progress')
  AND oeb.quantity_allocated < oeb.quantity_reserved
ORDER BY os.operation_date, os.start_time, unfulfilled_qty DESC;


-- name: q08_monthly_product_demand
-- Business question: Which products see above-average demand, and how
-- is demand trending?  (CTE + window functions: rolling 3-month average
-- and month-on-month change.)
WITH monthly AS (
    SELECT
        strftime('%Y-%m', os.operation_date)                      AS op_month,
        mpc.product_id,
        mpc.product_name,
        COUNT(DISTINCT opb.operation_id)                          AS operations_using_product,
        SUM(opb.quantity_reserved)                                AS qty_reserved,
        SUM(opb.quantity_allocated)                               AS qty_allocated
    FROM OperationProductBooking opb
    JOIN ProductInventory        pi  ON pi.inventory_id = opb.inventory_id
    JOIN MedicalProductCatalog   mpc ON mpc.product_id  = pi.product_id
    JOIN OperationScheduling     os  ON os.operation_id = opb.operation_id
    WHERE os.status IN ('Completed','In Progress','Scheduled')
    GROUP BY op_month, mpc.product_id
)
SELECT
    op_month,
    product_name,
    operations_using_product,
    qty_reserved,
    qty_allocated,
    ROUND(100.0 * qty_allocated / NULLIF(qty_reserved, 0), 1)     AS fulfilment_rate_pct,
    ROUND(AVG(qty_reserved) OVER (PARTITION BY product_id ORDER BY op_month
                                  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1)
                                                                  AS rolling_3m_avg_qty,
    qty_reserved - LAG(qty_reserved) OVER (PARTITION BY product_id ORDER BY op_month)
                                                                  AS change_vs_prev_month,
    CASE WHEN qty_reserved > AVG(qty_reserved) OVER (PARTITION BY product_id)
         THEN 'ABOVE AVERAGE' ELSE 'NORMAL / BELOW' END           AS demand_flag
FROM monthly
ORDER BY product_name, op_month;


-- name: q09_doctors_on_shift
-- Business question (Scheduling Coordinator): which doctors are on
-- shift on a given date?  Change the date to check another day.
SELECT
    d.doctor_code,
    d.f_name || ' ' || d.l_name                                   AS doctor_name,
    (SELECT GROUP_CONCAT(dep.department_name || ' (' || dd.role || ')', '; ')
       FROM DoctorDepartment dd
       JOIN Departments dep ON dep.department_id = dd.department_id
      WHERE dd.doctor_id = d.doctor_id)                           AS departments_and_roles,
    strftime('%H:%M', ds.start_time)                              AS shift_start,
    strftime('%H:%M', ds.end_time)                                AS shift_end,
    ROUND((julianday(ds.end_time) - julianday(ds.start_time)) * 24, 1) AS shift_hours
FROM DoctorShifts ds
JOIN Doctors      d ON d.doctor_id = ds.doctor_id
WHERE ds.shift_date = '2026-03-25'
ORDER BY ds.start_time, d.l_name;


-- name: q10_nurses_on_shift
-- Business question: which nurses are on shift on a given date?
SELECT
    n.nurse_code,
    n.f_name || ' ' || n.l_name                                   AS nurse_name,
    (SELECT GROUP_CONCAT(dep.department_name || ' (' || nd.role || ')', '; ')
       FROM NurseDepartment nd
       JOIN Departments dep ON dep.department_id = nd.department_id
      WHERE nd.nurse_id = n.nurse_id)                             AS departments_and_roles,
    strftime('%H:%M', ns.start_time)                              AS shift_start,
    strftime('%H:%M', ns.end_time)                                AS shift_end,
    ROUND((julianday(ns.end_time) - julianday(ns.start_time)) * 24, 1) AS shift_hours
FROM NurseShifts ns
JOIN Nurses      n ON n.nurse_id = ns.nurse_id
WHERE ns.shift_date = '2026-03-25'
ORDER BY ns.start_time, n.l_name;


-- name: q11_free_operating_rooms
-- Business question (Theatre Scheduler): which operating rooms have no
-- active operations on a given date and can take new bookings?
SELECT
    r.room_code,
    r.room_location,
    r.floor
FROM OperationRooms r
WHERE NOT EXISTS (
    SELECT 1 FROM OperationScheduling os
    WHERE os.room_id = r.room_id
      AND os.operation_date = '2026-03-25'
      AND os.status NOT IN ('Cancelled','Postponed')
)
ORDER BY r.room_code;


-- name: q12_doctor_conflict_check
-- Business question (booking check): is doctor 5 already in an active
-- operation that overlaps a proposed slot (2026-04-01 09:00-12:00)?
-- Zero rows = safe to book; any rows = clash.
SELECT
    os.operation_code,
    os.start_time                                                 AS existing_start,
    os.end_time                                                   AS existing_end,
    os.status,
    dso.doctor_role,
    d.f_name || ' ' || d.l_name                                   AS doctor_name
FROM DoctorScheduledOperations dso
JOIN OperationScheduling       os ON os.operation_id = dso.operation_id
JOIN Doctors                   d  ON d.doctor_id     = dso.doctor_id
WHERE dso.doctor_id = 5
  AND os.status NOT IN ('Cancelled','Postponed')
  AND '2026-04-01 09:00:00' < os.end_time
  AND '2026-04-01 12:00:00' > os.start_time;


-- name: q13_equipment_peak_demand
-- Business question: Is there enough of each piece of equipment for the
-- busiest day of upcoming operations?
-- FIX: equipment is reusable, so total bookings across a whole year must
-- not be compared with stock. This compares stock with the PEAK number
-- of units booked on any single day.
WITH daily AS (
    SELECT
        ei.equipment_id,
        os.operation_date,
        SUM(oeb.quantity_reserved)                                AS units_booked
    FROM OperationEquipmentBooking oeb
    JOIN EquipmentInventory        ei ON ei.equipment_inv_id = oeb.equipment_inv_id
    JOIN OperationScheduling       os ON os.operation_id     = oeb.operation_id
    WHERE os.status IN ('Scheduled','In Progress')
    GROUP BY ei.equipment_id, os.operation_date
),
peak AS (
    SELECT equipment_id,
           MAX(units_booked)                                      AS peak_daily_demand,
           COUNT(*)                                               AS days_with_bookings
    FROM daily
    GROUP BY equipment_id
)
SELECT
    mec.equipment_code,
    mec.equipment_name,
    SUM(ei.quantity)                                              AS total_stock,
    COALESCE(p.peak_daily_demand, 0)                              AS peak_daily_demand,
    COALESCE(p.days_with_bookings, 0)                             AS days_with_bookings,
    ROUND(1.0 * COALESCE(p.peak_daily_demand, 0) / NULLIF(SUM(ei.quantity), 0), 2)
                                                                  AS peak_utilisation,
    CASE
        WHEN COALESCE(p.peak_daily_demand, 0) > SUM(ei.quantity)       THEN 'SHORTAGE ON PEAK DAY'
        WHEN COALESCE(p.peak_daily_demand, 0) >= 0.8 * SUM(ei.quantity) THEN 'HIGH PRESSURE (>=80%)'
        WHEN COALESCE(p.peak_daily_demand, 0) >= 0.5 * SUM(ei.quantity) THEN 'MODERATE (50-79%)'
        ELSE 'LOW (<50%)'
    END                                                           AS pressure_level
FROM MedicalEquipmentCatalog mec
JOIN EquipmentInventory      ei ON ei.equipment_id = mec.equipment_id
LEFT JOIN peak               p  ON p.equipment_id  = mec.equipment_id
GROUP BY mec.equipment_id
ORDER BY peak_utilisation DESC;
