-- 04a VaR: forward-looking vs historical
SELECT scenario_id, method, ROUND(var_95_usd) AS var_95_usd, ROUND(var_99_usd) AS var_99_usd,
       ROUND(es_99_usd) AS es_99_usd, ROUND(var_99_pct_notional, 2) AS var_99_pct
FROM `serving.portfolio_var_summary`
WHERE scenario_id = 'baseline'
ORDER BY method;
