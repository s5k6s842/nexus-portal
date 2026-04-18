#!/usr/bin/env python3
"""
インフラ疎通テストスクリプト
依存ライブラリ: pip install requests psycopg2-binary
"""

import sys
import textwrap
import requests
import psycopg2

# ── 設定 ─────────────────────────────────────────────────────────────────────
QDRANT_URL   = "http://localhost:6333"
OLLAMA_URL   = "http://localhost:11434"
OLLAMA_MODEL = "qwen2:1.5b"
PG_CONFIG    = {
    "host":     "localhost",
    "port":     5432,
    "dbname":   "portal_db",
    "user":     "portal_user",
    "password": "portal_pass",
}

PASS = "\033[32m[OK]  \033[0m"
FAIL = "\033[31m[FAIL]\033[0m"

# ── テスト関数 ────────────────────────────────────────────────────────────────

def test_qdrant() -> bool:
    """Qdrant REST API: コレクション一覧取得（200 OK）"""
    print("─" * 50)
    print("Test 1 : Qdrant /collections")
    try:
        resp = requests.get(f"{QDRANT_URL}/collections", timeout=5)
        resp.raise_for_status()
        collections = resp.json().get("result", {}).get("collections", [])
        names = [c["name"] for c in collections] or ["(コレクションなし)"]
        print(f"{PASS} Status: {resp.status_code}  コレクション: {', '.join(names)}")
        return True
    except requests.exceptions.ConnectionError:
        print(f"{FAIL} Qdrant に接続できません。コンテナが起動しているか確認してください。")
    except Exception as e:
        print(f"{FAIL} {e}")
    return False


def test_ollama() -> bool:
    """Ollama /api/generate: 「こんにちは」への応答確認"""
    print("─" * 50)
    print(f"Test 2 : Ollama /api/generate  (model: {OLLAMA_MODEL})")
    print("        ※ 初回はモデルロードに数十秒かかる場合があります")
    try:
        resp = requests.post(
            f"{OLLAMA_URL}/api/generate",
            json={"model": OLLAMA_MODEL, "prompt": "こんにちは", "stream": False},
            timeout=120,
        )
        resp.raise_for_status()
        raw = resp.json().get("response", "")
        preview = textwrap.shorten(raw, width=60, placeholder="…")
        print(f"{PASS} Status: {resp.status_code}")
        print(f"        応答プレビュー: {preview}")
        return True
    except requests.exceptions.ConnectionError:
        print(f"{FAIL} Ollama に接続できません。コンテナが起動しているか確認してください。")
    except requests.exceptions.Timeout:
        print(f"{FAIL} タイムアウト。モデルが未プル、またはリソース不足の可能性があります。")
    except Exception as e:
        print(f"{FAIL} {e}")
    return False


def test_postgres() -> bool:
    """PostgreSQL: tickets テーブルのレコード数取得"""
    print("─" * 50)
    print("Test 3 : PostgreSQL  tickets テーブル")
    try:
        conn = psycopg2.connect(**PG_CONFIG, connect_timeout=5)
        cur = conn.cursor()

        cur.execute("SELECT COUNT(*) FROM tickets;")
        ticket_count = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM knowledge_base;")
        kb_count = cur.fetchone()[0]

        cur.close()
        conn.close()
        print(f"{PASS} tickets レコード数: {ticket_count}  /  knowledge_base レコード数: {kb_count}")
        return True
    except psycopg2.OperationalError as e:
        print(f"{FAIL} 接続エラー: {e}")
    except psycopg2.errors.UndefinedTable:
        print(f"{FAIL} テーブルが存在しません。init.sql が適用されているか確認してください。")
    except Exception as e:
        print(f"{FAIL} {e}")
    return False


# ── エントリポイント ──────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("=" * 50)
    print("  統合ポータル PoC  インフラ疎通テスト")
    print("=" * 50)

    results = {
        "Qdrant":     test_qdrant(),
        "Ollama":     test_ollama(),
        "PostgreSQL": test_postgres(),
    }

    print("─" * 50)
    print("結果サマリー")
    all_passed = True
    for name, ok in results.items():
        mark = "\033[32m✓\033[0m" if ok else "\033[31m✗\033[0m"
        print(f"  {mark}  {name}")
        if not ok:
            all_passed = False

    print("=" * 50)
    if all_passed:
        print("全テスト合格 — インフラの疎通確認完了")
        sys.exit(0)
    else:
        failed = [k for k, v in results.items() if not v]
        print(f"失敗: {', '.join(failed)}")
        sys.exit(1)
