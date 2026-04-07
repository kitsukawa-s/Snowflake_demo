## 初期設定
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