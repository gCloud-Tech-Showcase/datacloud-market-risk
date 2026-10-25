-- 00 Check: scenarios before you start
SELECT scenario_id, description, sector, shock_pct
FROM `raw.stress_scenarios`
ORDER BY scenario_id;
