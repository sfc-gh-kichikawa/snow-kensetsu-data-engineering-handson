/* =====================================================================
   第2章　10:00 古いSQLを引き継ぐ
   ---------------------------------------------------------------------
   前任者が Azure SQL Database 用に書いた T-SQL が残っています。
   このままでは Snowflake では動きません。CoCo に直してもらいましょう。

   操作の流れ
     1. 右のチャット欄で、CoCo に【指示1】を伝える
     2. ファイルに追記されたSQLを確認して、実行する
     3. 続けて【指示2】で条件を追加してもらう
     4. 最後に「④ エラーになるSQL」を実行し、CoCo に直してもらう
   ===================================================================== */

USE SCHEMA CONSTRUCTION_HOL.RAW;
USE WAREHOUSE BI_WH;

-- ---------------------------------------------------------------------
-- ① 前任者が残した T-SQL（支店別・案件別の原価率レポート）
-- ---------------------------------------------------------------------
-- T-SQL（Azure SQL Database や SQL Server の SQL）らしい書き方が入っています。
--   TOP 10        … 先頭10件だけ出す（Snowflake では最後に LIMIT 10）
--   [ ]           … 列名やテーブル名を囲む角かっこ（Snowflake では不要）
--   ISNULL        … NULL を別の値に置き換える（Snowflake では COALESCE など）
--   GETDATE()     … 今の日時（Snowflake では CURRENT_TIMESTAMP など）
--   WITH (NOLOCK) … ロックを待たずに読む指定（Snowflake では読み取りがロックを待たないので不要）
--   CONVERT(…111) … 日付を「年/月/日」の文字にする（Snowflake では TO_CHAR など）
-- このまま Snowflake で実行するとエラーになります。実行せずに、CoCo に書き換えてもらいます。

-- 支店別 原価率レポート（月次会議用）  作成：前任者
-- ※直近1年の原価を集計し、原価率の高い案件から10件を出す
SELECT TOP 10
    [p].[BRANCH]                                             AS [支店],
    [p].[PROJECT_NAME]                                       AS [案件名],
    ISNULL(SUM([c].[AMOUNT]), 0)                             AS [原価合計],
    [p].[CONTRACT_AMOUNT]                                    AS [契約金額],
    ISNULL(SUM([c].[AMOUNT]), 0) * 100.0
        / NULLIF([p].[CONTRACT_AMOUNT], 0)                   AS [原価率],
    CONVERT(VARCHAR(10), GETDATE(), 111)                     AS [集計日]
FROM [RAW].[PROJECTS] AS [p] WITH (NOLOCK)
LEFT JOIN [RAW].[COST_DETAIL] AS [c] WITH (NOLOCK)
    ON [p].[PROJECT_ID] = [c].[PROJECT_ID]
WHERE DATEDIFF(day, [c].[RECORDED_DATE], GETDATE()) <= 365
GROUP BY [p].[BRANCH], [p].[PROJECT_NAME], [p].[CONTRACT_AMOUNT]
ORDER BY [原価率] DESC;

-- 【指示1】
--   ①の T-SQL を Snowflake 用に書き換えて、その下に追記してください。実行はしないでください。

-- 書き換えた SQL を実行すると、原価率の高い案件から10件が表示されます。
-- 元の T-SQL は残ったままなので、何が変わったかを見比べられます。

-- 【指示2】
--   Where 句（絞り込みの条件）を、日本語で伝えて足してもらいます。
--   書き換えたSQLを、東京支店の2026年度（2026/4/1〜2027/3/31）だけに絞り、件数の制限をなくしてください。実行はしないでください。


-- ---------------------------------------------------------------------
-- ④ エラーになるSQL（実行するとエラーになります）
--    実行してエラーが出たら、CoCo に【指示3】を伝えてください。
-- ---------------------------------------------------------------------
SELECT
    BRANCH,
    PROJECT_NAME,
    SUM(AMOUNT) AS TOTAL_COST
FROM PROJECTS p
JOIN COST_DETAIL c
    ON p.PROJECT_ID = c.PROJECT_ID
GROUP BY BRANCH, PROJECT_NAME;

-- エラーの意味：BRANCH という列が PROJECTS と COST_DETAIL の両方にあるので、
-- どちらの列を使えばよいか Snowflake が決められません。CoCo に原因を説明してもらい、直してもらいます。

-- 【指示3】
--   ④のSQLのエラーの原因を説明して、直してください。
