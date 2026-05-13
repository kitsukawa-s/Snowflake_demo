/* ハンズオン① */
-- 1. 現在のロールを確認
SELECT CURRENT_ROLE();

-- 2. ロールをACCOUNTADMINに切り替え
USE ROLE ACCOUNTADMIN;

-- 3. 自分に付与されているロールを確認
SHOW GRANTS TO USER <自分のユーザー名>;

-- 4. 各システムロールで見えるオブジェクトを確認
USE ROLE SYSADMIN;
SHOW WAREHOUSES;
SHOW DATABASES;

USE ROLE SECURITYADMIN;
SHOW USERS;
SHOW ROLES;

USE ROLE USERADMIN;
SHOW USERS;    -- USERADMINが所有するユーザーのみ表示
SHOW ROLES;    -- USERADMINが所有するロールのみ表示

-- 5. スキーマの権限を確認する

SHOW GRANTS ON SCHEMA TRAINING_DB.HANDS_ON;
USE ROLE SYSADMIN;

/* ハンズオン② */
-- USERADMINで作業する
USE ROLE USERADMIN;

-- 1. カスタムロールを作成
CREATE ROLE DBA_ROLE;

-- 2. DBA_ROLEをSYSADMINに付与（ベストプラクティス）
--    → SYSADMINがカスタムロール配下のオブジェクトを管理できるようになる
GRANT ROLE DBA_ROLE TO ROLE SYSADMIN;

-- 3. ユーザー作成
CREATE USER MONICA
  PASSWORD    = 'Abc123!!'
  LOGIN_NAME  = 'monica'
  DEFAULT_ROLE = DBA_ROLE
  MUST_CHANGE_PASSWORD = TRUE;

-- 4. MonicaにDBA_ROLEを付与
GRANT ROLE DBA_ROLE TO USER MONICA;

-- 5. 付与を確認
SHOW GRANTS TO USER MONICA;
SHOW GRANTS TO ROLE DBA_ROLE;

/* ハンズオン③ */
-- 0) 役割分担の前提
--    - ロール/ユーザー管理：SECURITYADMIN / USERADMIN
--    - DB/Schemaなどオブジェクト作成：SYSADMIN

-- 1) ロール階層を作成（アクセスロール → 機能的ロール → SYSADMIN）
USE ROLE USERADMIN;

CREATE ROLE READER;
CREATE ROLE EDITOR;
CREATE ROLE CREATOR;

-- 継承（下位→上位へ積み上げ）
GRANT ROLE READER  TO ROLE EDITOR;
GRANT ROLE EDITOR  TO ROLE CREATOR;
GRANT ROLE CREATOR TO ROLE DBA_ROLE;
GRANT ROLE DBA_ROLE TO ROLE SYSADMIN;

-- 3) SYSADMINがDB/Schemaを作成（所有者=SYSADMIN）
USE ROLE SYSADMIN;
CREATE DATABASE RBAC_DB;
CREATE SCHEMA RBAC_DB.APP;

-- 4) アクセスロールに必要最小限の権限を付与（ここが「アクセスロール」の役目）
-- READER（読むための最低限）
GRANT USAGE ON DATABASE RBAC_DB TO ROLE READER;
GRANT USAGE ON SCHEMA RBAC_DB.APP TO ROLE READER;

-- CREATOR（作成権限）
GRANT CREATE TABLE ON SCHEMA RBAC_DB.APP TO ROLE CREATOR;

-- ==== monica切り替え ====
-- 5) MONICAがRDB_ROLEでテーブル作成できる（RDB_ROLE→CREATORを継承しているため）
USE ROLE RDB_ROLE;
CREATE TABLE RBAC_DB.APP.T1 (ID INT, NAME STRING);

-- ==== default userに切り替え ===
-- 6) 書き込み/参照権限をアクセスロールに付与し、MONICAが操作できることを確認
USE ROLE SECURITYADMIN;
GRANT SELECT ON TABLE RBAC_DB.APP.T1 TO ROLE READER;
GRANT INSERT, UPDATE, DELETE ON TABLE RBAC_DB.APP.T1 TO ROLE EDITOR;

-- ==== monica切り替え ====
USE ROLE RDB_ROLE;
INSERT INTO RBAC_DB.APP.T1 VALUES (1, 'Test');
SELECT * FROM RBAC_DB.APP.T1;

-- ==== default userに切り替え ===
-- 7) 確認：SYSADMIN は RDB_ROLE の上位ロールなので、同じ権限を継承して SELECT できる
USE ROLE SYSADMIN;
SELECT * FROM RBAC_DB.APP.T1;  -- → 成功（RDB_ROLE配下の権限を継承）

-- ============================================================
-- 8) 将来権限（Future Grants）の確認
-- ============================================================

-- ---- Step 1: 将来権限を設定する「前」にテーブルを作成 ----
USE ROLE SYSADMIN;
CREATE TABLE RBAC_DB.APP.T2 (ID INT, VALUE STRING);
INSERT INTO RBAC_DB.APP.T2 VALUES (1, 'Before Future Grant');

-- ==== monica切り替え ====
-- ---- Step 2: MONICAがRDB_ROLEでT2を参照 → 失敗（SELECTがGRANTされていない） ----
USE ROLE RDB_ROLE;
SELECT * FROM RBAC_DB.APP.T2;

-- ==== default userに切り替え ====
-- ---- Step 3: SECURITYADMINで将来権限を設定 ----
-- ※ SECURITYADMINはグローバルMANAGE GRANTS権限により、
--   USAGE権限がなくてもオブジェクトの権限管理（GRANT/REVOKE）が可能
--   （データ自体にはアクセスできない＝職務分離の設計）
USE ROLE SECURITYADMIN;

-- RBAC_DB.APP スキーマに今後作成される全テーブルに対して、
-- READER に SELECT、EDITOR に INSERT/UPDATE/DELETE を自動付与
GRANT SELECT ON FUTURE TABLES IN SCHEMA RBAC_DB.APP TO ROLE READER;
GRANT INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA RBAC_DB.APP TO ROLE EDITOR;

-- 設定内容を確認
SHOW FUTURE GRANTS IN SCHEMA RBAC_DB.APP;

-- ---- Step 4: 将来権限を設定した「後」にテーブルを作成 ----
USE ROLE SYSADMIN;
CREATE TABLE RBAC_DB.APP.T3 (ID INT, VALUE STRING);
INSERT INTO RBAC_DB.APP.T3 VALUES (1, 'After Future Grant');

-- ==== monica切り替え ====
-- ---- Step 5: MONICAがRDB_ROLEでT3を参照 → 成功（将来権限で自動GRANT済み） ----
USE ROLE RDB_ROLE;
SELECT * FROM RBAC_DB.APP.T3;
-- → 成功！FUTURE GRANTSにより自動でSELECTが付与されている

-- ---- Step 6: 比較 - T2はまだ参照できない（将来権限は過及しない） ----
SELECT * FROM RBAC_DB.APP.T2;

-- ==== default userに切り替え ====
-- ---- Step 7: 確認 - T2とT3の権限状態を比較 ----
USE ROLE SYSADMIN;
SHOW GRANTS ON TABLE RBAC_DB.APP.T2;  -- → READERへのSELECTなし
SHOW GRANTS ON TABLE RBAC_DB.APP.T3;  -- → READERへのSELECTが自動付与済み