# Nexus Portal — システム構成ドキュメント

このドキュメントはAIが本システムを理解・継続支援するための構成リファレンスです。

---

## 概要

社内向け統合ポータルシステムのPoC環境。  
ローカル完結のRAGチャットボットと、各部署（情シス・人事・経理）への問い合わせルーティングを統合することが目的。  
全サービスはDockerコンテナで稼働し、外部ネットワーク不要のオフライン環境で動作する。

---

## リポジトリ

- GitHub: `git@github.com:s5k6s842/nexus-portal.git`
- ローカルパス: `/Users/tomoyatakara/Documents/claude_code/nexus-portal/`
- Dockerプロジェクト名: `claude_code`（`docker-compose.yml` の `name` フィールドで固定）

---

## ファイル構成

```
nexus-portal/
├── docker-compose.yml   # 全コンテナ定義
├── init.sql             # PostgreSQL 初期化（テーブル定義・ダミーデータ・DB作成）
├── test_connections.py  # インフラ疎通テストスクリプト
├── README.md            # 起動手順・アクセス方法
└── SYSTEM.md            # 本ドキュメント
```

---

## コンテナ一覧

| コンテナ名 | イメージ | ホストポート | 役割 |
|---|---|---|---|
| `portal-postgres` | postgres:16-alpine | 5432 | メインRDB（3DB共用） |
| `portal-nocodb` | nocodb/nocodb:latest | 8080 | DB管理GUI |
| `portal-qdrant` | qdrant/qdrant:latest | 6333(HTTP) / 6334(gRPC) | ベクトルDB |
| `portal-ollama` | ollama/ollama:latest | 11434 | LLMエンジン（CPU動作） |
| `portal-redis` | redis:7-alpine | 6379 | Difyキュー・キャッシュ |
| `portal-dify-api` | langgenius/dify-api:latest | 5001 | DifyバックエンドAPI |
| `portal-dify-worker` | langgenius/dify-api:latest | なし | Celery非同期ワーカー |
| `portal-dify-plugin-daemon` | langgenius/dify-plugin-daemon:0.5.8-local | 5002 | プラグイン管理デーモン |
| `portal-dify-sandbox` | langgenius/dify-sandbox:latest | なし | コード実行サンドボックス |
| `portal-dify-web` | langgenius/dify-web:latest | 3000 | Dify管理UI（Next.js） |
| `portal-n8n` | n8nio/n8n:latest | 5678 | ワークフロー自動化 |

全コンテナは `portal-net`（bridgeネットワーク）に参加。コンテナ間通信はサービス名で解決する（例: `http://qdrant:6333`）。

---

## アクセスURL一覧

| サービス | URL | 認証 |
|---|---|---|
| Dify（RAGハブ） | http://localhost:3000 | 管理者アカウント（初回セットアップ済み） |
| n8n（ワークフロー） | http://localhost:5678 | `admin` / `n8n_admin_pass` |
| NocoDB（DB管理） | http://localhost:8080 | 初回登録済みアカウント |
| Qdrant Dashboard | http://localhost:6333/dashboard | 認証なし |
| Ollama API | http://localhost:11434 | 認証なし |
| PostgreSQL | localhost:5432 | 下記DB認証情報参照 |

---

## PostgreSQL データベース構成

単一のPostgreSQLインスタンス内に3つのデータベースが共存する。

| DB名 | 用途 | 接続ユーザー |
|---|---|---|
| `portal_db` | アプリケーションデータ（tickets・knowledge_base）+ NocoDB | `portal_user` |
| `dify_db` | Dify内部データ（マイグレーション済み） | `portal_user` |
| `n8n_db` | n8n内部データ | `portal_user` |

**接続情報:**
- Host: `localhost`（外部）/ `postgres`（コンテナ内部）
- Port: `5432`
- User: `portal_user`
- Password: `portal_pass`

---

## portal_db テーブル定義

### tickets（問い合わせ管理）

| カラム | 型 | 制約 |
|---|---|---|
| `id` | UUID | PK, `gen_random_uuid()` |
| `user_id` | VARCHAR(64) | NOT NULL |
| `category` | VARCHAR(16) | CHECK IN ('情シス','人事','経理') |
| `status` | VARCHAR(16) | CHECK IN ('受付済','対応中','完了'), DEFAULT '受付済' |
| `content` | TEXT | NOT NULL |
| `created_at` | TIMESTAMPTZ | DEFAULT NOW() |

### knowledge_base（Q&A原本）

| カラム | 型 | 制約 |
|---|---|---|
| `id` | UUID | PK, `gen_random_uuid()` |
| `question` | TEXT | NOT NULL |
| `answer` | TEXT | NOT NULL |
| `category` | VARCHAR(64) | NOT NULL |
| `status` | VARCHAR(16) | CHECK IN ('provisional','approved'), DEFAULT 'provisional' |
| `created_at` | TIMESTAMPTZ | DEFAULT NOW() |
| `updated_at` | TIMESTAMPTZ | トリガーで自動更新 |

---

## Ollama モデル

| モデル名 | サイズ | 用途 |
|---|---|---|
| `qwen2:1.5b` | 934MB | 起動時に自動プル（軽量・日本語対応） |
| `qwen2.5:7b` | 4.7GB | 手動プル済み・本番推論用 |

Difyからは `http://ollama:11434` でアクセスする。  
GPUなし・CPUモード（`OLLAMA_NUM_GPU=0`）で動作。GPU使用時は `docker-compose.yml` の `deploy` セクションのコメントを外し、`OLLAMA_NUM_GPU` を削除する。

---

## Dify 内部アーキテクチャ

```
[dify-web :3000]
      │ HTTP
[dify-api :5001] ──── [dify-worker] (Celery / 非同期処理)
      │                     │
      ├── postgres:5432 (dify_db)
      ├── redis:6379 (DB=0 キャッシュ / DB=1 Celeryキュー)
      ├── qdrant:6333 (ベクトル検索)
      ├── ollama:11434 (LLM推論)
      ├── dify-sandbox:8194 (コード実行)
      └── dify-plugin-daemon:5002 (プラグイン管理)

[dify-plugin-daemon :5002]
      ├── postgres:5432 (dify_db)
      └── redis:6379 (DB=2)
```

---

## Dify セットアップ済み情報

- 管理者メールアドレス: `s5k6s842@gmail.com`
- DBマイグレーション: 手動実行済み（`flask db upgrade`）
- ストレージパス: `/app/api/storage`（`dify_storage` ボリューム）
- ベクトルDB: Qdrant（`http://qdrant:6333`）
- プラグインデーモン: 正常稼働中（`0.5.8-local`）

---

## Dockerボリューム一覧

| ボリューム名 | マウント先 | 用途 |
|---|---|---|
| `claude_code_postgres_data` | `/var/lib/postgresql/data` | PostgreSQLデータ永続化 |
| `claude_code_nocodb_data` | `/usr/app/data` | NocoDB設定永続化 |
| `claude_code_qdrant_data` | `/qdrant/storage` | ベクトルデータ永続化 |
| `claude_code_ollama_data` | `/root/.ollama` | モデルファイル永続化 |
| `claude_code_redis_data` | `/data` | Redisスナップショット |
| `claude_code_n8n_data` | `/home/node/.n8n` | n8nワークフロー永続化 |
| `claude_code_dify_storage` | `/app/api/storage` / `/app/storage` | Difyファイル・プラグイン |

---

## 既知の問題と解決済みトラブル

| 問題 | 原因 | 解決策 |
|---|---|---|
| Dify初回セットアップ画面が固まる | DBマイグレーション未実行 | `docker exec portal-dify-api flask db upgrade` |
| セットアップボタンが反応しない | `/app/api/storage` の書き込み権限エラー | `dify-api` / `dify-worker` に `user: root` を追加 |
| Plugin daemon エラーが出続ける | プラグインデーモンコンテナが未定義 | `dify-plugin-daemon:0.5.8-local` を追加。`latest`タグは存在しない |
| `docker compose ps` で空欄になる | ディレクトリ移動によりプロジェクト名が変わった | `docker-compose.yml` に `name: claude_code` を追加 |

---

## よく使うコマンド

```bash
# 全コンテナ状態確認
docker compose ps

# 全コンテナ起動
docker compose up -d

# 全コンテナ停止（データ保持）
docker compose down

# 特定サービスのログ確認
docker compose logs -f dify-api

# PostgreSQLに接続
docker compose exec postgres psql -U portal_user -d portal_db

# Dify DBマイグレーション（新規環境構築時）
docker exec portal-dify-api flask db upgrade

# 疎通テスト
python3 test_connections.py
```

---

## 今後の拡張予定

- Appsmith（フロントエンド）コンテナの追加（ポート: 8000）
- Dify上でのRAGパイプライン構築
- n8nによるチケット自動ルーティングワークフロー設定
- knowledge_baseの `approved` データをQdrantに同期するバッチ処理
