-- 05b Stress: VaR by desk
SELECT desk,
       ROUND(MAX(IF(scenario_id = 'baseline', var_99_usd, NULL))) AS baseline_var_99,
       ROUND(MAX(IF(scenario_id = 'tech_down_10', var_99_usd, NULL))) AS tech_down_10_var_99
FROM `serving.var_by_desk`
GROUP BY desk
ORDER BY desk;
