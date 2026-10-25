-- 99 Reset: remove the Tech scenario
DELETE FROM `serving.mc_simulated_pnl` WHERE scenario_id = 'tech_down_10';
DELETE FROM `raw.stress_scenarios` WHERE scenario_id = 'tech_down_10';
