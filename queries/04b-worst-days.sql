-- 04b VaR: worst historical days
SELECT date, ROUND(pnl_usd) AS pnl_usd, worst_day_rank
FROM `serving.historical_pnl`
ORDER BY worst_day_rank
LIMIT 5;
