
## 無料トライアルアカウント作成時の対応

### ①アカウント作成する
- エディション：Enterprise
- クラウド：AWS
- リージョン：Tokyo

### ②初期設定
1. Snowsightにログイン後、"Project" タブから "Worckspaces" に移動する。
2. My Workspaceから "+Add new" より "SQL File" を作成する。
3. 以下のクエリを実行する。

```sql
-- セカンダリーロールの無効化
USE ROLE SECURITYADMIN;
ALTER USER skitsukawa SET DEFAULT_SECONDARY_ROLES=();

-- GitHub連携用API統合の作成
USE ROLE ACCOUNTADMIN;
CREATE OR REPLACE API INTEGRATION GITHUB_API_INT
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/kitsukawa-s/Snowflake_demo')
    ENABLED = TRUE;
```

### ③Git Workspaceの追加
1. Snowflakeで「Workspaces」を開く
2. 上部のDatabasesタブの横にある+アイコンから「Git workspace」を選択する
3. 以下を入力してCreateする

```
URL：https://github.com/kitsukawa-s/Snowflake_demo
Workspace name：任意
API integration：変更しない（GITHUB_API_INT）
認証方法：Public repository
```



## 橘川備忘録 PAT認証
```sql
-- Secret を格納するスキーマを用意
USE DATABASE USER$SKITSUKAWA;
USE SCHEMA USER$SKITSUKAWA.LOCAL;

-- GitHub PAT を Secret として作成
CREATE OR REPLACE SECRET github_token
    TYPE = PASSWORD
    USERNAME = 'kitsukawa-s'        -- GitHub ユーザー名
    PASSWORD = 'github_pat_xxx';   -- GitHub PAT

CREATE OR REPLACE API INTEGRATION github_api_int
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/kitsukawa-s/Snowflake_demo')
    ALLOWED_AUTHENTICATION_SECRETS = (github_token)
    ENABLED = TRUE;
```