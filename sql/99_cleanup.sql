/* =====================================================================
   後片付け：ハンズオンの最後に実行してください
   ---------------------------------------------------------------------
   ・ウェアハウスは60秒で自動停止するので、何もしなくて大丈夫です。
   ・Dynamic Table は止めないと、1分ごとに変更の確認を続けます。
   ・CoWork のエージェントは、質問されたときだけ動きます。
   ===================================================================== */

USE ROLE ACCOUNTADMIN;

-- ① Dynamic Table を停止する（第3章で作ったもの）
ALTER DYNAMIC TABLE IF EXISTS CONSTRUCTION_HOL.RAW.SITE_MACHINE_IDLE SUSPEND;

-- ② Task を停止する（作成直後から停止状態ですが、念のため）
ALTER TASK IF EXISTS CONSTRUCTION_HOL.RAW.MACHINE_IDLE_DAILY_TASK SUSPEND;

-- 確認：scheduling_state が SUSPENDED になっていること
SHOW DYNAMIC TABLES IN SCHEMA CONSTRUCTION_HOL.RAW;
SHOW TASKS IN SCHEMA CONSTRUCTION_HOL.RAW;

-- ③ もう一度試したいときは、次の文で Dynamic Table を再開できます
-- ALTER DYNAMIC TABLE CONSTRUCTION_HOL.RAW.SITE_MACHINE_IDLE RESUME;


/* ---------------------------------------------------------------------
   ここから下は、すべて削除したいとき（トライアルを返す前など）だけ実行します。
   ※ ハンズオンの最後は、ここより上だけを実行してください。
   ※ 一度削除すると元に戻せません。内容を確認してから実行してください。
   --------------------------------------------------------------------- */
ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT DROP AGENT CONSTRUCTION_HOL.RAW.CONSTRUCTION_AGENT;
DROP DATABASE IF EXISTS CONSTRUCTION_HOL;
DROP WAREHOUSE IF EXISTS ETL_WH;
DROP WAREHOUSE IF EXISTS BI_WH;
DROP WAREHOUSE IF EXISTS SETUP_WH;
DROP RESOURCE MONITOR IF EXISTS HOL_MONITOR;
DROP ROLE IF EXISTS BRANCH_TOKYO_ROLE;
DROP ROLE IF EXISTS BRANCH_OSAKA_ROLE;
DROP ROLE IF EXISTS HR_ROLE;
