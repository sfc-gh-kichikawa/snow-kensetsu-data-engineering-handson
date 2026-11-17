/* =====================================================================
   第7章 17:00 役員報告
   ---------------------------------------------------------------------
   役員「今日の現場の状況と原価を、1枚で見せてくれ」

   1〜3 は、上から順にそのまま実行してください（CoCo は使いません）。
     1. セマンティックビュー（業務の辞書）を作る
     2. CoWork から質問できるエージェントを作る
     3. エージェントを CoWork に登録する
   4〜5 は、ファイルの最後にある指示文を CoCo や CoWork に送ります。
     4. CoCo でダッシュボードを作る
     5. CoWork で深掘りの質問をする
   ===================================================================== */

USE ROLE ACCOUNTADMIN;
USE SCHEMA CONSTRUCTION_HOL.RAW;
USE WAREHOUSE BI_WH;

-- ---------------------------------------------------------------------
-- 1. セマンティックビュー：テーブルのつながり方・指標の計算式・日本語の別名を定義する
--    AI が「原価率」と聞かれたときに、どのテーブルをどうつなぎ、どう計算するかを
--    迷わないようにする「業務の辞書」です。誰が聞いても同じ計算式で答えが出ます。
--      TABLES        … 使うテーブルと、日本語の別名（例：PROJECTS は「現場」「案件」）
--      RELATIONSHIPS … テーブル同士のつながり方（どの列で結合するか）
--      DIMENSIONS    … 集計の切り口（支店、案件、月など）
--      METRICS       … 指標とその計算式（原価率、待機による損失など）
--    中身は読めなくても大丈夫です。そのまま実行してください。
-- ---------------------------------------------------------------------
CREATE OR REPLACE SEMANTIC VIEW CONSTRUCTION_HOL.RAW.CONSTRUCTION_SV

  TABLES (
    projects AS CONSTRUCTION_HOL.RAW.PROJECTS
      PRIMARY KEY (PROJECT_ID)
      WITH SYNONYMS ('工事案件', '現場', '案件')
      COMMENT = '工事案件マスター。1行が1つの工事案件（現場）',
    processes AS CONSTRUCTION_HOL.RAW.PROCESSES
      PRIMARY KEY (PROCESS_ID)
      WITH SYNONYMS ('工程')
      COMMENT = '工事案件ごとの工程',
    costs AS CONSTRUCTION_HOL.RAW.COST_DETAIL
      PRIMARY KEY (COST_ID)
      WITH SYNONYMS ('原価', '工事原価', '原価明細')
      COMMENT = '工事原価の明細。1行が1件の原価の計上',
    partners AS CONSTRUCTION_HOL.RAW.PARTNERS
      PRIMARY KEY (PARTNER_ID)
      WITH SYNONYMS ('協力会社')
      COMMENT = '協力会社マスター（架空）',
    opportunities AS CONSTRUCTION_HOL.RAW.OPPORTUNITIES
      PRIMARY KEY (OPPORTUNITY_ID)
      WITH SYNONYMS ('商談', '受注案件', '営業案件')
      COMMENT = '営業の商談。受注済みの商談は工事案件に紐づく',
    machine_idle AS CONSTRUCTION_HOL.RAW.SITE_MACHINE_IDLE
      WITH SYNONYMS ('重機の待機', '重機稼働')
      COMMENT = '現場×工程×重機の種類×1時間ごとの重機の待機状況（Dynamic Table）',
    employees AS CONSTRUCTION_HOL.RAW.EMPLOYEES
      PRIMARY KEY (EMPLOYEE_ID)
      WITH SYNONYMS ('社員', '従業員')
      COMMENT = '社員マスター（氏名は架空）。月給は人事部のロールだけが見られる',
    assignments AS CONSTRUCTION_HOL.RAW.ASSIGNMENTS
      WITH SYNONYMS ('配置', '現場への配置')
      COMMENT = '社員の現場への配置'
  )

  RELATIONSHIPS (
    processes_to_projects    AS processes (PROJECT_ID)     REFERENCES projects,
    costs_to_projects        AS costs (PROJECT_ID)         REFERENCES projects,
    costs_to_partners        AS costs (PARTNER_ID)         REFERENCES partners,
    opportunities_to_projects AS opportunities (PROJECT_ID) REFERENCES projects,
    idle_to_projects         AS machine_idle (PROJECT_ID)  REFERENCES projects,
    assignments_to_projects  AS assignments (PROJECT_ID)   REFERENCES projects,
    assignments_to_employees AS assignments (EMPLOYEE_ID)  REFERENCES employees
  )

  FACTS (
    opportunities.weighted_amount AS opportunities.EXPECTED_AMOUNT * opportunities.PROBABILITY / 100
      COMMENT = '受注見込み額 × 受注確度（円）'
  )

  DIMENSIONS (
    projects.project_name AS projects.PROJECT_NAME
      WITH SYNONYMS = ('案件名', '現場名', '工事名')
      COMMENT = '工事案件の名前',
    projects.branch AS projects.BRANCH
      WITH SYNONYMS = ('支店', '担当支店')
      COMMENT = '工事案件を担当する支店',
    projects.work_type AS projects.WORK_TYPE
      WITH SYNONYMS = ('工種')
      COMMENT = '建築または土木',
    projects.project_status AS projects.STATUS
      WITH SYNONYMS = ('状態', '施工状況')
      COMMENT = '施工中または竣工',
    projects.client_name AS projects.CLIENT_NAME
      WITH SYNONYMS = ('発注者')
      COMMENT = '発注者（架空）',
    processes.process_name AS processes.PROCESS_NAME
      WITH SYNONYMS = ('工程名')
      COMMENT = '工程の名前（準備工、山留め・掘削、基礎、躯体、仕上げ、外構）',
    costs.cost_type AS costs.COST_TYPE
      WITH SYNONYMS = ('費目')
      COMMENT = '材料費、労務費、外注費、機械費、経費',
    costs.recorded_date AS costs.RECORDED_DATE
      WITH SYNONYMS = ('計上日')
      COMMENT = '原価の計上日',
    costs.recorded_month AS DATE_TRUNC('MONTH', costs.RECORDED_DATE)
      WITH SYNONYMS = ('計上月', '月')
      COMMENT = '原価の計上月',
    partners.partner_name AS partners.PARTNER_NAME
      WITH SYNONYMS = ('協力会社名')
      COMMENT = '協力会社の名前（架空）',
    partners.trade AS partners.TRADE
      WITH SYNONYMS = ('業種')
      COMMENT = '協力会社の業種',
    opportunities.opportunity_name AS opportunities.OPPORTUNITY_NAME
      WITH SYNONYMS = ('商談名')
      COMMENT = '商談の名前',
    opportunities.stage AS opportunities.STAGE
      WITH SYNONYMS = ('商談段階', 'ステージ')
      COMMENT = '引合い、見積、提案、受注、失注',
    opportunities.customer_segment AS opportunities.CUSTOMER_SEGMENT
      WITH SYNONYMS = ('顧客区分')
      COMMENT = '官公庁、不動産デベロッパー、製造業、鉄道、医療',
    opportunities.expected_order_month AS opportunities.EXPECTED_ORDER_MONTH
      WITH SYNONYMS = ('受注予定月')
      COMMENT = '受注の予定月',
    machine_idle.idle_process_name AS machine_idle.PROCESS_NAME
      WITH SYNONYMS = ('待機が発生した工程')
      COMMENT = '重機が配置されている工程',
    machine_idle.machine_type AS machine_idle.MACHINE_TYPE
      WITH SYNONYMS = ('重機の種類', '機械')
      COMMENT = 'タワークレーン、クローラークレーン、バックホウ、コンクリートポンプ車、ブルドーザー',
    machine_idle.hour_slot AS machine_idle.HOUR_SLOT
      WITH SYNONYMS = ('時間帯', '日時')
      COMMENT = '1時間ごとの時間帯（日本時間）',
    employees.employee_name AS employees.EMPLOYEE_NAME
      WITH SYNONYMS = ('氏名', '社員名')
      COMMENT = '社員の氏名（架空）',
    employees.department AS employees.DEPARTMENT
      WITH SYNONYMS = ('部署')
      COMMENT = '所属部署',
    employees.job_title AS employees.JOB_TITLE
      WITH SYNONYMS = ('役職')
      COMMENT = '役職',
    assignments.site_role AS assignments.SITE_ROLE
      WITH SYNONYMS = ('現場での役割')
      COMMENT = '所長、工事主任、工事担当、安全担当'
  )

  METRICS (
    costs.total_cost AS SUM(costs.AMOUNT)
      WITH SYNONYMS = ('原価合計', '原価', '工事原価')
      COMMENT = '原価の合計金額（円）',
    projects.total_contract_amount AS SUM(projects.CONTRACT_AMOUNT)
      WITH SYNONYMS = ('契約金額', '請負金額')
      COMMENT = '契約金額の合計（円）',
    projects.project_count AS COUNT(projects.PROJECT_ID)
      WITH SYNONYMS = ('案件数')
      COMMENT = '工事案件の件数',
    cost_ratio AS costs.total_cost / NULLIF(projects.total_contract_amount, 0) * 100
      WITH SYNONYMS = ('原価率')
      COMMENT = '原価率（％）＝原価合計 ÷ 契約金額 × 100',
    machine_idle.idle_loss AS SUM(machine_idle.IDLE_LOSS_YEN)
      WITH SYNONYMS = ('待機による損失', '待機ロス', '待機損失')
      COMMENT = '重機の待機による損失の概算（円）＝待機時間 × 時間単価 ÷ 60',
    machine_idle.total_idle_minutes AS SUM(machine_idle.IDLE_MINUTES)
      WITH SYNONYMS = ('待機時間')
      COMMENT = '重機の待機時間の合計（分）',
    machine_idle.idle_rate AS SUM(machine_idle.IDLE_MINUTES) / NULLIF(SUM(machine_idle.TOTAL_MINUTES), 0) * 100
      WITH SYNONYMS = ('待機率')
      COMMENT = '重機の待機率（％）',
    opportunities.total_expected_amount AS SUM(opportunities.EXPECTED_AMOUNT)
      WITH SYNONYMS = ('受注見込み額', 'パイプライン')
      COMMENT = '受注見込み額の合計（円）',
    opportunities.weighted_expected_amount AS SUM(opportunities.weighted_amount)
      WITH SYNONYMS = ('確度を考慮した受注見込み額')
      COMMENT = '受注見込み額 × 受注確度 の合計（円）',
    employees.headcount AS COUNT(employees.EMPLOYEE_ID)
      WITH SYNONYMS = ('人数', '社員数')
      COMMENT = '社員の人数',
    employees.average_salary AS AVG(employees.MONTHLY_SALARY)
      WITH SYNONYMS = ('平均月給')
      COMMENT = '平均月給（円）。人事部のロール以外では値が見えない'
  )

  COMMENT = 'Snow建設（架空）の工事・原価・受注・重機稼働・人員配置を分析するための業務の辞書';

-- 作ったセマンティックビューの中身を確認（テーブル・切り口・指標が1行ずつ表示されます）
DESCRIBE SEMANTIC VIEW CONSTRUCTION_HOL.RAW.CONSTRUCTION_SV;


-- ---------------------------------------------------------------------
-- 2. CoWork から質問できるエージェントを作る
--    エージェントは、日本語の質問を受けて、上のセマンティックビューを使って SQL を作り、
--    結果を文章やグラフで返す AI のアシスタントです。
--      instructions … 答え方の指示（日本語で、金額は円で など）と、質問の例
--      tools        … 使う道具（データを集計する、グラフを作る）
--      warehouse    … 集計には BI_WH を使う（ETL の処理とは分かれています）
-- ---------------------------------------------------------------------
CREATE OR REPLACE AGENT CONSTRUCTION_HOL.RAW.CONSTRUCTION_AGENT
  COMMENT = 'Snow建設（架空）の現場分析アシスタント'
  PROFILE = '{"display_name": "Snow建設 現場分析アシスタント"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    response: "日本語で、簡潔に答えてください。金額は円で、3桁ごとにカンマを付けてください。データはすべて架空であることを前提に答えてください。"
    orchestration: "工事案件、原価、原価率、受注、重機の待機、社員の配置に関する質問には construction_analyst を使ってください。"
    sample_questions:
      - question: "待機による損失が一番大きい現場はどこですか？"
      - question: "支店別の原価率を教えてください"
      - question: "渋谷みらいタワー新築工事では、どの工程のどの重機が待機していますか？"

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "construction_analyst"
        description: "Snow建設（架空）の工事案件、工程、工事原価、協力会社、商談、重機の待機状況、社員と現場への配置を分析する。原価率、待機による損失、受注見込み額などの指標を、支店・案件・工程・月などの切り口で集計するときに使う。"
    - tool_spec:
        type: "data_to_chart"
        name: "data_to_chart"
        description: "集計結果からグラフを作る"

  tool_resources:
    construction_analyst:
      semantic_view: "CONSTRUCTION_HOL.RAW.CONSTRUCTION_SV"
      execution_environment:
        type: "warehouse"
        warehouse: "BI_WH"
  $$;


-- ---------------------------------------------------------------------
-- 3. エージェントを CoWork に登録する
--    登録すると、CoWork の画面でこのエージェントを選んで質問できるようになります。
--    （CoWork のオブジェクトがまだない場合は作成します。すでにあれば、そのまま使います）
-- ---------------------------------------------------------------------
EXECUTE IMMEDIATE $$
BEGIN
  CREATE SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
  RETURN 'CoWork のオブジェクトを作成しました';
EXCEPTION
  WHEN OTHER THEN
    RETURN 'CoWork のオブジェクトは作成済みです: ' || SQLERRM;
END;
$$;

ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
  ADD AGENT CONSTRUCTION_HOL.RAW.CONSTRUCTION_AGENT;

-- 作ったエージェントの確認（CONSTRUCTION_AGENT が表示されれば完了です）
SHOW AGENTS IN SCHEMA CONSTRUCTION_HOL.RAW;


-- ---------------------------------------------------------------------
-- 4. CoCo でダッシュボードを作る
--    右のチャット欄に、次の指示を送ります。
--    チャット欄で「/」と入力して一覧に dashboard が出る場合は、選んでから指示を続けても構いません。
-- ---------------------------------------------------------------------
-- 【CoCoへの指示】
--   セマンティックビュー CONSTRUCTION_SV を使って、役員向けのダッシュボードを作ってください。支店別の原価率、月別の原価の推移、現場別の待機による損失、受注見込み額の合計を並べてください。


-- ---------------------------------------------------------------------
-- 5. CoWork で深掘りの質問をする
--    講師の案内に沿ってダッシュボードを共有し、CoWork で開いてから、次の質問を送ります。
--    答えられない場合は、CoWork でエージェント「Snow建設 現場分析アシスタント」を選んで質問します。
-- ---------------------------------------------------------------------
-- 【CoWorkへの質問】
--   渋谷みらいタワー新築工事の待機による損失が大きいのはなぜ？どの工程の、どの重機が待機していますか？
