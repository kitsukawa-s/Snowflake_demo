/* ハンズオン① */
-- 1. 作業用テーブルを作成
USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE TRAINING_DB;
USE SCHEMA HANDS_ON;

CREATE OR REPLACE TABLE EMPLOYEES (
  ID        INTEGER,
  NAME      VARCHAR(100),
  DEPT      VARCHAR(50),
  SALARY    NUMBER(10,2)
);

-- 2. 名前付き内部ステージを作成
CREATE OR REPLACE STAGE MY_STAGE
  FILE_FORMAT = (TYPE = 'CSV' SKIP_HEADER = 1);

-- 3. Snowsight の「Data > Add Data」または PUT コマンドでCSVをアップロード
-- （SnowSQLの場合）
-- PUT file:///path/to/employees.csv @MY_STAGE;

-- 4. ステージのファイル一覧を確認
LIST @MY_STAGE;

-- 5. VALIDATION_MODE でエラー確認（実際にはロードしない）
COPY INTO EMPLOYEES
  FROM @MY_STAGE
  VALIDATION_MODE = 'RETURN_ERRORS';

-- 6. 実際にロード
COPY INTO EMPLOYEES FROM @MY_STAGE;

-- 7. ロード結果確認
SELECT * FROM EMPLOYEES;

/* ハンズオン② */
-- 1. VARIANT列を持つテーブルを作成
CREATE OR REPLACE TABLE JSON_DATA (RAW_DATA VARIANT);

-- 2. JSON用ファイルフォーマットを作成（大きな配列対策）
CREATE OR REPLACE FILE FORMAT JSON_FORMAT
  TYPE = 'JSON'
  STRIP_OUTER_ARRAY = TRUE;  -- 外側の配列 [ ] を除去し各要素を1行として扱う

-- 3. JSONステージを作成
CREATE OR REPLACE STAGE JSON_STAGE
  FILE_FORMAT = JSON_FORMAT;

-- 4. JSONファイルをアップロードしてロード
-- （例：[{"id":1,"name":"Alice"},{"id":2,"name":"Bob"}] のようなJSONファイル）
COPY INTO JSON_DATA FROM @JSON_STAGE;

-- 5. JSONデータを展開して参照
SELECT
  RAW_DATA:id::INTEGER   AS ID,
  RAW_DATA:name::VARCHAR AS NAME
FROM JSON_DATA;

/* ハンズオン③ */
-- 1. CSVとして複数ファイルにアンロード（デフォルト）
COPY INTO @MY_STAGE/export/
  FROM EMPLOYEES
  FILE_FORMAT = (TYPE = 'CSV' COMPRESSION = NONE);

-- 2. 単一ファイルにアンロード
COPY INTO @MY_STAGE/export_single/employees_all.csv
  FROM EMPLOYEES
  FILE_FORMAT = (TYPE = 'CSV' COMPRESSION = NONE)
  SINGLE = TRUE
  OVERWRITE = TRUE;

-- 3. アンロードされたファイルを確認
LIST @MY_STAGE/export/;

-- 4. ステージからデータを参照（ロードせずに）
SELECT $1, $2, $3, $4
FROM @MY_STAGE/export/;


-- Snowpipe の定義例（Auto_Ingest = FALSE：REST APIで手動トリガー）
CREATE OR REPLACE PIPE MY_PIPE
  AUTO_INGEST = FALSE
  AS
  COPY INTO EMPLOYEES FROM @MY_STAGE;

-- パイプの状態確認
SHOW PIPES;
SELECT SYSTEM$PIPE_STATUS('MY_PIPE');