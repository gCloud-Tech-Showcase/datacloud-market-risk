-- 01 Portfolio: positions by desk
SELECT desk, book, COUNT(*) AS positions, SUM(notional_usd) AS notional_usd
FROM `raw.portfolio_positions`
GROUP BY desk, book
ORDER BY desk, book;
