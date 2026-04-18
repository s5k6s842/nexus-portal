-- ============================================================
-- 統合ポータルシステム PoC 初期化スクリプト
-- ============================================================

-- Dify / n8n 用データベースを作成
-- \gexec は psql がスクリプトを実行する際にのみ有効
SELECT 'CREATE DATABASE dify_db'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'dify_db')\gexec

SELECT 'CREATE DATABASE n8n_db'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n_db')\gexec

-- UUID 生成拡張を有効化
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. tickets テーブル (問い合わせ管理)
-- ============================================================
CREATE TABLE IF NOT EXISTS tickets (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     VARCHAR(64) NOT NULL,
    category    VARCHAR(16) NOT NULL CHECK (category IN ('情シス', '人事', '経理')),
    status      VARCHAR(16) NOT NULL DEFAULT '受付済'
                    CHECK (status IN ('受付済', '対応中', '完了')),
    content     TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 2. knowledge_base テーブル (Q&Aデータ原本)
-- ============================================================
CREATE TABLE IF NOT EXISTS knowledge_base (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    question    TEXT        NOT NULL,
    answer      TEXT        NOT NULL,
    category    VARCHAR(64) NOT NULL,
    status      VARCHAR(16) NOT NULL DEFAULT 'provisional'
                    CHECK (status IN ('provisional', 'approved')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- updated_at を自動更新するトリガー関数
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_knowledge_base_updated_at
    BEFORE UPDATE ON knowledge_base
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- インデックス
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_tickets_status    ON tickets (status);
CREATE INDEX IF NOT EXISTS idx_tickets_category  ON tickets (category);
CREATE INDEX IF NOT EXISTS idx_kb_category       ON knowledge_base (category);
CREATE INDEX IF NOT EXISTS idx_kb_status         ON knowledge_base (status);

-- ============================================================
-- ダミーデータ: tickets (3件)
-- ============================================================
INSERT INTO tickets (user_id, category, status, content) VALUES
(
    'user_001',
    '情シス',
    '受付済',
    '社用PCの新規セットアップを依頼したい。Windows 11で開発環境（VSCode, Docker）の構築をお願いしたい。'
),
(
    'user_002',
    '人事',
    '対応中',
    '育児休業の取得手続きについて確認したい。来月から3ヶ月間取得予定のため、申請書類と手順を教えてほしい。'
),
(
    'user_003',
    '経理',
    '完了',
    '先月提出した交通費精算が未払いのままになっている。承認済みのはずだが振込がされていない。'
);

-- ============================================================
-- ダミーデータ: knowledge_base (3件 / provisional 含む)
-- ============================================================
INSERT INTO knowledge_base (question, answer, category, status) VALUES
(
    'VPNに接続できない場合はどうすればよいですか？',
    '以下の手順で確認してください。\n1. VPNクライアント（GlobalProtect）を再起動する\n2. ネットワーク設定でDNSを 8.8.8.8 に変更して再試行する\n3. 改善しない場合は情シスヘルプデスク（内線: 1234）へ連絡してください。',
    '情シス',
    'approved'
),
(
    '有給休暇の残日数を確認するにはどうすればよいですか？',
    '社員ポータル（https://portal.internal/hr）にログイン後、「勤怠管理」→「有給残日数」から確認できます。月次で更新されるため、直近の取得分が反映されるまで翌月初になる場合があります。',
    '人事',
    'approved'
),
(
    '経費精算の締め切り日と支払いサイクルを教えてください。',
    '経費精算は毎月末日締め、翌月25日払いです。※現在確認中の情報のため、正式な回答は経理部に問い合わせてください。',
    '経理',
    'provisional'
);
