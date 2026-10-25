-- 05a Stress: add Tech falls 10% and simulate
INSERT INTO `raw.stress_scenarios` (scenario_id, description, sector, shock_pct)
VALUES ('tech_down_10', 'Information Technology falls 10%', 'Information Technology', -0.10);

CALL `serving.simulate_scenario`('tech_down_10');
