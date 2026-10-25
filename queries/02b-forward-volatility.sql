-- 02b TimesFM: forward vs historical volatility
SELECT symbol, ROUND(last_close, 2) AS last_close,
       ROUND(forecast_low_99, 2) AS low_99, ROUND(forecast_high_99, 2) AS high_99,
       ROUND(100 * timesfm_vol_annualized, 1) AS timesfm_vol_pct,
       ROUND(100 * historical_vol_annualized, 1) AS historical_vol_pct
FROM `serving.timesfm_forward_params`
WHERE symbol IN ('JPM', 'NVDA', 'XOM', 'GOOGL')
ORDER BY symbol;
