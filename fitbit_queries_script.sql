--Performing basic cleaning on hourly intensities and sleepday tables
SELECT *
FROM `portfolioproject-449608.FitBit_Data.hourly_intensities`
WHERE TotalIntensity IS NULL;

SELECT *
FROM `portfolioproject-449608.FitBit_Data.hourly_intensities`
WHERE AverageIntensity IS NULL;

SELECT *
FROM `portfolioproject-449608.FitBit_Data.sleepday`
WHERE TotalSleepRecords IS NULL;

SELECT *
FROM `portfolioproject-449608.FitBit_Data.sleepday`
WHERE TotalMinutesAsleep IS NULL;

SELECT *
FROM `portfolioproject-449608.FitBit_Data.sleepday`
WHERE TotalTimeInBed IS NULL;
--Now I want to see if there are any duplicates
--Counting the duplicates for each row
SELECT COUNT(*) AS duplicate_count
FROM (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY Id, SleepDay ORDER BY SleepDay) AS row_number
  FROM `portfolioproject-449608.FitBit_Data.sleepday`
)
WHERE row_number > 1;
--Checking if hourly intensities has any duplicates, result is 0
SELECT COUNT(*) AS duplicate_count
FROM (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY Id, ActivityHour ORDER BY ActivityHour) AS row_number
  FROM `portfolioproject-449608.FitBit_Data.hourly_intensities`
)
WHERE row_number > 1;
--But SleepDay has, so I'm seeing the duplicates in full detail
SELECT *
FROM (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY Id, SleepDay ORDER BY SleepDay) AS row_number
  FROM `portfolioproject-449608.FitBit_Data.sleepday`
)
WHERE row_number > 1;
--There are only 3 instances. I create the new cleaned table without the duplicates 
CREATE OR REPLACE TABLE `portfolioproject-449608.FitBit_Data.sleepday_cleaned` AS
SELECT *
FROM (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY Id, SleepDay ORDER BY SleepDay) AS row_number
  FROM `portfolioproject-449608.FitBit_Data.sleepday`
)
WHERE row_number = 1;
--Testing if there are any duplicates in a new table
SELECT * FROM `portfolioproject-449608.FitBit_Data.sleepday_cleaned` LIMIT 10;

SELECT *
FROM (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY Id, SleepDay ORDER BY SleepDay)
  FROM `portfolioproject-449608.FitBit_Data.sleepday_cleaned`
)
WHERE row_number > 1;
--Good, there are no duplicates. I drop the old table. 
DROP TABLE `portfolioproject-449608.FitBit_Data.sleepday`;
--Renaming the cleaned table to the original name
ALTER TABLE `portfolioproject-449608.FitBit_Data.sleepday_cleaned`
RENAME TO `sleepday`

--Because I modified the timestamps column with Python on raw data earlier, there's no need to do it in BigQuery. Therefore I skip the step and set variables for time of day
---- Setting variables for time of day/ day of week analyses
DECLARE
  MORNING_START,
  MORNING_END,
  AFTERNOON_END,
  EVENING_END INT64;
-- Set the times for the times of the day
SET
  MORNING_START = 6;
SET
  MORNING_END = 12;
SET
  AFTERNOON_END = 18;
SET
  EVENING_END = 21;
-- Check to see which column names are shared across tables
SELECT
column_name,
COUNT(table_name)
FROM
`portfolioproject-449608.FitBit_Data.INFORMATION_SCHEMA.COLUMNS`
GROUP BY
1;
--According to the results Id is the most common column across all tables. Now I will make sure it is in every table I have
SELECT
  table_name,
  SUM(CASE
      WHEN column_name ="Id" THEN 1
    ELSE
    0
  END
  ) AS has_id_column
FROM `portfolioproject-449608.FitBit_Data.INFORMATION_SCHEMA.COLUMNS`
GROUP BY 1
ORDER BY 1 ASC;
--Only 2 tables do not have Id column hourly_intensities and hourly_steps
---- This query checks to make sure that each table has a column of a date or time related type
SELECT
  table_name,
  SUM(CASE
      WHEN data_type IN ("TIMESTAMP", "DATETIME", "TIME", "DATE") THEN 1
    ELSE
    0
  END
  ) AS has_time_info
FROM `portfolioproject-449608.FitBit_Data.INFORMATION_SCHEMA.COLUMNS`
WHERE
  data_type IN("TIMESTAMP", "DATETIME","DATE")
GROUP BY 1
HAVING has_time_info = 0;
-- As I have columns of the type DATETIME, TIMESTAMP, or DATE, this query will check for their names
SELECT
  CONCAT(table_catalog,".",table_schema,".",table_name) AS table_path,
  table_name,
  column_name
FROM `portfolioproject-449608.FitBit_Data.INFORMATION_SCHEMA.COLUMNS`
WHERE
  data_type IN("TIMESTAMP", "DATETIME","DATE");
--This query checks to see if the column name has any of the keywords below:
-- date, minute, daily, hourly, day, seconds
SELECT 
  table_name,
  column_name
FROM
  `portfolioproject-449608.FitBit_Data.INFORMATION_SCHEMA.COLUMNS`
WHERE
  REGEXP_CONTAINS(LOWER(column_name), "date|minute|daily|hourly|day|seconds");
--Here I want to check if the column ActivityDate follows a particular pattern, in other words if it is a timestamp column
SELECT
  ActivityDate,
  REGEXP_CONTAINS(STRING(ActivityDate), r'^\d{4}-\d{1,2}-\d{1,2}[T ]\d{1,2}:\d{1,2}:\d{1,2}(\.\d{1,6})? *(([+-]\d{1,2}(:\d{1,2})?)|Z|UTC)?$') AS is_timestamp
FROM `portfolioproject-449608.FitBit_Data.daily_activity_merged`
LIMIT 5;
--I want to quickly check if all columns follow the timestamp pattern, so I take the minimum value of the boolean expression across the entire table
SELECT
  CASE
    WHEN MIN(REGEXP_CONTAINS(STRING(ActivityDate), r'^\d{4}-\d{1,2}-\d{1,2}[T ]\d{1,2}:\d{1,2}:\d{1,2}(\.\d{1,6})? *(([+-]\d{1,2}(:\d{1,2})?)|Z|UTC)?$')) = TRUE THEN
  "Valid"
  ELSE
  "Not Valid"
END
  AS valid_test
FROM `portfolioproject-449608.FitBit_Data.daily_activity_merged`
--I want to do an analysis based upon daily data, this could help us to find tables that might be at the day level
SELECT
  DISTINCT table_name
FROM `portfolioproject-449608.FitBit_Data.INFORMATION_SCHEMA.COLUMNS`
WHERE 
  REGEXP_CONTAINS(LOWER(table_name),"day|daily");
--Now I want to check the columns shared across the tables
SELECT
  column_name,
  data_type,
  COUNT(table_name) AS table_count
FROM `portfolioproject-449608.FitBit_Data.INFORMATION_SCHEMA.COLUMNS`
WHERE
  REGEXP_CONTAINS(LOWER(table_name), "day|daily")
GROUP BY
  1,
  2;
--make certain that the data types align between tables
SELECT
  column_name,
  table_name,
  data_type,
FROM `portfolioproject-449608.FitBit_Data.INFORMATION_SCHEMA.COLUMNS`
WHERE
  REGEXP_CONTAINS(LOWER(table_name), "day|daily")
  AND column_name IN(
  SELECT
    column_name
  FROM `portfolioproject-449608.FitBit_Data.INFORMATION_SCHEMA.COLUMNS`
  WHERE 
    REGEXP_CONTAINS(LOWER(table_name),"day|daily")
  GROUP BY 1
  HAVING 
    COUNT(table_name) >= 2
  )
ORDER BY
  1;
---- Now I'd like to do an analysis based upon the time of day and day of the week
-- I will do this at a person level such that I smooth over anomalous days for an individual
WITH
  user_dow_summary AS (
  SELECT
    Id,
    FORMAT_TIMESTAMP("%w", ActivityHour) AS dow_number,
    FORMAT_TIMESTAMP("%A", ActivityHour) AS day_of_week,
    CASE
      WHEN FORMAT_TIMESTAMP("%A", ActivityHour) IN ("Sunday","Saturday") THEN "Weekend"
      WHEN FORMAT_TIMESTAMP("%A", ActivityHour) NOT IN ("Sunday","Saturday") THEN "Weekday"
    ELSE
    "ERROR"
  END
    AS part_of_week,
    CASE
      WHEN TIME(ActivityHour) BETWEEN TIME(6,0,0) AND TIME(12,0,0) THEN "Morning"
      WHEN TIME(ActivityHour) BETWEEN TIME(12,0,0) AND TIME(18,0,0) THEN "Afternoon"
      WHEN TIME(ActivityHour) BETWEEN TIME(18,0,0) AND TIME(21,0,0) THEN "Evening"
      WHEN TIME(ActivityHour) >= TIME(21,0,0) OR TIME(TIMESTAMP_TRUNC(ActivityHour, MINUTE)) <= TIME(6,0,0) THEN "Night"
    ELSE
    "ERROR"
  END
    AS time_of_day,
    SUM(TotalIntensity) AS total_intensity,
    SUM(AverageIntensity) AS total_average_intensity,
    AVG(AverageIntensity) AS average_intensity,
    MAX(AverageIntensity) AS max_intensity,
    MIN(AverageIntensity) AS min_intensity,
  FROM `portfolioproject-449608.FitBit_Data.hourly_intensities`
  GROUP BY 1, 2, 3, 4, 5),
  intensity_deciles AS (
  SELECT
    DISTINCT dow_number, 
    part_of_week,
    day_of_week,
    time_of_day,
    ROUND(PERCENTILE_CONT(total_intensity, 0.1) OVER (PARTITION BY dow_number, part_of_week, day_of_week, time_of_day), 4) AS total_intensity_first_decile,
    ROUND(PERCENTILE_CONT(total_intensity, 0.2) OVER (PARTITION BY dow_number, part_of_week, day_of_week, time_of_day), 4) AS total_intensity_second_decile,
    ROUND(PERCENTILE_CONT(total_intensity, 0.3) OVER (PARTITION BY dow_number, part_of_week, day_of_week, time_of_day), 4) AS total_intensity_third_decile,
    ROUND(PERCENTILE_CONT(total_intensity, 0.4) OVER (PARTITION BY dow_number, part_of_week, day_of_week, time_of_day), 4) AS total_intensity_fourth_decile,
    ROUND(PERCENTILE_CONT(total_intensity, 0.5) OVER (PARTITION BY dow_number, part_of_week, day_of_week, time_of_day), 4) AS total_intensity_fifth_decile,
    ROUND(PERCENTILE_CONT(total_intensity, 0.6) OVER (PARTITION BY dow_number, part_of_week, day_of_week, time_of_day), 4) AS total_intensity_sixth_decile,
    ROUND(PERCENTILE_CONT(total_intensity, 0.7) OVER (PARTITION BY dow_number, part_of_week, day_of_week, time_of_day), 4) AS total_intensity_seventh_decile,
    ROUND(PERCENTILE_CONT(total_intensity, 0.8) OVER (PARTITION BY dow_number, part_of_week, day_of_week, time_of_day), 4) AS total_intensity_eight_decile,
    ROUND(PERCENTILE_CONT(total_intensity, 0.9) OVER (PARTITION BY dow_number, part_of_week, day_of_week, time_of_day), 4) AS total_intensity_ninth_decile,
  FROM
    user_dow_summary ),
  basic_summary AS (
  SELECT
    part_of_week,
    day_of_week,
    time_of_day,
    SUM(total_intensity) AS total_total_intensity,
    AVG(total_intensity) AS average_total_intensity,
    SUM(total_average_intensity) AS total_total_average_intensity,
    AVG(total_average_intensity) AS average_total_average_intensity,
    SUM(average_intensity) AS total_average_intensity,
    AVG(average_intensity) AS average_average_intensity,
    AVG(max_intensity) AS average_max_intensity,
    AVG(min_intensity) AS average_min_intensity
  FROM user_dow_summary
  GROUP BY 1, dow_number, 2, 3)
SELECT *
FROM basic_summary
LEFT JOIN intensity_deciles
USING (part_of_week, day_of_week, time_of_day)
ORDER BY 1, dow_number, 2,
  CASE
    WHEN time_of_day = "Morning" then 0
    WHEN time_of_day = "Afternoon" then 1
    WHEN time_of_day = "Evening" then 2
    WHEN time_of_day = "Night" then 3
END;
--Considering sleep related ads, products, I want to know total sleep duration, Sleep Start & End Time Trends, Sleep Variability(potential target customers)
WITH sleep_summary AS(
  SELECT
    Id,
    DATE(MIN(date)) AS sleep_date,
    TIME(MIN(date)) AS sleep_start_time,
    TIME(MAX(date)) AS sleep_end_time,
    ROUND(TIMESTAMP_DIFF(MAX(date), MIN(date), MINUTE) / 60.0, 2) AS total_sleep_hours
  FROM `portfolioproject-449608.FitBit_Data.minute_sleep`
  WHERE value = 1
  GROUP BY Id,DATE(date))
SELECT
  Id,
  sleep_date,
  sleep_start_time,
  sleep_end_time,
  sleep_summary.total_sleep_hours,
  CASE
    WHEN total_sleep_hours < 6 THEN "Sleep Deficit"
    WHEN total_sleep_hours BETWEEN 6 AND 8 THEN "Optimal Sleep"
    WHEN total_sleep_hours > 8 THEN "Excess Sleep"
  END AS sleep_category
FROM sleep_summary
ORDER BY sleep_date DESC, sleep_start_time;
--Now I want to see how many users are in Excess, Sleep Deficit and Optimal Sleep categories, to see if there is even a point in making sleep related products.
WITH sleep_summary AS(
  SELECT
    Id,
    DATE(MIN(date)) AS sleep_date,
    TIME(MIN(date)) AS sleep_start_time,
    TIME(MAX(date)) AS sleep_end_time,
    ROUND(TIMESTAMP_DIFF(MAX(date), MIN(date), MINUTE) / 60.0, 2) AS total_sleep_hours
  FROM `portfolioproject-449608.FitBit_Data.minute_sleep`
  WHERE value = 1
  GROUP BY Id,DATE(date))
SELECT
  sleep_category,
  COUNT(DISTINCT Id) AS user_count
FROM (
  SELECT
    Id,
    total_sleep_hours,
    CASE
      WHEN total_sleep_hours < 6 THEN "Sleep Deficit"
      WHEN total_sleep_hours BETWEEN 6 AND 8 THEN "Optimal Sleep"
      WHEN total_sleep_hours > 8 THEN "Excess Sleep"
    END AS sleep_category
  FROM sleep_summary
)
GROUP BY sleep_category
ORDER BY sleep_category;
--I want to know on how many hours have users slept on each day of the week to see if there is a pattern with sleep habits depending on the weekend or weekday 
WITH sleep_summary AS (
  SELECT
    Id,
    SleepDay,
    FORMAT_TIMESTAMP("%A", SleepDay) AS day_of_week,
    TotalMinutesAsleep,  -- Total minutes asleep per day
    ROUND(TotalMinutesAsleep / 60.0, 2) AS total_sleep_hours  -- Convert minutes to hours
  FROM `portfolioproject-449608.FitBit_Data.sleepday`
)

SELECT
  day_of_week,
  AVG(total_sleep_hours) AS average_sleep_hours,
  MIN(total_sleep_hours) AS min_sleep_hours,
  MAX(total_sleep_hours) AS max_sleep_hours,
  COUNT(DISTINCT Id) AS number_of_users
FROM sleep_summary
GROUP BY day_of_week
ORDER BY
  CASE
    WHEN day_of_week = 'Sunday' THEN 1
    WHEN day_of_week = 'Monday' THEN 2
    WHEN day_of_week = 'Tuesday' THEN 3
    WHEN day_of_week = 'Wednesday' THEN 4
    WHEN day_of_week = 'Thursday' THEN 5
    WHEN day_of_week = 'Friday' THEN 6
    WHEN day_of_week = 'Saturday' THEN 7
  END;
