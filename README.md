# 社内向け統合ポータルシステム PoC

ローカル完結のRAGチャットボットと部署への問い合わせルーティングを統合したシステムのPoC環境です。

## ファイル構成

```
.
├── docker-compose.yml   # 各コンテナの定義（PostgreSQL / NocoDB / Qdrant / Ollama）
├── init.sql             # DB初期化スクリプト（テーブル定義 + ダミーデータ）
└── README.md            # 本ドキュメント
```

---

## 技術スタック

| サービス | 役割 | ポート |
|---|---|---|
| PostgreSQL | メインDB | 5432 |
| NocoDB | DB管理UI | 8080 |
| Qdrant | ベクトルDB | 6333 / 6334 |
| Ollama | LLMエンジン | 11434 |

---

## 前提条件

- Docker Desktop（または Docker Engine + Compose Plugin）がインストール済みであること
- 空きディスク容量：モデルダウンロード含め **最低 5GB 以上**

---

## 起動手順

### 1. プロジェクトディレクトリへ移動

```bash
cd /path/to/your/project
```

### 2. 全コンテナをバックグラウンドで起動

```bash
docker compose up -d
```

> 初回は各イメージのプルと Ollama のモデルダウンロード（約 1GB）が走るため、**5〜10 分程度かかります。**

### 3. 起動状況の確認

```bash
# 全コンテナのステータス確認
docker compose ps

# Ollama のモデルプル進捗をリアルタイム確認
docker compose logs -f ollama
```

`[ollama-init] Model ready.` が表示されれば準備完了です。

### 4. 各サービスへのアクセス

| サービス | URL | 備考 |
|---|---|---|
| NocoDB | http://localhost:8080 | 初回はアカウント作成が必要 |
| Qdrant Dashboard | http://localhost:6333/dashboard | ベクトルDB管理UI |
| Ollama API | http://localhost:11434 | REST API エンドポイント |
| PostgreSQL | localhost:5432 | `portal_user` / `portal_pass` / `portal_db` |

### 5. Ollama 動作確認

```bash
curl http://localhost:11434/api/generate -d '{
  "model": "qwen2:1.5b",
  "prompt": "日本語で自己紹介してください",
  "stream": false
}'
```

---

## 停止・削除

```bash
# コンテナ停止（データは保持）
docker compose down

# データも含めて完全削除
docker compose down -v
```

---

## Ollama モデルの変更

デフォルトは `qwen2:1.5b` を使用しています。変更する場合は `docker-compose.yml` の `command` 内のモデル名を書き換えてください。

| モデル | サイズ | 特徴 |
|---|---|---|
| `qwen2:1.5b` | ~934 MB | **デフォルト採用**。軽量・日本語対応 |
| `gemma2:2b` | ~1.6 GB | Google製、品質高め |
| `llama3.2:1b` | ~1.3 GB | Meta製、英語中心 |

---

## GPU を使用する場合

`docker-compose.yml` 内の Ollama サービスにある `deploy` セクションのコメントを外し、`OLLAMA_NUM_GPU` を削除してください。

```yaml
environment:
  # OLLAMA_NUM_GPU: "0"  # この行を削除
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```
