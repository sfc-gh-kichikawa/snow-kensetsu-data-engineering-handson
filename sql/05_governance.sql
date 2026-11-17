/* =====================================================================
   第5章　13:00 守りの運用
   ---------------------------------------------------------------------
   人事部「給与の列は、人事部以外には見せないでほしい」
   内部監査室「来週の監査で、権限とアクセスの記録を出してください」

     ① うっかり削除しても戻せる（UNDROP）
     ② 本番と同じデータの開発環境を一瞬で作る（ゼロコピークローン）
     ③ 支店ごとに見える行を変える（行アクセスポリシー）
     ④ 給与の列を隠す（マスキングポリシー）
     ⑤ 監査の準備（権限の一覧、ある時点のデータの再現）
     ⑥ 費用の上限を決める（リソースモニター）
   ===================================================================== */

USE ROLE ACCOUNTADMIN;
USE SCHEMA CONSTRUCTION_HOL.RAW;
USE WAREHOUSE BI_WH;

-- 第5章では、ロールを切り替えて、見えるデータが変わることを確かめます。
-- ロールは「権限のまとまり」です。今日は準備スクリプトで次の3つを用意しています。
--   BRANCH_TOKYO_ROLE：東京支店の担当者 / BRANCH_OSAKA_ROLE：大阪支店の担当者 / HR_ROLE：人事部
-- 各ロールが BI_WH を使って SQL を実行できるようにしておきます
GRANT USAGE ON WAREHOUSE BI_WH TO ROLE BRANCH_TOKYO_ROLE;
GRANT USAGE ON WAREHOUSE BI_WH TO ROLE BRANCH_OSAKA_ROLE;
GRANT USAGE ON WAREHOUSE BI_WH TO ROLE HR_ROLE;

-- ---------------------------------------------------------------------
-- ① うっかり削除
--    Snowflake は、削除したテーブルを一定期間（標準は1日）保持しています（Time Travel）。
--    その間なら、UNDROP ですぐに元に戻せます。バックアップから戻す作業は要りません。
-- ---------------------------------------------------------------------
SELECT COUNT(*) FROM COST_DETAIL;     -- 500,000行

DROP TABLE COST_DETAIL;               -- 敢えてテーブルを削除します。

SELECT COUNT(*) FROM COST_DETAIL;     -- エラーになります（テーブルがない）

UNDROP TABLE COST_DETAIL;             -- 1秒で元に戻ります

SELECT COUNT(*) FROM COST_DETAIL;     -- 500,000行に戻っています


-- ---------------------------------------------------------------------
-- ② 開発環境を一瞬で作る
--    ゼロコピークローンは、データをコピーせずに、同じ中身のテーブルを作る機能です。
--    データの量に関係なく数秒で終わり、作った直後はストレージの料金も増えません。
--    複製した側を変更しても、本番のテーブルには影響しません。
-- ---------------------------------------------------------------------
-- 【CoCoへの指示】
--   COST_DETAIL を、新しい DEV スキーマにゼロコピークローンしてください。

-- 複製した側の件数（本番と同じ）
SELECT COUNT(*) FROM CONSTRUCTION_HOL.DEV.COST_DETAIL;


-- ---------------------------------------------------------------------
-- ③ 支店ごとに見える行を変える
--    行アクセスポリシーは、「どのロールに、どの行を見せるか」をテーブルに設定する機能です。
--    BRANCH_ROLE_MAP は、ロールと支店の対応表です（準備スクリプトで作成済み）。
--    同じ SQL を実行しても、ロールによって結果が変わります。ビューを支店ごとに作る必要はありません。
-- ---------------------------------------------------------------------
-- 【CoCoへの指示】
--   BRANCH_ROLE_MAP を使って、RAW スキーマの COST_DETAIL に行アクセスポリシー BRANCH_RAP を設定してください。支店のロールには自分の支店の行だけ、ACCOUNTADMIN にはすべての行が見えるようにします。

-- 同じSQLを、ロールを変えて実行してみましょう
-- 東京のロールでは東京支店だけ、大阪のロールでは大阪支店だけ、ACCOUNTADMIN では全支店が表示されます
USE ROLE BRANCH_TOKYO_ROLE;
SELECT BRANCH, COUNT(*) AS rows_visible, SUM(AMOUNT) AS total_cost FROM CONSTRUCTION_HOL.RAW.COST_DETAIL GROUP BY BRANCH;

USE ROLE BRANCH_OSAKA_ROLE;
SELECT BRANCH, COUNT(*) AS rows_visible, SUM(AMOUNT) AS total_cost FROM CONSTRUCTION_HOL.RAW.COST_DETAIL GROUP BY BRANCH;

USE ROLE ACCOUNTADMIN;
SELECT BRANCH, COUNT(*) AS rows_visible, SUM(AMOUNT) AS total_cost FROM CONSTRUCTION_HOL.RAW.COST_DETAIL GROUP BY BRANCH;


-- ---------------------------------------------------------------------
-- ④ 給与の列を隠す
--    マスキングポリシーは、列の値をロールによって隠す機能です。
--    行アクセスポリシーが「行」を絞るのに対して、マスキングポリシーは「列の値」を隠します。
--    管理者のロール（ACCOUNTADMIN）でも、設定したロール以外には見せないことができます。
-- ---------------------------------------------------------------------
-- 【CoCoへの指示】
--   EMPLOYEES の MONTHLY_SALARY に、HR_ROLE 以外には NULL を返すマスキングポリシー SALARY_MASK を設定してください。

USE ROLE HR_ROLE;
SELECT EMPLOYEE_ID, EMPLOYEE_NAME, DEPARTMENT, MONTHLY_SALARY FROM CONSTRUCTION_HOL.RAW.EMPLOYEES LIMIT 5;

USE ROLE ACCOUNTADMIN;
SELECT EMPLOYEE_ID, EMPLOYEE_NAME, DEPARTMENT, MONTHLY_SALARY FROM CONSTRUCTION_HOL.RAW.EMPLOYEES LIMIT 5;
-- ↑ 管理者のロールでも、給与は見えません


-- ---------------------------------------------------------------------
-- ⑤ 監査の準備
--    監査でよく聞かれる「誰が見られるのか」「どんな制限がかかっているのか」を、
--    CoCo に日本語で頼んで表にしてもらいます。
--    Time Travel を使うと、過去のある時点のデータもそのまま SELECT できます。
-- ---------------------------------------------------------------------
-- 【CoCoへの指示】
--   EMPLOYEES を見られるロールと、設定されているポリシーを、監査用の表にまとめてください。

-- 【CoCoへの指示】
--   Time Travel で、10分前の RAW スキーマの COST_DETAIL の支店別原価合計を出してください。


-- ---------------------------------------------------------------------
-- ⑥ 費用の上限を決める
--    リソースモニターは、ウェアハウスが使うクレジット（Snowflake の料金の単位）に上限を設ける機能です。
--    上限に近づいたら通知し、上限に達したらウェアハウスを止められます。使いすぎを防げます。
-- ---------------------------------------------------------------------
-- 【CoCoへの指示】
--   1日5クレジットを上限とするリソースモニター HOL_MONITOR を作り、ETL_WH と BI_WH に設定してください。80%で通知、100%で停止します。

SHOW RESOURCE MONITORS;
