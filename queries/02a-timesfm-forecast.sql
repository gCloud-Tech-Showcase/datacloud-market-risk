-- 02a TimesFM: JPM forecast
SELECT symbol, DATE(forecast_timestamp) AS step_date, ROUND(forecast_value, 2) AS forecast_value,
       ROUND(prediction_interval_lower_bound, 2) AS lower_99,
       ROUND(prediction_interval_upper_bound, 2) AS upper_99, ai_forecast_status
FROM `serving.timesfm_forecast`
WHERE symbol = 'JPM'
ORDER BY forecast_timestamp;
