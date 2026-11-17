# Snowflake データエンジニアリング ハンズオン（建設業編）

架空の建設会社「Snow建設」のデータ基盤チームの1日（9:00〜17:00）を体験しながら、Snowflake の基本操作を学ぶハンズオンです。SQL を一から書く必要はありません。Snowflake の AI アシスタント「Cortex Code（CoCo）」に日本語で頼みながら進めます。

> このリポジトリのデータは、すべて架空です。社名・人名・案件名・金額は、実在の企業・人物・案件とは関係ありません。

## 体験すること

| 章 | 時刻（ストーリー） | 内容 |
|---|---|---|
| 1 | 9:00 初出社 | Snowsight と CoCo の使い方、ウェアハウスの作成 |
| 2 | 10:00 古いSQLを引き継ぐ | T-SQL を CoCo で Snowflake 用に変換、条件の追加、エラーの修正 |
| 3 | 11:00 現場からデータが届く | ステージからの COPY INTO、Dynamic Table、Task |
| 4 | 12:00 明日の朝ピークに備える | ウェアハウスのサイズ変更、結果キャッシュ、自動停止 |
| 5 | 13:00 守りの運用 | UNDROP、ゼロコピークローン、行アクセスポリシー、マスキング、監査の準備、リソースモニター |
| 7 | 17:00 役員報告 | セマンティックビュー、ダッシュボード、CoWork での深掘り |

第6章（協力会社とのデータ共有）は講師のデモです。

## 必要なもの

- Snowflake のアカウント（Enterprise Edition 以上）。ACCOUNTADMIN ロールを使います
- Cortex Code（CoCo）と Snowflake CoWork が使える状態であること
- ブラウザ（Snowsight を使います。ソフトのインストールは不要です）

## フォルダの構成

| パス | 内容 |
|---|---|
| `sql/00_setup.sql` | 準備スクリプト。最初に1回だけ実行します |
| `sql/01_first_day.sql` 〜 `sql/07_report.sql` | 各章で使うファイル |
| `sql/99_cleanup.sql` | 後片付け。Dynamic Table と Task を停止します |
| `answers/` | 救済用の正解SQL。CoCo の結果がうまくいかないときに使います |
| `docs/handson_guide.md` | 手順書 |

## はじめかた

### 1. このリポジトリを Workspaces に取り込む

このリポジトリは公開されているので、GitHub のアカウントやトークンは不要です。

1. Snowsight にログインし、左下のユーザーメニューでロールを **ACCOUNTADMIN** にします。
2. 左のメニューの **ワークスペース**（英語表示では **Workspaces**）を開きます。**自分のワークスペース**（My Workspace）の **＋ 新規追加**（Add new）で SQL ファイルを作り、次の SQL を実行します。Snowflake が GitHub からファイルを取得するための設定です。

   ```sql
   USE ROLE ACCOUNTADMIN;
   CREATE OR REPLACE API INTEGRATION GITHUB_PUBLIC_API
     API_PROVIDER = git_https_api
     API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-kichikawa')
     ENABLED = TRUE;
   ```

3. ワークスペース一覧の上にある **＋** を押し、**新規作成**（Create new）の中から **Gitワークスペース**（Git workspace）を選びます。
4. 開いた画面の、リポジトリの URL を入れる欄（Repository URL）に、次の URL を貼り付けます。

   ```
   https://github.com/sfc-gh-kichikawa/snow-kensetsu-data-engineering-handson
   ```

5. API インテグレーションの欄（API Integration）で `GITHUB_PUBLIC_API` を選びます。
6. 認証方法で、公開リポジトリ（Public repository）を選び、作成（Create）を押します。`sql/`、`answers/`、`docs/` が表示されれば完了です。

> 「Public repository」で作ったワークスペースからは、GitHub に push できません。SQL ファイルに追記して保存するのは問題ありません。変更はご自身のワークスペースの中にだけ残ります。
>
> 教材が更新されたときは、ワークスペースの **Changes** タブで **Pull** を押すと最新になります。

### 2. 準備スクリプトを実行する

1. ロールが **ACCOUNTADMIN** であることを確かめ、`sql/00_setup.sql` を開いて、すべて実行します（数分かかります）。
2. `docs/handson_guide.md` の手順に沿って、第1章から進めます。

## 準備スクリプトが作るもの

- データベース `CONSTRUCTION_HOL`、スキーマ `RAW`
- 基幹システムのデータ：工事案件、工程、協力会社、工事原価明細（50万行）、会計仕訳（100万行）、社員、現場への配置、商談
- 今後のデータ：重機マスター、重機の稼働ログ（CSV 4本を内部ステージ `IICS_LANDING` に作成）、システムの監査ログ
- 第5章で使うロール：`BRANCH_TOKYO_ROLE`、`BRANCH_OSAKA_ROLE`、`HR_ROLE`
- アカウントのタイムゾーンを `Asia/Tokyo` に設定します

重機の稼働ログは、準備スクリプトを実行した日の前日の日付で作られます。日をまたいで使う場合は、`CALL CONSTRUCTION_HOL.RAW.REGENERATE_LANDING_FILES();` でファイルを作り直してください。

## 片付け

ハンズオンが終わったら、次のSQLで作成したものを削除できます。

```sql
USE ROLE ACCOUNTADMIN;
ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT DROP AGENT CONSTRUCTION_HOL.RAW.CONSTRUCTION_AGENT;
DROP DATABASE IF EXISTS CONSTRUCTION_HOL;
DROP WAREHOUSE IF EXISTS ETL_WH;
DROP WAREHOUSE IF EXISTS BI_WH;
DROP WAREHOUSE IF EXISTS SETUP_WH;
DROP RESOURCE MONITOR IF EXISTS HOL_MONITOR;
DROP ROLE IF EXISTS BRANCH_TOKYO_ROLE;
DROP ROLE IF EXISTS BRANCH_OSAKA_ROLE;
DROP ROLE IF EXISTS HR_ROLE;
DROP API INTEGRATION IF EXISTS GITHUB_PUBLIC_API;
```

Git 連携のワークスペースは、左のメニューの **ワークスペース** の一覧から削除してください。
