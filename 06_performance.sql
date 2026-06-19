-- 0. 環境セットアップ（DB・スキーマ・ウェアハウス・サンプルデータを作成）
USE ROLE SYSADMIN;

CREATE OR REPLACE DATABASE N06;
CREATE OR REPLACE SCHEMA N06.HANDS_ON;
CREATE OR REPLACE WAREHOUSE N06_WH
  WAREHOUSE_SIZE      = 'X-SMALL'
  AUTO_SUSPEND        = 60      -- 60秒アイドルで自動停止
  AUTO_RESUME         = TRUE    -- クエリ実行時に自動起動
  INITIALLY_SUSPENDED = TRUE;   -- 作成時は停止状態

USE DATABASE N06;
USE SCHEMA N06.HANDS_ON;
USE WAREHOUSE N06_WH;

-- 大きめのサンプル注文テーブル（約200万行）を生成
CREATE OR REPLACE TABLE N06.HANDS_ON.ORDERS AS
SELECT
  SEQ8()                                              AS ORDER_ID,
  UNIFORM(1, 100000, RANDOM())                        AS CUSTOMER_ID,
  DATEADD('day', UNIFORM(0, 1095, RANDOM()), '2023-01-01'::DATE) AS ORDER_DATE,
  UNIFORM(100, 50000, RANDOM())                       AS AMOUNT
FROM TABLE(GENERATOR(ROWCOUNT => 2000000));

-- 件数確認
SELECT COUNT(*) AS ROWS_COUNT FROM N06.HANDS_ON.ORDERS;


-- ハンズオン①
USE ROLE SYSADMIN;
USE DATABASE N06;
USE SCHEMA N06.HANDS_ON;
USE WAREHOUSE N06_WH;

-- 1. 初回クエリ（WHがデータを読み、ローカルキャッシュに載せる）
SELECT COUNT(*), AVG(AMOUNT), MAX(AMOUNT) FROM ORDERS;

-- 1-b. 直前クエリのプロファイル指標をクエリで確認（UIを開かず数値で見る）
--       BYTES_SCANNED が大きい＝実際にデータを読んでいる
SELECT
  QUERY_ID,            -- クエリを一意に識別するID
  BYTES_SCANNED,       -- 実際に読み込んだバイト数（少ないほどキャッシュ/プルーニングが効いている）
  ROWS_PRODUCED,       -- 結果として返した行数
  COMPILATION_TIME,    -- 実行計画の作成（コンパイル）にかかった時間（ミリ秒）
  EXECUTION_TIME,      -- 実際の処理にかかった時間（ミリ秒）
  WAREHOUSE_NAME       -- 使用したウェアハウス名（結果キャッシュ利用時は NULL）
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE QUERY_ID = LAST_QUERY_ID();

-- 2. 同じクエリを再実行（クエリ結果キャッシュが使われる）
SELECT COUNT(*), AVG(AMOUNT), MAX(AMOUNT) FROM ORDERS;

-- 2-b. プロファイル確認：結果キャッシュ再利用なら
--       BYTES_SCANNED = 0 / EXECUTION_TIME ≒ 0 / WAREHOUSE_NAME が NULL
SELECT
  QUERY_ID,
  BYTES_SCANNED,
  EXECUTION_TIME,
  WAREHOUSE_NAME
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE QUERY_ID = LAST_QUERY_ID();

-- 3. クエリ結果キャッシュを無効化
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- 4. 無効化後に再実行（結果キャッシュは使われないがローカルキャッシュは効く）
SELECT COUNT(*), AVG(AMOUNT), MAX(AMOUNT) FROM ORDERS;

-- 4-b. プロファイル確認：今度は WH を使って再計算する（BYTES_SCANNED が再発生）
SET q4 = LAST_QUERY_ID();   -- 直前のデータクエリのIDを保存（4-cでも使う）

SELECT
  QUERY_ID,
  BYTES_SCANNED,
  EXECUTION_TIME,
  WAREHOUSE_NAME
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE QUERY_ID = $q4;

-- 4-c. ローカル(SSD)キャッシュ命中率は TableScan のオペレーター統計から取得
--       （INFORMATION_SCHEMA.QUERY_HISTORY には命中率の列が無いため）
SELECT
  OPERATOR_TYPE,  -- オペレーター種別（TableScan＝テーブル読み取り など）
  OPERATOR_STATISTICS:io:bytes_scanned::number AS bytes_scanned,  -- このオペレーターが読んだバイト数
  ROUND(OPERATOR_STATISTICS:io:percentage_scanned_from_cache::float * 100, 1) AS pct_from_cache  -- ローカル(SSD)キャッシュから読んだ割合(%)
FROM TABLE(GET_QUERY_OPERATOR_STATS($q4))
WHERE OPERATOR_TYPE = 'TableScan';

-- 5. オペレーター単位の詳細プロファイルをクエリで取得
--    （Snowsightの「Query Profile」図と同じ統計をSQLで見る）
--    対象クエリを実行した直後に LAST_QUERY_ID() で取得する
SELECT COUNT(*) FROM ORDERS WHERE AMOUNT > 25000;
SELECT *
FROM TABLE(GET_QUERY_OPERATOR_STATS(LAST_QUERY_ID()));

-- 6. キャッシュ設定を元に戻す
ALTER SESSION SET USE_CACHED_RESULT = TRUE;

-- 7. 直近クエリの実行時間・スキャン量をまとめて確認
SELECT
  QUERY_TEXT,          -- 実行されたSQL文の本文
  EXECUTION_TIME,
  BYTES_SCANNED,
  WAREHOUSE_NAME
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(
  DATEADD('hours', -1, CURRENT_TIMESTAMP()),
  CURRENT_TIMESTAMP()
))
ORDER BY START_TIME DESC
LIMIT 10;

-- ハンズオン②
USE ROLE SYSADMIN;
USE WAREHOUSE N06_WH;

-- 1. 現在のウェアハウス情報を確認
SHOW WAREHOUSES LIKE 'N06_WH';

-- 2. ウェアハウスを手動サスペンド
ALTER WAREHOUSE N06_WH SUSPEND;
-- → 実行中クエリは完了後にサスペンド（ローカルキャッシュは破棄される）

-- 3. サスペンド中にリサイズを試みる（可能！）
ALTER WAREHOUSE N06_WH SET WAREHOUSE_SIZE = 'LARGE';
-- → コマンドは通る。新リソースは再開時にプロビジョニングされる

-- 4. ウェアハウスを再開
ALTER WAREHOUSE N06_WH RESUME;

-- 5. もとのサイズに戻す（コスト節約）
ALTER WAREHOUSE N06_WH SET WAREHOUSE_SIZE = 'X-SMALL';

-- 6. マルチクラスタウェアハウスの設定例
ALTER WAREHOUSE N06_WH SET
  MIN_CLUSTER_COUNT = 1
  MAX_CLUSTER_COUNT = 3
  SCALING_POLICY    = 'ECONOMY';  -- 6分以上ビジーな場合のみ追加クラスタ起動

-- 7. 自動サスペンド・自動再開の設定
ALTER WAREHOUSE N06_WH SET
  AUTO_SUSPEND = 60       -- 60秒アイドルでサスペンド
  AUTO_RESUME  = TRUE;    -- クエリが来たら自動再開

-- 8. クレジット消費履歴を確認
--    ※終了を CURRENT_DATE()（＝今日の0時）にすると、今日ぶんの利用が範囲から外れて
--      結果が0行になりやすい。終了は CURRENT_TIMESTAMP()（現在時刻）にして今日も含める。
--    ※メータリングは集計に最大3時間ほど遅延するため、起動直後はまだ表示されないことがある。
SELECT *
FROM TABLE(INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
  DATEADD('days', -1, CURRENT_TIMESTAMP()),  -- 24時間前から
  CURRENT_TIMESTAMP()                        -- 現在まで（今日の利用も含める）
));


-- ハンズオン③
USE ROLE SYSADMIN;
USE DATABASE N06;
USE SCHEMA N06.HANDS_ON;
USE WAREHOUSE N06_WH;

-- ※ プルーニングを観察する間は結果キャッシュをオフにする
--   （キャッシュが効くとクエリが実行されず、オペレーター統計が空＝「no results」になる）
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- 0. （再実行対策）前回のクラスタリングキーを解除し、「クラスタリング前」の状態に戻す
--     ※初回実行などキーが無いときは何も起きない（エラーが出ても無視して進んでよい）
ALTER TABLE ORDERS DROP CLUSTERING KEY;

-- 1. 【クラスタリング前】日付で絞り込んで集計する
SELECT COUNT(*), SUM(AMOUNT)
FROM ORDERS
WHERE ORDER_DATE BETWEEN '2023-06-01' AND '2023-06-30';

-- 1-b. まず直前のデータクエリのIDを保存し、そのIDでパーティション統計を見る
--      ★IDを保存する理由：統計クエリを単体で再実行すると LAST_QUERY_ID() が
--        「統計クエリ自身」を指し、TableScan が無く「no results」になるため
SET qid = LAST_QUERY_ID();

SELECT
  OPERATOR_STATISTICS:pruning:partitions_scanned::number AS partitions_scanned,  -- 実際に読んだパーティション数
  OPERATOR_STATISTICS:pruning:partitions_total::number   AS partitions_total      -- テーブル全体のパーティション数
FROM TABLE(GET_QUERY_OPERATOR_STATS($qid))
WHERE OPERATOR_TYPE = 'TableScan';

-- 2. ORDER_DATE をクラスタリングキーに設定（この列で物理的に並べ替える）
ALTER TABLE ORDERS CLUSTER BY (ORDER_DATE);

-- 3. 並び具合（整列度）を数値で確認する
--    average_depth が小さい（1に近い）ほどよく整列＝プルーニングが効きやすい
SELECT SYSTEM$CLUSTERING_INFORMATION('ORDERS', '(ORDER_DATE)');

-- 4. 【クラスタリング後】まったく同じ絞り込みをもう一度実行
SELECT COUNT(*), SUM(AMOUNT)
FROM ORDERS
WHERE ORDER_DATE BETWEEN '2023-06-01' AND '2023-06-30';

-- 4-b. 同じようにIDを保存してパーティション数を確認し、手順1-b の値と比べる
--      partitions_scanned が減っていればクラスタリングでプルーニングが改善した証拠
SET qid = LAST_QUERY_ID();
SELECT
  OPERATOR_STATISTICS:pruning:partitions_scanned::number AS partitions_scanned,
  OPERATOR_STATISTICS:pruning:partitions_total::number   AS partitions_total
FROM TABLE(GET_QUERY_OPERATOR_STATS($qid))
WHERE OPERATOR_TYPE = 'TableScan';

-- ※ 確認が終わったら結果キャッシュを元に戻す
ALTER SESSION SET USE_CACHED_RESULT = TRUE;



USE ROLE ACCOUNTADMIN;   -- モニターの作成・割り当てには ACCOUNTADMIN 権限が必要

-- 5. リソースモニターを作成（1か月あたり5クレジットを上限に、段階的に通知・停止）
CREATE OR REPLACE RESOURCE MONITOR N06_MONITOR
  WITH CREDIT_QUOTA = 5            -- この期間で使える上限クレジット数
  FREQUENCY = MONTHLY             -- 集計周期（毎月リセット）
  START_TIMESTAMP = IMMEDIATELY   -- すぐに集計を開始
  TRIGGERS
    ON 75 PERCENT  DO NOTIFY             -- 75%：メール通知のみ（止めない）
    ON 100 PERCENT DO SUSPEND            -- 100%：実行中クエリの完了後にサスペンド
    ON 110 PERCENT DO SUSPEND_IMMEDIATE; -- 110%：実行中クエリも止めて即サスペンド

-- 6. 作ったモニターをウェアハウスに割り当てる（←これをやらないと何も効かない）
ALTER WAREHOUSE N06_WH SET RESOURCE_MONITOR = N06_MONITOR;

-- 7. 設定されたモニターの状態を確認
SHOW RESOURCE MONITORS;



USE ROLE SYSADMIN;

-- 8. テーブルの行数・ストレージサイズを確認（INFORMATION_SCHEMA：即時・短期）
SELECT
  TABLE_NAME,   -- テーブル名
  ROW_COUNT,    -- 行数
  BYTES         -- 圧縮後のストレージサイズ（バイト）
FROM N06.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'HANDS_ON';

-- 9.【SYSADMIN可】重いクエリ（実行時間・スキャン量が大きい）を直近から探す
--    ※ INFORMATION_SCHEMA.QUERY_HISTORY() は SYSADMIN でも参照可・即時反映。
--      ただしスピル量の列（BYTES_SPILLED_*）は持たないので、ここでは実行時間とスキャン量で「重さ」を見る
SELECT
  QUERY_TEXT,
  EXECUTION_TIME / 1000 AS EXEC_SEC,    -- 実行時間（秒）。大きいほど重い
  BYTES_SCANNED,                        -- スキャンしたバイト数。大きいほど重い
  WAREHOUSE_NAME                        -- 実行したウェアハウス名
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(
  DATEADD('hours', -1, CURRENT_TIMESTAMP()),  -- 1時間前から
  CURRENT_TIMESTAMP()                         -- 現在まで
))
ORDER BY EXECUTION_TIME DESC
LIMIT 10;

-- 9-b.【ACCOUNTADMIN必須】スピル（メモリあふれ）が起きたクエリを履歴から探す
--      ※ スピル量の列（BYTES_SPILLED_*）は SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY にのみ存在し、
--        INFORMATION_SCHEMA には無い。この共有DBは ACCOUNTADMIN（または IMPORTED PRIVILEGES 付与
--        ロール）でないと参照できず、反映に数分〜数十分の遅延がある
--      スピルが多い＝メモリ不足。WHサイズアップの候補が見つかる
USE ROLE ACCOUNTADMIN;
SELECT
  QUERY_TEXT,
  EXECUTION_TIME / 1000 AS EXEC_SEC,    -- 実行時間を秒に換算
  BYTES_SPILLED_TO_LOCAL_STORAGE,       -- ローカル(SSD)へあふれたバイト数（多い＝メモリ不足のサイン）
  BYTES_SPILLED_TO_REMOTE_STORAGE,      -- リモートへあふれたバイト数（さらに深刻なメモリ不足）
  WAREHOUSE_SIZE                        -- 実行時のウェアハウスサイズ
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('days', -1, CURRENT_TIMESTAMP())
  AND BYTES_SPILLED_TO_LOCAL_STORAGE > 0
ORDER BY BYTES_SPILLED_TO_LOCAL_STORAGE DESC
LIMIT 10;


-- USE ROLE ACCOUNTADMIN;
-- SELECT
--   QUERY_TEXT,
--   EXECUTION_TIME / 1000 AS EXEC_SEC,
--   BYTES_SPILLED_TO_LOCAL_STORAGE,
--   BYTES_SPILLED_TO_REMOTE_STORAGE,
--   WAREHOUSE_SIZE
-- FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
-- WHERE START_TIME >= DATEADD('days', -1, CURRENT_TIMESTAMP())  -- スピル条件は外す
-- ORDER BY START_TIME DESC
-- LIMIT 10;

-- USE ROLE SYSADMIN;
-- USE WAREHOUSE N06_WH;   -- X-SMALL のまま

-- ALTER SESSION SET USE_CACHED_RESULT = FALSE;  -- キャッシュで素通りしないように

-- -- わざと重い処理：5000万行の乱数文字列を「全件ソート」してメモリをあふれさせる
-- --   ※ QUALIFY で出力は10行に絞るが、ソート自体は全件に対して走るのでスピルする
-- SELECT id, s
-- FROM (
--   SELECT SEQ8() AS id, RANDSTR(100, RANDOM()) AS s
--   FROM TABLE(GENERATOR(ROWCOUNT => 50000000))
-- )
-- QUALIFY ROW_NUMBER() OVER (ORDER BY s) <= 10;