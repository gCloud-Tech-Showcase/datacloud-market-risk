-- 03 Monte Carlo: path 42
SELECT scenario_id, path_id, historical_date, symbol, desk, notional_usd,
       ROUND(sim_log_return, 5) AS sim_log_return, ROUND(sim_pnl_usd, 2) AS sim_pnl_usd
FROM `serving.mc_simulated_pnl`
WHERE scenario_id = 'baseline' AND path_id = 42 AND symbol IN ('AAPL', 'JPM', 'XOM')
ORDER BY symbol;
