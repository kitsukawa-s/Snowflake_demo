USE ROLE SYSADMIN;
CREATE OR REPLACE DATABASE N03;
CREATE OR REPLACE SCHEMA N03.HANDS_ON;
CREATE OR REPLACE WAREHOUSE N03_WH
  WAREHOUSE_SIZE    = 'X-SMALL'
  AUTO_SUSPEND      = 60        -- 60秒アイドルで自動停止
  AUTO_RESUME       = TRUE     -- クエリ実行時に自動起動
  INITIALLY_SUSPENDED = TRUE;   -- 作成時は停止状態

/* ハンズオン① */
-- 1. 作業用テーブルを作成
USE ROLE SYSADMIN;
USE WAREHOUSE N03_WH;
USE DATABASE N03;
USE SCHEMA HANDS_ON;

CREATE OR REPLACE TABLE EMPLOYEES (
  ID        INTEGER,
  NAME      VARCHAR(100),
  DEPT      VARCHAR(50),
  SALARY    NUMBER(10,2)
);

-- 2. 名前付き内部ステージを作成
CREATE OR REPLACE STAGE CSV_STAGE
  FILE_FORMAT = (TYPE = 'CSV' SKIP_HEADER = 1);

-- 3. Snowsight の「Data > Add Data」または PUT コマンドでCSVをアップロード
-- （SnowSQLの場合）
-- PUT file:///path/to/employees.csv @CSV_STAGE;

-- 4. ステージのファイル一覧を確認
LIST @CSV_STAGE;

-- 5. VALIDATION_MODE でエラー確認（実際にはロードしない）
COPY INTO EMPLOYEES
  FROM @CSV_STAGE/EMPLOYEE.csv -- LISTコマンドで取得した対象のファイル名を指定する。
  VALIDATION_MODE = 'RETURN_ERRORS';

-- 6. 実際にロード
COPY INTO EMPLOYEES FROM @CSV_STAGE/EMPLOYEE.csv;　-- LISTコマンドで取得した対象のファイル名を指定する。

-- 7. ロード結果確認
SELECT * FROM EMPLOYEES;

/* ハンズオン② */
-- 1. ステージを作成（ファイルフォーマットは COPY 時に指定する）
CREATE OR REPLACE STAGE JSON_STAGE;

-- 2. 上記のJSONファイルを @JSON_STAGE にアップロード
--    Snowsight の「Data > Add Data」または PUT コマンドを使用
LIST @JSON_STAGE;

/*
パターンA：STRIP_OUTER_ARRAY = FALSE（デフォルト）
*/
-- 配列をそのまま1つのVARIANT値として取り込む
CREATE OR REPLACE TABLE JSON_FALSE (RAW_DATA VARIANT);

COPY INTO JSON_FALSE
  FROM @JSON_STAGE
  FILE_FORMAT = (TYPE = 'JSON' STRIP_OUTER_ARRAY = FALSE);

-- 行数を確認 → 配列1個=1行なので「1行」だけ
SELECT COUNT(*) AS ROW_COUNT FROM JSON_FALSE;   -- => 1

-- 中身：配列まるごとが1セルに入っている
SELECT RAW_DATA FROM JSON_FALSE;

-- 各要素を取り出すには FLATTEN による展開が必要
SELECT
  f.value:id::INTEGER   AS ID,
  f.value:name::VARCHAR AS NAME
FROM JSON_FALSE,
     LATERAL FLATTEN(INPUT => RAW_DATA) f;

/*
パターンB：STRIP_OUTER_ARRAY = TRUE
*/
-- 外側の配列 [ ] を外し、各要素を1行として取り込む
CREATE OR REPLACE TABLE JSON_TRUE (RAW_DATA VARIANT);

COPY INTO JSON_TRUE
  FROM @JSON_STAGE
  FILE_FORMAT = (TYPE = 'JSON' STRIP_OUTER_ARRAY = TRUE);

-- 行数を確認 → 要素数ぶんの行になる
SELECT COUNT(*) AS ROW_COUNT FROM JSON_TRUE;   -- => 3

-- 各行にオブジェクトが1つずつ入るので、そのまま参照できる（FLATTEN不要）
SELECT
  RAW_DATA:id::INTEGER   AS ID,
  RAW_DATA:name::VARCHAR AS NAME
FROM JSON_TRUE;

/* ハンズオン③ */
-- 0. 分割を体験するためにデータを増量（10万行の例）
CREATE OR REPLACE TABLE EMPLOYEES_BIG AS
SELECT
  e.ID + seq4() AS ID,
  e.NAME,
  e.DEPT,
  e.SALARY
FROM EMPLOYEES e
CROSS JOIN TABLE(GENERATOR(ROWCOUNT => 100000));

SELECT count(*) FROM EMPLOYEES_BIG;

-- 1. CSVとして複数ファイルにアンロード（デフォルト）
COPY INTO @CSV_STAGE/export/
  FROM EMPLOYEES_BIG
  FILE_FORMAT = (TYPE = 'CSV' COMPRESSION = NONE)
  MAX_FILE_SIZE = 200000
  OVERWRITE = TRUE; -- 例：200KB（小さくして分割を発生させる）

-- 2. 単一ファイルにアンロード
COPY INTO @CSV_STAGE/export_single/employees_all.csv
  FROM EMPLOYEES_BIG
  FILE_FORMAT = (TYPE = 'CSV' COMPRESSION = NONE)
  SINGLE = TRUE
  MAX_FILE_SIZE = 100000000
  OVERWRITE = TRUE;

-- 3. アンロードされたファイルを確認
LIST @CSV_STAGE/export/;
LIST @CSV_STAGE/export_single/;

-- 4. ステージからデータを参照（ロードせずに）
SELECT $1 as id, $2, $3, $4
FROM @CSV_STAGE/export/;



-- Snowpipe の定義例（Auto_Ingest = FALSE：REST APIで手動トリガー）
CREATE OR REPLACE PIPE MY_PIPE
  AUTO_INGEST = FALSE
  AS
  COPY INTO EMPLOYEES FROM @CSV_STAGE;

-- パイプの状態確認
SHOW PIPES;
SELECT SYSTEM$PIPE_STATUS('MY_PIPE');