/* =====================================================================
   Snowflake データエンジニアリング ハンズオン  準備スクリプト
   ---------------------------------------------------------------------
   ・題材：架空の建設会社「Snow建設」
   ・このスクリプトのデータは、すべて架空です。社名・人名・案件名・金額は
     実在の企業・人物・案件とは関係ありません。
   ・実行方法：Snowsight の Workspaces でこのファイルを開き、
     ロールを ACCOUNTADMIN にして「すべて実行」してください（数分かかります）。
   ・ハンズオン当日の朝（または前日）に実行してください。
     重機の稼働ログは「実行日の前日」の日付で作成されます。
   ===================================================================== */

USE ROLE ACCOUNTADMIN;

-- アカウントのタイムゾーンを日本時間にそろえる（「前日」「現在時刻」をずらさないため）
ALTER ACCOUNT SET TIMEZONE = 'Asia/Tokyo';
ALTER SESSION SET TIMEZONE = 'Asia/Tokyo';

-- ---------------------------------------------------------------------
-- 0. 準備用のウェアハウス（準備が終わったら自動で停止します）
-- ---------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS SETUP_WH
  WAREHOUSE_SIZE = 'SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = '準備スクリプト専用';
USE WAREHOUSE SETUP_WH;

-- ---------------------------------------------------------------------
-- 1. データベース・スキーマ
-- ---------------------------------------------------------------------
CREATE OR REPLACE DATABASE CONSTRUCTION_HOL COMMENT = 'ハンズオン用（架空データ）';
CREATE OR REPLACE SCHEMA CONSTRUCTION_HOL.RAW COMMENT = '基幹システム・IoT・監査ログの生データ';
USE SCHEMA CONSTRUCTION_HOL.RAW;

-- ---------------------------------------------------------------------
-- 2. 工事（土建）：工事案件
--    P001 渋谷みらいタワー新築工事 がストーリーの主役の現場です
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE PROJECTS (
  PROJECT_ID        VARCHAR  COMMENT '案件ID',
  PROJECT_NAME      VARCHAR  COMMENT '案件名',
  BRANCH            VARCHAR  COMMENT '担当支店',
  WORK_TYPE         VARCHAR  COMMENT '工種（建築／土木）',
  CLIENT_NAME       VARCHAR  COMMENT '発注者名（架空）',
  CONTRACT_AMOUNT   NUMBER(18,0) COMMENT '契約金額（円）',
  START_DATE        DATE     COMMENT '着工日',
  PLANNED_END_DATE  DATE     COMMENT '竣工予定日',
  STATUS            VARCHAR  COMMENT '状態（施工中／竣工）'
) COMMENT = '工事案件マスター（工事管理システム）';

INSERT INTO PROJECTS
WITH s AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 50))
), b AS (
  SELECT
    i,
    MOD(i, 5)       AS bi,
    FLOOR(i / 5)    AS k
  FROM s
)
SELECT
  'P' || LPAD(i + 1, 3, '0'),
  ARRAY_CONSTRUCT(
    ARRAY_CONSTRUCT('渋谷','品川','新宿','池袋','丸の内'),
    ARRAY_CONSTRUCT('横浜','川崎','みなとみらい','藤沢','相模原'),
    ARRAY_CONSTRUCT('梅田','難波','神戸','京都','堺'),
    ARRAY_CONSTRUCT('名古屋','栄','豊田','岐阜','四日市'),
    ARRAY_CONSTRUCT('博多','天神','北九州','熊本','鹿児島')
  )[bi][MOD(k, 5)]::VARCHAR
  || ARRAY_CONSTRUCT('みらいタワー新築工事','中央ビル新築工事','物流センター新築工事','駅前再開発工事','病院新築工事',
                     '高架橋工事','トンネル工事','護岸整備工事','研究所新築工事','レジデンス新築工事')[k]::VARCHAR,
  ARRAY_CONSTRUCT('東京支店','横浜支店','大阪支店','名古屋支店','九州支店')[bi]::VARCHAR,
  IFF(k IN (5, 6, 7), '土木', '建築'),
  ARRAY_CONSTRUCT('あおば台開発（架空）','ほしぞら電鉄（架空）','こもれび物流（架空）','せせらぎ医療会（架空）',
                  'みずほし製薬（架空）','さざなみ県（架空）','ゆうひ市（架空）','そよかぜ不動産（架空）')[MOD(ABS(HASH(i, 'client')), 8)]::VARCHAR,
  IFF(i = 0, 25000000000, (20 + MOD(ABS(HASH(i, 'amt')), 280)) * 100000000),
  DATEADD(day, MOD(ABS(HASH(i, 'start')), 400), '2024-04-01'::DATE),
  DATEADD(day, 700 + MOD(ABS(HASH(i, 'dur')), 500), DATEADD(day, MOD(ABS(HASH(i, 'start')), 400), '2024-04-01'::DATE)),
  IFF(k >= 8, '竣工', '施工中')
FROM b
ORDER BY i;

-- 主役の現場（P001）の条件をそろえ、状態を日付に合わせる（重機が動いている P001〜P010 は施工中）
UPDATE PROJECTS
SET START_DATE       = IFF(PROJECT_ID = 'P001', '2025-04-01'::DATE, START_DATE),
    PLANNED_END_DATE = IFF(PROJECT_ID = 'P001', '2028-03-31'::DATE, PLANNED_END_DATE),
    CLIENT_NAME      = IFF(PROJECT_ID = 'P001', 'そよかぜ不動産（架空）', CLIENT_NAME),
    STATUS           = IFF(PROJECT_ID > 'P010' AND PLANNED_END_DATE < CURRENT_DATE(), '竣工', '施工中');

-- 工程
CREATE OR REPLACE TABLE PROCESSES (
  PROCESS_ID      VARCHAR COMMENT '工程ID',
  PROJECT_ID      VARCHAR COMMENT '案件ID',
  PROCESS_SEQ     NUMBER  COMMENT '工程の順番',
  PROCESS_NAME    VARCHAR COMMENT '工程名',
  PLANNED_START   DATE    COMMENT '予定開始日',
  PLANNED_END     DATE    COMMENT '予定終了日'
) COMMENT = '工程マスター（工事管理システム）';

INSERT INTO PROCESSES
SELECT
  p.PROJECT_ID || '-' || n.seq,
  p.PROJECT_ID,
  n.seq,
  ARRAY_CONSTRUCT('準備工','山留め・掘削','基礎','躯体','仕上げ','外構')[n.seq - 1]::VARCHAR,
  DATEADD(day, FLOOR(DATEDIFF(day, p.START_DATE, p.PLANNED_END_DATE) * (n.seq - 1) / 6), p.START_DATE),
  DATEADD(day, FLOOR(DATEDIFF(day, p.START_DATE, p.PLANNED_END_DATE) * n.seq / 6) - 1, p.START_DATE)
FROM PROJECTS p
CROSS JOIN (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS seq FROM TABLE(GENERATOR(ROWCOUNT => 6))) n;

-- ---------------------------------------------------------------------
-- 3. 会計：協力会社・工事原価明細・会計仕訳
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE PARTNERS (
  PARTNER_ID    VARCHAR COMMENT '協力会社ID',
  PARTNER_NAME  VARCHAR COMMENT '協力会社名（架空）',
  TRADE         VARCHAR COMMENT '業種'
) COMMENT = '協力会社マスター';

INSERT INTO PARTNERS
WITH s AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 100)))
SELECT
  'C' || LPAD(i + 1, 3, '0'),
  ARRAY_CONSTRUCT('あさぎ','いぶき','うしお','えにし','おぼろ','かすみ','きらら','くすのき','けやき','こはく',
                  'さつき','しおん','すずらん','せいらん','たちばな','ちとせ','つむぎ','ときわ','なぎさ','はるか')[MOD(ABS(HASH(i, 'p1')), 20)]::VARCHAR
  || ARRAY_CONSTRUCT('鉄筋工業','型枠工業','土木興業','電設','空調設備','内装','塗装工業','重機リース','生コン','解体工業')[MOD(i, 10)]::VARCHAR
  || '（架空）',
  ARRAY_CONSTRUCT('鉄筋','型枠','とび・土工','電気設備','空調設備','内装','塗装','重機リース','生コン','解体')[MOD(i, 10)]::VARCHAR
FROM s;

CREATE OR REPLACE TABLE COST_DETAIL (
  COST_ID        NUMBER       COMMENT '原価明細ID',
  PROJECT_ID     VARCHAR      COMMENT '案件ID',
  BRANCH         VARCHAR      COMMENT '担当支店',
  COST_TYPE      VARCHAR      COMMENT '費目（材料費／労務費／外注費／機械費／経費）',
  PARTNER_ID     VARCHAR      COMMENT '協力会社ID',
  AMOUNT         NUMBER(18,0) COMMENT '金額（円）',
  RECORDED_DATE  DATE         COMMENT '計上日'
) COMMENT = '工事原価明細（会計システム）';

INSERT INTO COST_DETAIL
WITH s AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 500000))
)
SELECT
  s.i + 1,
  p.PROJECT_ID,
  p.BRANCH,
  CASE
    WHEN MOD(ABS(HASH(s.i, 'ct')), 100) < 35 THEN '外注費'
    WHEN MOD(ABS(HASH(s.i, 'ct')), 100) < 60 THEN '材料費'
    WHEN MOD(ABS(HASH(s.i, 'ct')), 100) < 80 THEN '労務費'
    WHEN MOD(ABS(HASH(s.i, 'ct')), 100) < 92 THEN '機械費'
    ELSE '経費'
  END,
  'C' || LPAD(MOD(ABS(HASH(s.i, 'pt')), 100) + 1, 3, '0'),
  -- 案件ごとの原価率（P001は高め）に沿って金額を配分
  ROUND(p.CONTRACT_AMOUNT
        * IFF(p.PROJECT_ID = 'P001', 0.93, 0.60 + MOD(ABS(HASH(p.PROJECT_ID, 'ratio')), 30) / 100)
        / 10000
        * (0.5 + MOD(ABS(HASH(s.i, 'amt')), 1000) / 1000)),
  DATEADD(day, MOD(ABS(HASH(s.i, 'd')), 594), '2025-04-01'::DATE)
FROM s
JOIN PROJECTS p
  ON p.PROJECT_ID = 'P' || LPAD(MOD(s.i, 50) + 1, 3, '0')
ORDER BY 7;   -- 計上日の順にロード

CREATE OR REPLACE TABLE GL_JOURNAL (
  JOURNAL_ID     NUMBER       COMMENT '仕訳ID',
  JOURNAL_DATE   DATE         COMMENT '計上日',
  ACCOUNT_CODE   VARCHAR      COMMENT '勘定科目コード',
  ACCOUNT_NAME   VARCHAR      COMMENT '勘定科目名',
  DEPARTMENT     VARCHAR      COMMENT '部門（支店）',
  PROJECT_ID     VARCHAR      COMMENT '案件ID（工事に紐づく仕訳のみ）',
  DEBIT_AMOUNT   NUMBER(18,0) COMMENT '借方金額（円）',
  CREDIT_AMOUNT  NUMBER(18,0) COMMENT '貸方金額（円）',
  DESCRIPTION    VARCHAR      COMMENT '摘要'
) COMMENT = '会計仕訳（会計システム）';

INSERT INTO GL_JOURNAL
WITH s AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 1000000))
), a AS (
  SELECT
    i,
    MOD(ABS(HASH(i, 'acct')), 10) AS ai,
    MOD(ABS(HASH(i, 'dr')), 2)    AS is_debit,
    (1000 + MOD(ABS(HASH(i, 'amt')), 5000000)) AS amt
  FROM s
)
SELECT
  i + 1,
  DATEADD(day, FLOOR(i * 594 / 1000000), '2025-04-01'::DATE),
  ARRAY_CONSTRUCT('4110','1510','5110','5120','5130','5140','1110','2110','1210','6110')[ai]::VARCHAR,
  ARRAY_CONSTRUCT('完成工事高','未成工事支出金','材料費','労務費','外注費','経費',
                  '現金預金','工事未払金','完成工事未収入金','販売費及び一般管理費')[ai]::VARCHAR,
  ARRAY_CONSTRUCT('東京支店','横浜支店','大阪支店','名古屋支店','九州支店','本社')[MOD(ABS(HASH(i, 'dept')), 6)]::VARCHAR,
  IFF(ai IN (6, 9), NULL, 'P' || LPAD(MOD(ABS(HASH(i, 'prj')), 50) + 1, 3, '0')),
  IFF(is_debit = 1, amt, 0),
  IFF(is_debit = 0, amt, 0),
  ARRAY_CONSTRUCT('完成工事高','未成工事支出金','材料費','労務費','外注費','経費',
                  '現金預金','工事未払金','完成工事未収入金','販売費及び一般管理費')[ai]::VARCHAR || ' 計上'
FROM a
ORDER BY 2;   -- 計上日の順にロード

-- ---------------------------------------------------------------------
-- 4. 人事：社員・現場への配置（氏名はすべて架空）
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE EMPLOYEES (
  EMPLOYEE_ID     VARCHAR      COMMENT '社員ID',
  EMPLOYEE_NAME   VARCHAR      COMMENT '氏名（架空）',
  BRANCH          VARCHAR      COMMENT '所属支店',
  DEPARTMENT      VARCHAR      COMMENT '所属部署',
  JOB_TITLE       VARCHAR      COMMENT '役職',
  MONTHLY_SALARY  NUMBER(10,0) COMMENT '月給（円・架空）',
  HIRE_DATE       DATE         COMMENT '入社日'
) COMMENT = '社員マスター（人事システム）';

INSERT INTO EMPLOYEES
WITH s AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 500))),
e AS (
  SELECT
    i,
    MOD(ABS(HASH(i, 'dept')), 100) AS dr,
    MOD(ABS(HASH(i, 'title')), 100) AS tr
  FROM s
)
SELECT
  'E' || LPAD(i + 1, 4, '0'),
  ARRAY_CONSTRUCT('青山','石田','上野','江口','小川','加藤','木村','久保','小松','斉藤',
                  '佐野','島田','杉山','関口','高木','千葉','土屋','手塚','中西','西村',
                  '野口','橋本','平野','福田','堀内','松井','三浦','村上','森田','山口')[MOD(ABS(HASH(i, 'sei')), 30)]::VARCHAR
  || ' ' ||
  ARRAY_CONSTRUCT('彩','葵','健太','翔','大輔','直樹','美咲','結衣','拓也','陽介',
                  '真由','亮','沙織','智子','和也','蓮','花','悠斗','愛','誠',
                  '涼子','優','航','千尋','颯','美穂','恵','大和','莉子','康平')[MOD(ABS(HASH(i, 'mei')), 30)]::VARCHAR,
  ARRAY_CONSTRUCT('東京支店','横浜支店','大阪支店','名古屋支店','九州支店','本社')[MOD(ABS(HASH(i, 'br')), 6)]::VARCHAR,
  CASE WHEN dr < 55 THEN '工事部' WHEN dr < 70 THEN '営業部' WHEN dr < 82 THEN '経理部'
       WHEN dr < 92 THEN '人事部' ELSE '情報システム部' END,
  CASE WHEN tr < 50 THEN '担当' WHEN tr < 78 THEN '主任' WHEN tr < 93 THEN '課長' ELSE '部長' END,
  CASE WHEN tr < 50 THEN 250000 WHEN tr < 78 THEN 350000 WHEN tr < 93 THEN 500000 ELSE 750000 END
    + MOD(ABS(HASH(i, 'sal')), 80) * 1000,
  DATEADD(day, -MOD(ABS(HASH(i, 'hire')), 9000), '2026-04-01'::DATE)
FROM e;

CREATE OR REPLACE TABLE ASSIGNMENTS (
  EMPLOYEE_ID  VARCHAR COMMENT '社員ID',
  PROJECT_ID   VARCHAR COMMENT '案件ID',
  SITE_ROLE    VARCHAR COMMENT '現場での役割（所長／工事主任／工事担当／安全担当）',
  START_DATE   DATE    COMMENT '配置開始日',
  END_DATE     DATE    COMMENT '配置終了日'
) COMMENT = '現場への配置（人事システム）';

INSERT INTO ASSIGNMENTS
WITH eng AS (
  SELECT EMPLOYEE_ID, ROW_NUMBER() OVER (ORDER BY EMPLOYEE_ID) - 1 AS rn
  FROM EMPLOYEES WHERE DEPARTMENT = '工事部'
), cnt AS (SELECT COUNT(*) AS n FROM eng),
s AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 1000)))
SELECT
  eng.EMPLOYEE_ID,
  p.PROJECT_ID,
  CASE WHEN MOD(s.i, 20) = 0 THEN '所長' WHEN MOD(s.i, 5) = 0 THEN '工事主任'
       WHEN MOD(s.i, 7) = 0 THEN '安全担当' ELSE '工事担当' END,
  p.START_DATE,
  p.PLANNED_END_DATE
FROM s
CROSS JOIN cnt
JOIN eng ON eng.rn = MOD(s.i, cnt.n)
JOIN PROJECTS p ON p.PROJECT_ID = 'P' || LPAD(MOD(ABS(HASH(s.i, 'prj')), 50) + 1, 3, '0');

-- ---------------------------------------------------------------------
-- 5. 営業：受注案件（受注済みは工事案件に紐づく）
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE OPPORTUNITIES (
  OPPORTUNITY_ID        VARCHAR      COMMENT '商談ID',
  OPPORTUNITY_NAME      VARCHAR      COMMENT '商談名',
  BRANCH                VARCHAR      COMMENT '担当支店',
  CUSTOMER_SEGMENT      VARCHAR      COMMENT '顧客区分（官公庁／不動産デベロッパー／製造業／鉄道／医療）',
  STAGE                 VARCHAR      COMMENT '商談段階（引合い／見積／提案／受注／失注）',
  EXPECTED_AMOUNT       NUMBER(18,0) COMMENT '受注見込み額（円）',
  PROBABILITY           NUMBER(3,0)  COMMENT '受注確度（％）',
  EXPECTED_ORDER_MONTH  DATE         COMMENT '受注予定月',
  PROJECT_ID            VARCHAR      COMMENT '受注後の案件ID（受注済みのみ）'
) COMMENT = '受注案件（営業支援システム）';

INSERT INTO OPPORTUNITIES
-- 受注済み 50件（工事案件と1対1）
SELECT
  'O' || LPAD(ROW_NUMBER() OVER (ORDER BY PROJECT_ID), 4, '0'),
  PROJECT_NAME,
  BRANCH,
  IFF(WORK_TYPE = '土木', '官公庁',
      ARRAY_CONSTRUCT('不動産デベロッパー','製造業','鉄道','医療')[MOD(ABS(HASH(PROJECT_ID, 'seg')), 4)]::VARCHAR),
  '受注',
  CONTRACT_AMOUNT,
  100,
  DATE_TRUNC('month', DATEADD(month, -2, START_DATE)),
  PROJECT_ID
FROM PROJECTS
UNION ALL
-- 商談中・失注 150件
SELECT
  'O' || LPAD(51 + i, 4, '0'),
  ARRAY_CONSTRUCT('渋谷','品川','横浜','川崎','梅田','神戸','名古屋','豊田','博多','熊本')[MOD(ABS(HASH(i, 'pl')), 10)]::VARCHAR
  || ARRAY_CONSTRUCT('オフィスビル計画','物流施設計画','再開発計画','病院建替計画','道路改良計画','橋梁補修計画')[MOD(ABS(HASH(i, 'nm')), 6)]::VARCHAR,
  ARRAY_CONSTRUCT('東京支店','横浜支店','大阪支店','名古屋支店','九州支店')[MOD(i, 5)]::VARCHAR,
  ARRAY_CONSTRUCT('官公庁','不動産デベロッパー','製造業','鉄道','医療')[MOD(ABS(HASH(i, 'seg')), 5)]::VARCHAR,
  ARRAY_CONSTRUCT('引合い','見積','提案','失注')[MOD(ABS(HASH(i, 'stg')), 4)]::VARCHAR,
  (10 + MOD(ABS(HASH(i, 'amt')), 200)) * 100000000,
  ARRAY_CONSTRUCT(20, 40, 60, 0)[MOD(ABS(HASH(i, 'stg')), 4)]::NUMBER,
  DATE_TRUNC('month', DATEADD(month, MOD(ABS(HASH(i, 'mon')), 12), '2026-12-01'::DATE)),
  NULL
FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 150)));

-- ---------------------------------------------------------------------
-- 6. 今後のデータ：IoT（重機マスター、稼働ログ）
--    稼働中の10現場（P001〜P010）に5台ずつ、計50台
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE MACHINES (
  MACHINE_ID    VARCHAR      COMMENT '重機ID',
  MACHINE_TYPE  VARCHAR      COMMENT '重機の種類',
  PROJECT_ID    VARCHAR      COMMENT '配置先の案件ID',
  PROCESS_ID    VARCHAR      COMMENT '配置先の工程ID',
  HOURLY_RATE   NUMBER(10,0) COMMENT '時間単価（円／時間）。待機による損失の計算に使う'
) COMMENT = '重機マスター';

INSERT INTO MACHINES
WITH s AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 50)))
SELECT
  'M' || LPAD(i + 1, 3, '0'),
  ARRAY_CONSTRUCT('タワークレーン','クローラークレーン','バックホウ','コンクリートポンプ車','ブルドーザー')[MOD(i, 5)]::VARCHAR,
  'P' || LPAD(FLOOR(i / 5) + 1, 3, '0'),
  'P' || LPAD(FLOOR(i / 5) + 1, 3, '0') || '-' || ARRAY_CONSTRUCT(4, 3, 2, 4, 6)[MOD(i, 5)]::VARCHAR,
  ARRAY_CONSTRUCT(25000, 18000, 9000, 15000, 8000)[MOD(i, 5)]::NUMBER
FROM s;

-- COPY INTO のロード先（第3章で使う。最初は空）
CREATE OR REPLACE TABLE MACHINE_LOG (
  MACHINE_ID   VARCHAR       COMMENT '重機ID',
  MEASURED_AT  TIMESTAMP_NTZ COMMENT '計測日時（日本時間）',
  STATUS       VARCHAR       COMMENT '状態（稼働／待機／停止）',
  FUEL_LEVEL   NUMBER(5,1)   COMMENT '燃料残量（％）'
) COMMENT = '重機の稼働ログ（現場のIoT基盤からIICS経由で毎日4回届く）';

-- IICS から届くファイルの置き場所（内部ステージ）
CREATE OR REPLACE STAGE IICS_LANDING
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  COMMENT = 'IICS（Informatica）から届くファイルの置き場所';

-- 稼働ログのCSV（6時間ごとに4本）を作り直すプロシージャ
--  ・実行日の前日の 00:00〜23:59 を1分間隔で作成（50台 × 1,440分 = 72,000行）
--  ・P001（渋谷）の重機は待機が多めになるよう作っている（ストーリー上の伏線）
CREATE OR REPLACE PROCEDURE REGENERATE_LANDING_FILES()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  log_date DATE DEFAULT DATEADD(day, -1, CURRENT_DATE());
  ymd      VARCHAR;
  stmt     VARCHAR;
  h_from   NUMBER;
BEGIN
  ymd := TO_CHAR(:log_date, 'YYYYMMDD');
  EXECUTE IMMEDIATE 'REMOVE @IICS_LANDING';

  CREATE OR REPLACE TEMPORARY TABLE TMP_MACHINE_LOG AS
  WITH m AS (
    SELECT MACHINE_ID, PROJECT_ID, MACHINE_TYPE FROM MACHINES
  ), t AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS minute_no FROM TABLE(GENERATOR(ROWCOUNT => 1440))
  ), base AS (
    SELECT
      m.MACHINE_ID,
      m.PROJECT_ID,
      m.MACHINE_TYPE,
      DATEADD(minute, t.minute_no, :log_date::TIMESTAMP_NTZ) AS measured_at,
      FLOOR(t.minute_no / 60) AS hh,
      t.minute_no,
      MOD(ABS(HASH(m.MACHINE_ID, t.minute_no, 'st')), 100) AS r
    FROM m CROSS JOIN t
  )
  SELECT
    MACHINE_ID,
    measured_at AS MEASURED_AT,
    CASE
      WHEN hh < 7 OR hh >= 19 THEN IFF(r < 95, '停止', '待機')                      -- 夜間はほぼ停止
      WHEN PROJECT_ID = 'P001' AND MACHINE_TYPE = 'タワークレーン' THEN IFF(r < 55, '待機', '稼働')
      WHEN PROJECT_ID = 'P001' THEN IFF(r < 40, '待機', '稼働')
      ELSE IFF(r < 18, '待機', IFF(r < 22, '停止', '稼働'))
    END AS STATUS,
    ROUND(GREATEST(5, 100 - minute_no * 0.05 - MOD(ABS(HASH(MACHINE_ID, 'fuel')), 20)), 1) AS FUEL_LEVEL
  FROM base;

  FOR q IN 0 TO 3 DO
    h_from := q * 6;
    stmt := 'COPY INTO @IICS_LANDING/machine_log/machine_log_' || ymd || '_' || LPAD(h_from, 2, '0') || '.csv ' ||
            'FROM (SELECT MACHINE_ID, TO_CHAR(MEASURED_AT, ''YYYY-MM-DD HH24:MI:SS'') AS MEASURED_AT, STATUS, FUEL_LEVEL ' ||
            '      FROM TMP_MACHINE_LOG WHERE HOUR(MEASURED_AT) >= ' || h_from || ' AND HOUR(MEASURED_AT) < ' || (h_from + 6) ||
            '      ORDER BY MEASURED_AT, MACHINE_ID) ' ||
            'FILE_FORMAT = (TYPE = CSV COMPRESSION = NONE FIELD_OPTIONALLY_ENCLOSED_BY = ''"'') ' ||
            'HEADER = TRUE SINGLE = TRUE OVERWRITE = TRUE MAX_FILE_SIZE = 104857600';
    EXECUTE IMMEDIATE :stmt;
  END FOR;

  ALTER STAGE IICS_LANDING REFRESH;
  RETURN '作成しました: machine_log_' || ymd || '_00/06/12/18.csv';
END;
$$;

CALL REGENERATE_LANDING_FILES();

-- ---------------------------------------------------------------------
-- 7. 今後のデータ：システムの監査ログ（直近90日）
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SYSTEM_AUDIT_LOG (
  LOG_ID       NUMBER        COMMENT 'ログID',
  EVENT_TIME   TIMESTAMP_NTZ COMMENT '発生日時',
  EMPLOYEE_ID  VARCHAR       COMMENT '利用者の社員ID',
  DEPARTMENT   VARCHAR       COMMENT '利用者の所属部署',
  SYSTEM_NAME  VARCHAR       COMMENT 'システム名',
  ACTION       VARCHAR       COMMENT '操作（ログイン／参照／更新／出力）'
) COMMENT = '各システムの監査ログ（今後データ基盤に取り込む予定のデータ）';

INSERT INTO SYSTEM_AUDIT_LOG
WITH s AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS i FROM TABLE(GENERATOR(ROWCOUNT => 100000)))
SELECT
  s.i + 1,
  DATEADD(second, 28800 + MOD(ABS(HASH(s.i, 'sec')), 32400),            -- 8:00〜17:00 の間
          DATEADD(day, -1 - MOD(ABS(HASH(s.i, 'day')), 90), CURRENT_DATE())::TIMESTAMP_NTZ),
  e.EMPLOYEE_ID,
  e.DEPARTMENT,
  CASE e.DEPARTMENT
    WHEN '経理部' THEN '会計システム'
    WHEN '人事部' THEN '人事システム'
    WHEN '営業部' THEN '営業支援システム'
    WHEN '工事部' THEN '工事管理システム'
    ELSE ARRAY_CONSTRUCT('会計システム','人事システム','営業支援システム','工事管理システム','文書管理システム')[MOD(ABS(HASH(s.i, 'sys')), 5)]::VARCHAR
  END,
  ARRAY_CONSTRUCT('ログイン','参照','参照','参照','更新','出力')[MOD(ABS(HASH(s.i, 'act')), 6)]::VARCHAR
FROM s
JOIN EMPLOYEES e ON e.EMPLOYEE_ID = 'E' || LPAD(MOD(ABS(HASH(s.i, 'emp')), 500) + 1, 4, '0')
ORDER BY 2;

-- ---------------------------------------------------------------------
-- 8. 権限管理の準備（第5章で使うロールと、支店とロールの対応表）
-- ---------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS BRANCH_TOKYO_ROLE COMMENT = '東京支店の社員';
CREATE ROLE IF NOT EXISTS BRANCH_OSAKA_ROLE COMMENT = '大阪支店の社員';
CREATE ROLE IF NOT EXISTS HR_ROLE           COMMENT = '人事部の社員';

CREATE OR REPLACE TABLE BRANCH_ROLE_MAP (
  ROLE_NAME  VARCHAR COMMENT 'ロール名',
  BRANCH     VARCHAR COMMENT '閲覧できる支店'
) COMMENT = '支店とロールの対応表（行アクセスポリシーで使う）';
INSERT INTO BRANCH_ROLE_MAP VALUES
  ('BRANCH_TOKYO_ROLE', '東京支店'),
  ('BRANCH_OSAKA_ROLE', '大阪支店');

GRANT USAGE ON DATABASE CONSTRUCTION_HOL TO ROLE BRANCH_TOKYO_ROLE;
GRANT USAGE ON DATABASE CONSTRUCTION_HOL TO ROLE BRANCH_OSAKA_ROLE;
GRANT USAGE ON DATABASE CONSTRUCTION_HOL TO ROLE HR_ROLE;
GRANT USAGE ON SCHEMA CONSTRUCTION_HOL.RAW TO ROLE BRANCH_TOKYO_ROLE;
GRANT USAGE ON SCHEMA CONSTRUCTION_HOL.RAW TO ROLE BRANCH_OSAKA_ROLE;
GRANT USAGE ON SCHEMA CONSTRUCTION_HOL.RAW TO ROLE HR_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA CONSTRUCTION_HOL.RAW TO ROLE BRANCH_TOKYO_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA CONSTRUCTION_HOL.RAW TO ROLE BRANCH_OSAKA_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA CONSTRUCTION_HOL.RAW TO ROLE HR_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA CONSTRUCTION_HOL.RAW TO ROLE BRANCH_TOKYO_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA CONSTRUCTION_HOL.RAW TO ROLE BRANCH_OSAKA_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA CONSTRUCTION_HOL.RAW TO ROLE HR_ROLE;

-- 実行しているユーザー自身に3つのロールを付与（ロールの切り替えを体験するため）
EXECUTE IMMEDIATE $$
DECLARE
  u VARCHAR DEFAULT CURRENT_USER();
BEGIN
  EXECUTE IMMEDIATE 'GRANT ROLE BRANCH_TOKYO_ROLE TO USER "' || :u || '"';
  EXECUTE IMMEDIATE 'GRANT ROLE BRANCH_OSAKA_ROLE TO USER "' || :u || '"';
  EXECUTE IMMEDIATE 'GRANT ROLE HR_ROLE TO USER "' || :u || '"';
  RETURN 'ロールを付与しました: ' || :u;
END;
$$;

-- ---------------------------------------------------------------------
-- 9. TPC-H のサンプルデータ（第4章で使う）
--    新しいアカウントには最初からあります。ない場合だけ作成します。
-- ---------------------------------------------------------------------
EXECUTE IMMEDIATE $$
BEGIN
  CREATE DATABASE SNOWFLAKE_SAMPLE_DATA FROM SHARE SFC_SAMPLES.SAMPLE_DATA;
  GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE PUBLIC;
  RETURN 'SNOWFLAKE_SAMPLE_DATA を作成しました';
EXCEPTION
  WHEN OTHER THEN
    RETURN 'SNOWFLAKE_SAMPLE_DATA は作成済みか、作成できませんでした: ' || SQLERRM;
END;
$$;

-- CREATE DATABASE でセッションのデータベースが切り替わるため、元に戻す
USE SCHEMA CONSTRUCTION_HOL.RAW;

-- ---------------------------------------------------------------------
-- 10. 確認（各テーブルの件数とステージのファイル）
-- ---------------------------------------------------------------------
-- 結果が4行とも「OK」なら準備は完了です
SELECT "確認項目", "件数", "期待値", IFF("件数" = "期待値", 'OK', '要確認') AS "判定"
FROM (
            SELECT 1 AS no, '工事原価明細（COST_DETAIL）'              AS "確認項目", (SELECT COUNT(*) FROM COST_DETAIL) AS "件数", 500000  AS "期待値"
  UNION ALL SELECT 2,     '会計仕訳（GL_JOURNAL）',                          (SELECT COUNT(*) FROM GL_JOURNAL),          1000000
  UNION ALL SELECT 3,     '重機の稼働ログ（MACHINE_LOG：第3章でロード）',    (SELECT COUNT(*) FROM MACHINE_LOG),         0
  UNION ALL SELECT 4,     'ステージに届いたCSVファイル（IICS_LANDING）',     (SELECT COUNT(*) FROM DIRECTORY(@IICS_LANDING)), 4
)
ORDER BY no;

-- SETUP_WH は60秒使われなければ自動で停止します
