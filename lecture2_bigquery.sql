-- =====================================================
-- Query 1: Total Users and New Users
-- =====================================================

WITH UserInfo AS (
  SELECT
    user_pseudo_id,
    MAX(IF(event_name IN ('first_visit', 'first_open'), 1, 0)) AS is_new_user
  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20201101' AND '20201130'
  GROUP BY
    user_pseudo_id
)

SELECT
  COUNT(*) AS total_users,
  SUM(is_new_user) AS new_users
FROM UserInfo;


-- =====================================================
-- Query 2: Extract page_location with UNNEST
-- =====================================================

SELECT
  TIMESTAMP_MICROS(event_timestamp) AS event_time,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'page_location'
    LIMIT 1
  ) AS page_location
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE
  event_name = 'page_view'
  AND _TABLE_SUFFIX BETWEEN '20201201' AND '20201202'
LIMIT 50;


-- =====================================================
-- Query 3: Item-Level Analysis with UNNEST
-- =====================================================

SELECT
  event_date,
  item.item_name,
  COUNT(*) AS item_rows
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS e,
  UNNEST(e.items) AS item
WHERE
  e.event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
GROUP BY
  event_date,
  item.item_name
ORDER BY
  item_rows DESC
LIMIT 20;


-- =====================================================
-- Query 4: Events Seen per Day with STRING_AGG
-- =====================================================

SELECT
  event_date,
  STRING_AGG(
    DISTINCT event_name,
    ', '
    ORDER BY event_name
  ) AS events_seen
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20201201' AND '20201203'
GROUP BY
  event_date
ORDER BY
  event_date;


-- =====================================================
-- Query 5: Items Added to Cart per User with ARRAY_AGG
-- =====================================================

SELECT
  user_pseudo_id,
  ARRAY_AGG(item.item_name) AS items_added_to_cart
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
  UNNEST(items) AS item
WHERE
  event_name = 'add_to_cart'
  AND _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
GROUP BY
  user_pseudo_id
ORDER BY
  user_pseudo_id
LIMIT 10;


-- =====================================================
-- Query 6: Session-Level Cart Summary
-- =====================================================

WITH add_to_cart AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
      LIMIT 1
    ) AS session_id,
    TIMESTAMP_MICROS(event_timestamp) AS event_timestamp,
    i.item_id,
    i.item_name,
    i.quantity,
    i.price
  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
    UNNEST(items) AS i
  WHERE
    event_name = 'add_to_cart'
    AND _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
)

SELECT
  user_pseudo_id,
  session_id,
  COUNT(*) AS total_add_to_cart_events,
  ARRAY_AGG(
    STRUCT(
      item_id,
      item_name,
      quantity,
      price,
      event_timestamp
    )
    ORDER BY quantity DESC, event_timestamp ASC
    LIMIT 10
  ) AS cart_items
FROM add_to_cart
WHERE
  session_id IS NOT NULL
GROUP BY
  user_pseudo_id,
  session_id;


-- =====================================================
-- Query 7: Daily Users Joined with Daily Purchases
-- =====================================================

WITH daily_users AS (
  SELECT
    event_date,
    COUNT(DISTINCT user_pseudo_id) AS users
  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
  GROUP BY
    event_date
),

daily_purchases AS (
  SELECT
    event_date,
    COUNT(
      DISTINCT (
        SELECT value.string_value
        FROM UNNEST(event_params)
        WHERE key = 'transaction_id'
        LIMIT 1
      )
    ) AS purchases
  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
  GROUP BY
    event_date
)

SELECT
  u.event_date,
  u.users,
  IFNULL(p.purchases, 0) AS purchases,
  ROUND(
    IFNULL(p.purchases, 0) / NULLIF(u.users, 0) * 100,
    2
  ) AS conversion_rate_pct
FROM daily_users AS u
LEFT JOIN daily_purchases AS p
  ON u.event_date = p.event_date
ORDER BY
  u.event_date;


-- =====================================================
-- Query 8: Top 3 Event Types per Day
-- =====================================================

WITH daily_event_counts AS (
  SELECT
    event_date,
    event_name,
    COUNT(*) AS events
  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20201201' AND '20201207'
  GROUP BY
    event_date,
    event_name
)

SELECT
  event_date,
  event_name,
  events,
  RANK() OVER (
    PARTITION BY event_date
    ORDER BY events DESC
  ) AS rnk
FROM daily_event_counts
QUALIFY
  rnk <= 3
ORDER BY
  event_date,
  rnk;


-- =====================================================
-- Query 9: Rolling 7-Day Average of Purchases
-- =====================================================

WITH daily_purchases AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS dt,
    COUNT(*) AS purchases
  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
  GROUP BY
    dt
)

SELECT
  dt,
  purchases,
  AVG(purchases) OVER (
    ORDER BY dt
    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
  ) AS purchases_7d_avg
FROM daily_purchases
ORDER BY
  dt;


-- =====================================================
-- Query 10: Approximate Users per Event Type
-- =====================================================

SELECT
  event_name,
  APPROX_COUNT_DISTINCT(user_pseudo_id) AS approx_users
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
GROUP BY
  event_name
ORDER BY
  approx_users DESC
LIMIT 15;