/* =====================================================================
   救済用の正解SQL（第1章〜第3章）
   CoCo の結果がうまくいかなかったとき、遅れを取り戻したいときに使います。
   ===================================================================== */

USE ROLE ACCOUNTADMIN;
USE SCHEMA CONSTRUCTION_HOL.RAW;

-- =====================================================================
-- 第1章 ウェアハウスを作る
-- =====================================================================
CREATE WAREHOUSE IF NOT EXISTS ETL_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'ETL用';
CREATE WAREHOUSE IF NOT EXISTS BI_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'BI用';

-- =====================================================================
-- 第2章 古いSQLを Snowflake 用に直す
-- =====================================================================
USE WAREHOUSE BI_WH;

-- 【指示1】の結果の例（T-SQL → Snowflake）
SELECT
    p.BRANCH                                                     AS "支店",
    p.PROJECT_NAME                                               AS "案件名",
    COALESCE(SUM(c.AMOUNT), 0)                                   AS "原価合計",
    p.CONTRACT_AMOUNT                                            AS "契約金額",
    COALESCE(SUM(c.AMOUNT), 0) * 100.0 / NULLIF(p.CONTRACT_AMOUNT, 0) AS "原価率",
    TO_CHAR(CURRENT_DATE(), 'YYYY/MM/DD')                        AS "集計日"
FROM CONSTRUCTION_HOL.RAW.PROJECTS AS p
LEFT JOIN CONSTRUCTION_HOL.RAW.COST_DETAIL AS c
    ON p.PROJECT_ID = c.PROJECT_ID
WHERE DATEDIFF(day, c.RECORDED_DATE, CURRENT_DATE()) <= 365
GROUP BY p.BRANCH, p.PROJECT_NAME, p.CONTRACT_AMOUNT
ORDER BY "原価率" DESC
LIMIT 10;

-- 【指示2】の結果の例（東京支店・2026年度に絞る）
SELECT
    p.BRANCH                                                     AS "支店",
    p.PROJECT_NAME                                               AS "案件名",
    COALESCE(SUM(c.AMOUNT), 0)                                   AS "原価合計",
    p.CONTRACT_AMOUNT                                            AS "契約金額",
    COALESCE(SUM(c.AMOUNT), 0) * 100.0 / NULLIF(p.CONTRACT_AMOUNT, 0) AS "原価率",
    TO_CHAR(CURRENT_DATE(), 'YYYY/MM/DD')                        AS "集計日"
FROM CONSTRUCTION_HOL.RAW.PROJECTS AS p
LEFT JOIN CONSTRUCTION_HOL.RAW.COST_DETAIL AS c
    ON p.PROJECT_ID = c.PROJECT_ID
WHERE p.BRANCH = '東京支店'
  AND c.RECORDED_DATE BETWEEN '2026-04-01' AND '2027-03-31'
GROUP BY p.BRANCH, p.PROJECT_NAME, p.CONTRACT_AMOUNT
ORDER BY "原価率" DESC;

-- 【指示3】の結果の例（BRANCH が PROJECTS と COST_DETAIL の両方にあり、どちらか曖昧なのがエラーの原因）
SELECT
    p.BRANCH,
    p.PROJECT_NAME,
    SUM(c.AMOUNT) AS TOTAL_COST
FROM PROJECTS p
JOIN COST_DETAIL c
    ON p.PROJECT_ID = c.PROJECT_ID
GROUP BY p.BRANCH, p.PROJECT_NAME;

-- =====================================================================
-- 第3章 COPY INTO → Dynamic Table → Task
-- =====================================================================
USE WAREHOUSE ETL_WH;

-- ① COPY INTO
CREATE OR REPLACE FILE FORMAT CONSTRUCTION_HOL.RAW.CSV_WITH_HEADER
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"';

COPY INTO CONSTRUCTION_HOL.RAW.MACHINE_LOG
  FROM @CONSTRUCTION_HOL.RAW.IICS_LANDING/machine_log/
  FILE_FORMAT = (FORMAT_NAME = 'CONSTRUCTION_HOL.RAW.CSV_WITH_HEADER');

SELECT COUNT(*) FROM CONSTRUCTION_HOL.RAW.MACHINE_LOG;   -- 72,000行

-- ② Dynamic Table
CREATE OR REPLACE DYNAMIC TABLE CONSTRUCTION_HOL.RAW.SITE_MACHINE_IDLE
  TARGET_LAG = '1 minute'
  WAREHOUSE = ETL_WH
  REFRESH_MODE = INCREMENTAL   -- 指定しないと、この集計は FULL に自動で決まる
  COMMENT = '現場×工程×重機の種類×1時間ごとの重機の待機状況'
AS
SELECT
    p.PROJECT_ID,
    p.PROJECT_NAME,
    p.BRANCH,
    pr.PROCESS_NAME,
    m.MACHINE_TYPE,
    DATE_TRUNC('HOUR', l.MEASURED_AT)                                     AS HOUR_SLOT,
    COUNT(*)                                                              AS TOTAL_MINUTES,
    COUNT_IF(l.STATUS = '待機')                                           AS IDLE_MINUTES,
    ROUND(COUNT_IF(l.STATUS = '待機') / COUNT(*) * 100, 1)                AS IDLE_RATE_PCT,
    ROUND(SUM(IFF(l.STATUS = '待機', m.HOURLY_RATE / 60, 0)))             AS IDLE_LOSS_YEN
FROM CONSTRUCTION_HOL.RAW.MACHINE_LOG l
JOIN CONSTRUCTION_HOL.RAW.MACHINES   m  ON l.MACHINE_ID = m.MACHINE_ID
JOIN CONSTRUCTION_HOL.RAW.PROJECTS   p  ON m.PROJECT_ID = p.PROJECT_ID
JOIN CONSTRUCTION_HOL.RAW.PROCESSES  pr ON m.PROCESS_ID = pr.PROCESS_ID
GROUP BY p.PROJECT_ID, p.PROJECT_NAME, p.BRANCH, pr.PROCESS_NAME, m.MACHINE_TYPE, DATE_TRUNC('HOUR', l.MEASURED_AT);

-- ④ Task（毎朝7時に前日の日報を作る）
CREATE TABLE IF NOT EXISTS CONSTRUCTION_HOL.RAW.MACHINE_IDLE_DAILY (
  REPORT_DATE    DATE          COMMENT '対象日',
  PROJECT_ID     VARCHAR       COMMENT '案件ID',
  PROJECT_NAME   VARCHAR       COMMENT '案件名',
  BRANCH         VARCHAR       COMMENT '担当支店',
  IDLE_MINUTES   NUMBER        COMMENT '待機時間（分）',
  IDLE_LOSS_YEN  NUMBER        COMMENT '待機による損失（円）',
  CREATED_AT     TIMESTAMP_NTZ COMMENT '作成日時'
) COMMENT = '重機の待機の日報';

CREATE OR REPLACE TASK CONSTRUCTION_HOL.RAW.MACHINE_IDLE_DAILY_TASK
  WAREHOUSE = ETL_WH
  SCHEDULE = 'USING CRON 0 7 * * * Asia/Tokyo'
  COMMENT = '毎朝7時に前日の重機の待機による損失を集計する'
AS
INSERT INTO CONSTRUCTION_HOL.RAW.MACHINE_IDLE_DAILY
SELECT
    DATEADD(day, -1, CURRENT_DATE()),
    p.PROJECT_ID,
    p.PROJECT_NAME,
    p.BRANCH,
    COUNT_IF(l.STATUS = '待機'),
    ROUND(SUM(IFF(l.STATUS = '待機', m.HOURLY_RATE / 60, 0))),
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
FROM CONSTRUCTION_HOL.RAW.MACHINE_LOG l
JOIN CONSTRUCTION_HOL.RAW.MACHINES m ON l.MACHINE_ID = m.MACHINE_ID
JOIN CONSTRUCTION_HOL.RAW.PROJECTS p ON m.PROJECT_ID = p.PROJECT_ID
WHERE l.MEASURED_AT >= DATEADD(day, -1, CURRENT_DATE())
  AND l.MEASURED_AT <  CURRENT_DATE()
GROUP BY p.PROJECT_ID, p.PROJECT_NAME, p.BRANCH;

EXECUTE TASK CONSTRUCTION_HOL.RAW.MACHINE_IDLE_DAILY_TASK;
