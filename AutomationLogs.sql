USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = N'RPADatabase')
BEGIN
    ALTER DATABASE RPADatabase SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE RPADatabase;
END
GO

CREATE DATABASE RPADatabase;
GO

USE RPADatabase;
GO

CREATE TABLE RPA_Telemetry (
    TaskID INT IDENTITY(1,1) PRIMARY KEY,
    TargetURL NVARCHAR(255),
    ExecutionStatus NVARCHAR(50),
    ItemsProcessed INT,
    ExecutionDate DATETIME DEFAULT GETDATE(),
    DurationSeconds FLOAT
);
GO

CREATE TABLE RPA_Payload (
    PayloadID INT IDENTITY(1,1) PRIMARY KEY,
    Quote_Text NVARCHAR(MAX),
    Author NVARCHAR(255),
    Tags NVARCHAR(MAX),
    Extracted_At DATETIME DEFAULT GETDATE()
);
GO

-- Retrieve all recorded automated executions ordered by the most recent run
SELECT * FROM RPA_Telemetry 
ORDER BY ExecutionDate DESC;

-- Fetch a sample of the most recently harvested payload records
SELECT TOP 100 * FROM RPA_Payload 
ORDER BY Extracted_At DESC;

-- Count the total number of pipeline executions logged in telemetry
SELECT COUNT(*) AS Total_Executions 
FROM RPA_Telemetry;

-- Calculate the total volume of data ingested into the payload table
SELECT COUNT(*) AS Total_Payload_Records 
FROM RPA_Payload;

-- Filter all telemetry logs where the pipeline execution failed
SELECT * FROM RPA_Telemetry 
WHERE ExecutionStatus = 'FAILED';

-- Extract all unique authors harvested in the payload data
SELECT DISTINCT Author 
FROM RPA_Payload 
ORDER BY Author ASC;

-- Calculate the average, minimum, and maximum duration of successful runs
SELECT 
    AVG(DurationSeconds) AS Avg_Duration, 
    MIN(DurationSeconds) AS Min_Duration, 
    MAX(DurationSeconds) AS Max_Duration 
FROM RPA_Telemetry 
WHERE ExecutionStatus = 'COMPLETED';

-- Find the total number of items processed grouped by execution status
SELECT 
    ExecutionStatus, 
    SUM(ItemsProcessed) AS Total_Items 
FROM RPA_Telemetry 
GROUP BY ExecutionStatus;

-- Identify the top 10 most prolific authors based on quote count
SELECT TOP 10 
    Author, 
    COUNT(*) AS Quote_Count 
FROM RPA_Payload 
GROUP BY Author 
ORDER BY Quote_Count DESC;

-- Retrieve the 5 longest execution runs in pipeline history
SELECT TOP 5 
    TaskID, 
    TargetURL, 
    DurationSeconds, 
    ExecutionDate 
FROM RPA_Telemetry 
ORDER BY DurationSeconds DESC;

-- Calculate the overall pipeline success rate percentage
SELECT 
    CAST(SUM(CASE WHEN ExecutionStatus = 'COMPLETED' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS Success_Rate 
FROM RPA_Telemetry;

-- Find the average number of items extracted per successful run
SELECT 
    AVG(ItemsProcessed) AS Avg_Items_Per_Run 
FROM RPA_Telemetry 
WHERE ExecutionStatus = 'COMPLETED';

-- Count how many payload records have missing or NONE tags
SELECT COUNT(*) AS Missing_Tags_Count 
FROM RPA_Payload 
WHERE Tags = 'NONE' OR Tags IS NULL;

-- Aggregate the total payload volume ingested per calendar day
SELECT 
    CAST(Extracted_At AS DATE) AS Ingestion_Date, 
    COUNT(*) AS Daily_Volume 
FROM RPA_Payload 
GROUP BY CAST(Extracted_At AS DATE) 
ORDER BY Ingestion_Date DESC;

-- Identify authors whose average quote text length exceeds 100 characters
SELECT 
    Author, 
    AVG(LEN(Quote_Text)) AS Avg_Quote_Length 
FROM RPA_Payload 
GROUP BY Author 
HAVING AVG(LEN(Quote_Text)) > 100;

-- Measure ingestion speed in records per second for each successful run
SELECT 
    TaskID, 
    ItemsProcessed, 
    DurationSeconds, 
    CAST(ItemsProcessed / NULLIF(DurationSeconds, 0) AS DECIMAL(10,2)) AS Records_Per_Second 
FROM RPA_Telemetry 
WHERE ExecutionStatus = 'COMPLETED' 
ORDER BY Records_Per_Second DESC;

-- Retrieve telemetry records that took longer than the historical average duration
SELECT 
    TaskID, 
    DurationSeconds 
FROM RPA_Telemetry 
WHERE DurationSeconds > (
    SELECT AVG(DurationSeconds) 
    FROM RPA_Telemetry 
    WHERE ExecutionStatus = 'COMPLETED'
);

-- Find runs where the status was marked complete but zero items were processed
SELECT 
    TaskID, 
    ExecutionDate 
FROM RPA_Telemetry 
WHERE ExecutionStatus = 'COMPLETED' 
  AND ItemsProcessed = 0;

-- Calculate the running cumulative total of processed items over time
SELECT 
    TaskID, 
    ExecutionDate, 
    ItemsProcessed, 
    SUM(ItemsProcessed) OVER(ORDER BY ExecutionDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS Cumulative_Volume 
FROM RPA_Telemetry 
WHERE ExecutionStatus = 'COMPLETED';

-- Rank execution runs by duration from longest to shortest using window functions
SELECT 
    TaskID, 
    DurationSeconds, 
    RANK() OVER(ORDER BY DurationSeconds DESC) AS Duration_Rank 
FROM RPA_Telemetry;

-- Calculate a 3-run moving average of pipeline execution latency
SELECT 
    TaskID, 
    ExecutionDate, 
    DurationSeconds, 
    AVG(DurationSeconds) OVER(ORDER BY ExecutionDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS Moving_Avg_Latency 
FROM RPA_Telemetry 
WHERE ExecutionStatus = 'COMPLETED';

-- Analyze hourly payload ingestion distribution to find the busiest hour of the day
SELECT 
    DATEPART(HOUR, Extracted_At) AS Hour_Of_Day, 
    COUNT(*) AS Payloads_Ingested 
FROM RPA_Payload 
GROUP BY DATEPART(HOUR, Extracted_At) 
ORDER BY Payloads_Ingested DESC;

-- Find the time difference in seconds between the current run and the previous run
SELECT 
    TaskID, 
    ExecutionDate, 
    DATEDIFF(SECOND, LAG(ExecutionDate) OVER(ORDER BY ExecutionDate), ExecutionDate) AS Seconds_Since_Last_Run 
FROM RPA_Telemetry;

-- Segment runs into efficiency tiers based on duration latency
SELECT 
    TaskID, 
    DurationSeconds, 
    CASE 
        WHEN DurationSeconds < 5 THEN 'Fast' 
        WHEN DurationSeconds BETWEEN 5 AND 15 THEN 'Normal' 
        ELSE 'Slow' 
    END AS Efficiency_Tier 
FROM RPA_Telemetry;

-- Retrieve the first payload record extracted for each unique author
WITH RankedPayloads AS (
    SELECT 
        PayloadID, 
        Author, 
        Extracted_At, 
        ROW_NUMBER() OVER(PARTITION BY Author ORDER BY Extracted_At ASC) as rn 
    FROM RPA_Payload
) 
SELECT 
    PayloadID, 
    Author, 
    Extracted_At 
FROM RankedPayloads 
WHERE rn = 1;

-- Compare daily items processed in telemetry against actual daily payload inserts to detect discrepancies
WITH DailyTelemetry AS (
    SELECT 
        CAST(ExecutionDate AS DATE) as Date, 
        SUM(ItemsProcessed) as Expected_Volume 
    FROM RPA_Telemetry 
    GROUP BY CAST(ExecutionDate AS DATE)
), 
DailyPayload AS (
    SELECT 
        CAST(Extracted_At AS DATE) as Date, 
        COUNT(*) as Actual_Volume 
    FROM RPA_Payload 
    GROUP BY CAST(Extracted_At AS DATE)
) 
SELECT 
    t.Date, 
    t.Expected_Volume, 
    p.Actual_Volume, 
    (t.Expected_Volume - p.Actual_Volume) AS Discrepancy 
FROM DailyTelemetry t 
LEFT JOIN DailyPayload p ON t.Date = p.Date;

-- Identify the target URL that yields the highest average records per second
SELECT 
    TargetURL, 
    AVG(CAST(ItemsProcessed / NULLIF(DurationSeconds, 0) AS DECIMAL(10,2))) AS Avg_Records_Per_Second 
FROM RPA_Telemetry 
WHERE ExecutionStatus = 'COMPLETED' 
GROUP BY TargetURL 
ORDER BY Avg_Records_Per_Second DESC;

-- Extract specific payload records containing the word 'life' in their tags
SELECT 
    PayloadID, 
    Quote_Text, 
    Tags 
FROM RPA_Payload 
WHERE Tags LIKE '%life%';

-- Map each payload entry to its closest preceding telemetry run ID based on chronological timestamps
SELECT 
    p.PayloadID, 
    p.Author, 
    p.Extracted_At, 
    (SELECT TOP 1 t.TaskID 
     FROM RPA_Telemetry t 
     WHERE t.ExecutionDate <= p.Extracted_At 
     ORDER BY t.ExecutionDate DESC) AS Correlated_TaskID 
FROM RPA_Payload p;

-- Comprehensive executive summary bridging aggregated daily metrics from both tables
WITH TelemetryStats AS (
    SELECT 
        CAST(ExecutionDate AS DATE) as Exec_Date, 
        COUNT(*) as Total_Runs, 
        AVG(DurationSeconds) as Avg_Duration 
    FROM RPA_Telemetry 
    GROUP BY CAST(ExecutionDate AS DATE)
), 
PayloadStats AS (
    SELECT 
        CAST(Extracted_At AS DATE) as Extr_Date, 
        COUNT(DISTINCT Author) as Unique_Authors, 
        COUNT(*) as Daily_Payload 
    FROM RPA_Payload 
    GROUP BY CAST(Extracted_At AS DATE)
) 
SELECT 
    t.Exec_Date, 
    t.Total_Runs, 
    CAST(t.Avg_Duration AS DECIMAL(10,2)) AS Avg_Duration_Sec, 
    p.Daily_Payload, 
    p.Unique_Authors 
FROM TelemetryStats t 
JOIN PayloadStats p ON t.Exec_Date = p.Extr_Date 
ORDER BY t.Exec_Date DESC;