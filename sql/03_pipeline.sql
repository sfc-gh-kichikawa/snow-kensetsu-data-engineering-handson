/* =====================================================================
   第3章　11:00 現場からデータが届く
   ---------------------------------------------------------------------
   工事部長「渋谷の現場の工程が遅れている。機械が遊んでいないか？」

   IICS（Informatica）から、重機の稼働ログのCSVが内部ステージに届きました。
     ① COPY INTO でテーブルにロードする
     ② Dynamic Table で「現場×工程×時間帯の待機率」を自動で最新化する
     ③ 新しいデータが届いたときの動きを確かめる
     ④ Task で毎朝7時の日報を作る
   ===================================================================== */

USE SCHEMA CONSTRUCTION_HOL.RAW;
USE WAREHOUSE ETL_WH;

-- ---------------------------------------------------------------------
-- ① 届いたファイルを確認して、COPY INTO でロードする
-- ---------------------------------------------------------------------
-- ステージは、テーブルに取り込む前のファイルを置いておく場所です。名前の前に @ を付けて表します。
-- IICS の Snowflake 用コネクタは、標準の方式では、データをファイルとしてステージに置きます。
-- 届いたファイルの一覧（4本：前日分を6時間ごとのバッチで送った想定）
LIST @IICS_LANDING;

-- 【CoCoへの指示】
--   @IICS_LANDING のCSVを MACHINE_LOG にロードする COPY INTO を、①の下に追記してください。実行はしないでください。

-- COPY INTO は、ステージのファイルをテーブルに取り込む SQL です。
-- CoCo はファイルの中身を確かめて、ヘッダー行の読み飛ばしなどの設定も書いてくれます。

-- ロードできた件数を確認（重機50台 × 1日1,440分 = 72,000行になります）
SELECT COUNT(*) AS row_count FROM MACHINE_LOG;

-- もう一度、CoCo が作った COPY INTO を実行してみてください。
-- → 2回目は「ロードしたファイル 0本」になります（二重に取り込まれない）
--   Snowflake は、どのファイルを取り込んだかを64日間覚えています。
--   IICS のジョブを再実行しても、同じファイルが二重に入ることはありません。


-- ---------------------------------------------------------------------
-- ② Dynamic Table を作る
--    Dynamic Table は、「どう集計したいか」を SELECT 文で書くだけで、
--    元のデータが変わると Snowflake が自動で集計を最新にしてくれるテーブルです。
--      ・TARGET_LAG：元のデータからどのくらい遅れてもよいか（今回は1分）
--      ・REFRESH_MODE = INCREMENTAL：毎回すべて作り直さず、増えた分だけ計算する
--    この下に CoCo が SQL を書き込みます。
-- ---------------------------------------------------------------------
-- 【CoCoへの指示】
--   MACHINE_LOG・MACHINES・PROCESSES・PROJECTS から、現場・工程・重機の種類・1時間ごとの待機率、待機時間、損失（待機時間 × 時間単価 ÷ 60）を出す Dynamic Table 「SITE_MACHINE_IDLE」 を、②の下に追記してください。TARGET_LAG は1分、REFRESH_MODE は INCREMENTAL、ウェアハウスは ETL_WH です。列は PROJECT_ID、PROJECT_NAME、BRANCH、PROCESS_NAME、MACHINE_TYPE、HOUR_SLOT、TOTAL_MINUTES、IDLE_MINUTES、IDLE_RATE_PCT、IDLE_LOSS_YEN にしてください。実行はしないでください。




-- 中身を確認（待機率の高い順）
SELECT * FROM SITE_MACHINE_IDLE ORDER BY IDLE_RATE_PCT DESC LIMIT 20;


-- ---------------------------------------------------------------------
-- ③ 新しいデータが届いたら？
--    「渋谷の現場のクレーンから、今、待機の記録が届いた」という想定です。
--    次の INSERT をそのまま実行してください（全員が同じ結果になるように用意しています）。
-- ---------------------------------------------------------------------
INSERT INTO MACHINE_LOG (MACHINE_ID, MEASURED_AT, STATUS, FUEL_LEVEL)
SELECT
    IFF(n < 30, 'M001', 'M002'),                                   -- M001 タワークレーン / M002 クローラークレーン（渋谷）
    DATEADD(minute, -MOD(n, 30), CURRENT_TIMESTAMP())::TIMESTAMP_NTZ,
    '待機',
    60.0
FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS n FROM TABLE(GENERATOR(ROWCOUNT => 60)));

-- Dynamic Table には何もしていません。元のデータ（MACHINE_LOG）に行を足しただけです。
-- 待っている間に、左のデータベース画面で SITE_MACHINE_IDLE を開き、「グラフ」タブで
-- どのテーブルから作られているかを見てみましょう。

-- 1分ほど待ってから、もう一度見てみましょう（渋谷の現場の今の時間帯が上位に来ます）
SELECT PROJECT_NAME, PROCESS_NAME, MACHINE_TYPE, HOUR_SLOT, IDLE_RATE_PCT, IDLE_MINUTES, IDLE_LOSS_YEN
FROM SITE_MACHINE_IDLE
ORDER BY HOUR_SLOT DESC, IDLE_RATE_PCT DESC
LIMIT 10;

-- 待てないときは、手動で更新できます
-- ALTER DYNAMIC TABLE SITE_MACHINE_IDLE REFRESH;

-- 更新の履歴：データが届いた直後だけ更新され、それ以外は NO_DATA になります。
--   REFRESH_ACTION の見方：
--     INCREMENTAL … 増えた分だけ計算して更新した
--     NO_DATA     … 元のデータが変わっていないので、何もしなかった（ウェアハウスも動かない）
--   1分ごとに確認していても、変化がなければウェアハウスの料金はかかりません。
SELECT NAME, REFRESH_ACTION, STATE, DATA_TIMESTAMP, REFRESH_START_TIME, REFRESH_END_TIME
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(NAME => 'CONSTRUCTION_HOL.RAW.SITE_MACHINE_IDLE'))
ORDER BY DATA_TIMESTAMP DESC
LIMIT 20;


-- ---------------------------------------------------------------------
-- ④ Task で毎朝7時の日報を作る
--    Task は、決まった時刻に SQL を動かす、Snowflake の中のスケジューラーです。
--    別のスケジューラーやサーバーを用意しなくても、定時の集計を Snowflake の中だけで動かせます。
--    この下に CoCo が SQL を書き込みます。
-- ---------------------------------------------------------------------
-- 【CoCoへの指示】
--   毎朝7時（日本時間）に、前日の現場ごとの待機時間と損失を MACHINE_IDLE_DAILY に追加する Task MACHINE_IDLE_DAILY_TASK を、④の下に追記してください。テーブルも作り、ウェアハウスは ETL_WH、列名は下の確認用SQLに合わせてください。実行はしないでください。




-- 明日の朝まで待てないので、今すぐ1回だけ実行します
EXECUTE TASK MACHINE_IDLE_DAILY_TASK;

-- 実行結果の確認（数十秒後に SUCCEEDED になります）
--   STATE の見方：EXECUTING＝実行中、SUCCEEDED＝成功、FAILED＝失敗（ERROR_MESSAGE に理由）
SELECT NAME, STATE, SCHEDULED_TIME, COMPLETED_TIME, ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'MACHINE_IDLE_DAILY_TASK'))
ORDER BY SCHEDULED_TIME DESC
LIMIT 5;

-- 日報の中身（日付の新しい順、損失の大きい順）
--   前日分の集計なので、③で足した「今日の」待機の記録は入りません。
SELECT * FROM MACHINE_IDLE_DAILY ORDER BY 1 DESC, IDLE_LOSS_YEN DESC;

-- Task の状態を確認します。state 列が「suspended（停止中）」になっています。
--   ・Task は、作っただけでは動きません。作った直後は停止中です。
--   ・毎朝7時に自動で動かすには、RESUME（再開）して「started（稼働中）」にします。
--   ・上で使った EXECUTE TASK は「今すぐ1回だけ動かす」命令で、毎朝のスケジュールは始まりません。
--   ・作った瞬間に勝手に動き出して、意図しない処理や費用が出ないための仕組みです。
SHOW TASKS LIKE 'MACHINE_IDLE_DAILY_TASK';

-- 本番で毎朝動かすときは、次を実行します（今日のハンズオンでは実行しません）
-- ALTER TASK MACHINE_IDLE_DAILY_TASK RESUME;    -- 毎朝7時の自動実行を始める
-- ALTER TASK MACHINE_IDLE_DAILY_TASK SUSPEND;   -- 自動実行を止める
