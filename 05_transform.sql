-- 0. 環境セットアップ（DB・スキーマ・ウェアハウスを作成）
USE ROLE SYSADMIN;

CREATE OR REPLACE DATABASE N05;
CREATE OR REPLACE SCHEMA N05.HANDS_ON;
CREATE OR REPLACE WAREHOUSE N05_WH
  WAREHOUSE_SIZE      = 'X-SMALL'
  AUTO_SUSPEND        = 60      -- 60秒アイドルで自動停止
  AUTO_RESUME         = TRUE    -- クエリ実行時に自動起動
  INITIALLY_SUSPENDED = TRUE;   -- 作成時は停止状態

USE DATABASE N05;
USE SCHEMA N05.HANDS_ON;
USE WAREHOUSE N05_WH;

-- ハンズオン①
USE ROLE SYSADMIN;
USE DATABASE N05;
USE SCHEMA N05.HANDS_ON;
USE WAREHOUSE N05_WH;

-- 1. JSON データをVARIANT列に格納
CREATE OR REPLACE TABLE EVENTS AS
SELECT PARSE_JSON('{
  "event_id": 1,
  "user": "Alice",
  "tags": ["sale", "vip", "web"],
  "metadata": {"region": "JP", "score": 95}
}') AS RAW;

-- 2. ドット記法でフィールドにアクセス
SELECT
  RAW:event_id::INTEGER         AS EVENT_ID,
  RAW:user::VARCHAR             AS USERNAME,
  RAW:metadata:region::VARCHAR  AS REGION,
  RAW:metadata:score::INTEGER   AS SCORE
FROM EVENTS;

-- 3. FLATTEN で配列を展開（1タグ＝1行）
SELECT
  e.RAW:event_id::INTEGER AS EVENT_ID,
  f.VALUE::VARCHAR         AS TAG
FROM EVENTS e,
LATERAL FLATTEN(INPUT => e.RAW:tags) f;

-- 4. OUTER => TRUE で空配列でも行を返す
SELECT f.*
FROM TABLE(FLATTEN(
  INPUT => PARSE_JSON('[]'),
  OUTER => TRUE
)) f;
-- → NULL行が1行返る（OUTER=FALSEだと0行）

-- 5. RECURSIVE => TRUE でネストを再帰展開
SELECT f.*
FROM TABLE(FLATTEN(
  INPUT    => PARSE_JSON('{"a":{"b":{"c":42}}}'),
  RECURSIVE => TRUE
)) f;

-- ハンズオン②
-- 0. このハンズオンで使うサンプルデータ：注文テーブル ORDERS
CREATE OR REPLACE TABLE N05.HANDS_ON.ORDERS (
  ORDER_ID  INTEGER,
  CUSTOMER  VARCHAR,
  AMOUNT    NUMBER(10,2)
);

INSERT INTO N05.HANDS_ON.ORDERS (ORDER_ID, CUSTOMER, AMOUNT) VALUES
  (1, 'Alice', 12000),
  (2, 'Bob',    8000),
  (3, 'Alice', 15000),
  (4, 'Carol',  5000),
  (5, 'Bob',   22000),
  (6, 'Dave',   3000);

-- 1. SQLのUDFを作成
CREATE OR REPLACE FUNCTION TAX_AMOUNT(price FLOAT)
RETURNS FLOAT
LANGUAGE SQL
AS '(price * 0.1)';

-- 2. UDF を SQL 文の中で使用（SELECT内で呼び出せる）
SELECT
  ORDER_ID,
  AMOUNT,
  TAX_AMOUNT(AMOUNT) AS TAX,
  AMOUNT + TAX_AMOUNT(AMOUNT) AS TOTAL
FROM N05.HANDS_ON.ORDERS;

-- 3. JavaScriptのUDFを作成
CREATE OR REPLACE FUNCTION CELSIUS_TO_FAHRENHEIT(c FLOAT)
RETURNS FLOAT
LANGUAGE JAVASCRIPT
AS '
  return C * 9/5 + 32;
';

SELECT CELSIUS_TO_FAHRENHEIT(100);  -- 212

-- 4. ウィンドウ関数：累計・ランキング
SELECT
  ORDER_ID,
  CUSTOMER,
  AMOUNT,
  SUM(AMOUNT)   OVER (ORDER BY ORDER_ID) AS RUNNING_TOTAL,
  RANK()        OVER (ORDER BY AMOUNT DESC) AS RANK,
  ROW_NUMBER()  OVER (ORDER BY ORDER_ID)    AS ROW_NUM
FROM N05.HANDS_ON.ORDERS;

-- 5. HyperLogLog で近似ユニーク件数を取得
SELECT APPROX_COUNT_DISTINCT(CUSTOMER) AS APPROX_UNIQUE
FROM N05.HANDS_ON.ORDERS;


-- ハンズオン③
-- 0. このハンズオンで使うサンプルデータ：注文テーブル ORDERS
CREATE OR REPLACE TABLE N05.HANDS_ON.ORDERS (
  ORDER_ID  INTEGER,
  CUSTOMER  VARCHAR,
  AMOUNT    NUMBER(10,2)
);

INSERT INTO N05.HANDS_ON.ORDERS (ORDER_ID, CUSTOMER, AMOUNT) VALUES
  (1, 'Alice', 12000),
  (2, 'Bob',    8000),
  (3, 'Alice', 15000),
  (4, 'Carol',  5000),
  (5, 'Bob',   22000),
  (6, 'Dave',   3000);

-- 1. BERNOULLI（行単位）サンプリング：各行を25%の確率で選択
SELECT * FROM N05.HANDS_ON.ORDERS
  TABLESAMPLE BERNOULLI(25);

-- 2. SYSTEM（ブロック単位）サンプリング
SELECT * FROM N05.HANDS_ON.ORDERS
  TABLESAMPLE SYSTEM(50);

-- 3. 固定行数サンプリング（`n ROWS` と書く。`SAMPLE ROW(2)` は「2%抽出」になり別物）
SELECT * FROM N05.HANDS_ON.ORDERS
  SAMPLE (2 ROWS);  -- 最大2行

-- 4. 内部ステージを作成し、サンプルCSVを書き出す（COPY INTO 用のデータを用意）
CREATE OR REPLACE STAGE N05.HANDS_ON.MY_STAGE
  FILE_FORMAT = (TYPE = CSV);

-- 列順 (名前, 金額, 部門, ID) のサンプルCSVをステージに書き出す（手動アップロード不要）
COPY INTO @N05.HANDS_ON.MY_STAGE/employees.csv
  FROM (
    SELECT * FROM VALUES
      ('Alice', 5000, 'Sales',       101),
      ('Bob',   6000, 'Engineering', 102),
      ('Carol', 7000, 'Sales',       103)
  )
  FILE_FORMAT = (TYPE = CSV COMPRESSION = NONE)
  SINGLE = TRUE
  OVERWRITE = TRUE;

-- 5. COPY INTO でのデータ変換（列並び替え・型キャスト）
-- ステージファイルの列が (名前, 金額, 部門, ID) の順だとして
CREATE OR REPLACE TABLE EMPLOYEES2 (
  ID INTEGER, NAME VARCHAR, DEPT VARCHAR, SALARY NUMBER(10,2)
);

COPY INTO EMPLOYEES2 (ID, NAME, DEPT, SALARY)
  FROM (
    SELECT
      $4::INTEGER,   -- 列順序を変更
      $1::VARCHAR,
      $3::VARCHAR,
      $2::NUMBER(10,2)
    FROM @N05.HANDS_ON.MY_STAGE
  );

-- 6. 3種類のURLを実際に発行して試す（File / Scoped / Pre-signed URL）

-- まずステージ内のファイルを確認
LIST @N05.HANDS_ON.MY_STAGE;

-- ① File URL：期限なしの固定リンク。開くにはSnowflakeログイン＋ステージ権限が必要
SELECT BUILD_STAGE_FILE_URL(@N05.HANDS_ON.MY_STAGE, 'employees.csv') AS FILE_URL;

-- ② Scoped URL：発行から24時間で失効。発行した本人のみ開ける（クエリ内の一時処理向け）
SELECT BUILD_SCOPED_FILE_URL(@N05.HANDS_ON.MY_STAGE, 'employees.csv') AS SCOPED_URL;

-- ③ Pre-signed URL：指定秒数だけ有効（第3引数＝秒）。認証不要でブラウザに貼れば誰でも開ける
SELECT GET_PRESIGNED_URL(@N05.HANDS_ON.MY_STAGE, 'employees.csv', 3600) AS PRESIGNED_URL;

-- （参考）GET_ABSOLUTE_PATH はURLではなく、ステージ内の相対パス文字列を返す
SELECT GET_ABSOLUTE_PATH(@N05.HANDS_ON.MY_STAGE, 'employees.csv') AS ABS_PATH;