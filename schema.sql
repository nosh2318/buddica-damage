-- ============================================================
-- BUDDICA 車両デジタルツイン スキーマ（高松店）
-- Supabase SQL Editor で実行
-- ============================================================

-- ============================================================
-- 表示レイヤー: vehicle_twins
-- UIが直接参照する「今の状態」
-- current_damages は check_events の確定後に上書き更新される
-- ============================================================
CREATE TABLE IF NOT EXISTS vehicle_twins (
  id              TEXT PRIMARY KEY,           -- 'V-001', 'V-002' ...
  store           TEXT NOT NULL DEFAULT 'takamatsu',
  plate           TEXT,                       -- 香川500さ12-34
  model           TEXT,                       -- 車名
  year            INTEGER,
  color           TEXT,

  -- 現在のステータス
  status          TEXT NOT NULL DEFAULT 'ready',
    -- ready       : 空車・清潔
    -- out         : 貸出中
    -- returning   : 返却待ち（お客様が戻ってきた）
    -- maintenance : 整備中

  -- 現在の予約情報
  current_resv_no TEXT,
  current_customer TEXT,

  -- 現在の傷状態（これがUIに表示される唯一の真実）
  current_damages JSONB NOT NULL DEFAULT '[]',

  -- 統計
  odometer        INTEGER DEFAULT 0,
  rental_count    INTEGER DEFAULT 0,

  -- 最新イベントへのポインタ（チェーンの先頭）
  last_event_id   UUID,
  last_check_at   TIMESTAMPTZ,
  last_check_staff TEXT,

  -- ロック（排他制御）
  locked_by        TEXT,
  locked_at        TIMESTAMPTZ,

  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);


-- ============================================================
-- チェーンレイヤー: check_events
-- 追記のみ。更新・削除禁止。廃車まで繋がり続ける。
-- ============================================================
CREATE TABLE IF NOT EXISTS check_events (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id      TEXT NOT NULL REFERENCES vehicle_twins(id),

  -- イベント種別
  event_type      TEXT NOT NULL,
    -- 'checkout' : 出庫チェック（貸出前）
    -- 'return'   : 返却チェック（返却後）
    -- 'repair'   : 修理完了記録
    -- 'initial'  : 初期登録

  -- 予約・顧客情報
  resv_no         TEXT,
  customer_name   TEXT,
  customer_email  TEXT,
  staff           TEXT NOT NULL,

  -- その時点の傷の完全スナップショット（全件）
  damages_snapshot JSONB NOT NULL DEFAULT '[]',

  -- このイベントで新規検出された傷
  new_damages     JSONB NOT NULL DEFAULT '[]',

  -- AIによる動画解析結果
  video_url       TEXT,
  ai_raw_result   JSONB,
  ai_confidence   NUMERIC(5,2),

  -- スタッフ承認
  staff_confirmed BOOLEAN DEFAULT FALSE,
  confirmed_at    TIMESTAMPTZ,

  notes           TEXT,

  -- チェーン接続
  prev_event_id   UUID REFERENCES check_events(id),

  created_at      TIMESTAMPTZ DEFAULT NOW()
);


-- ============================================================
-- 修理記録テーブル
-- ============================================================
CREATE TABLE IF NOT EXISTS repair_records (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id      TEXT NOT NULL,
  store           TEXT NOT NULL DEFAULT 'takamatsu',
  damage_id       TEXT,
  damage_location TEXT,
  damage_type     TEXT,
  damage_severity TEXT,
  damage_desc     TEXT,
  repair_type     TEXT DEFAULT 'internal',
  repair_date     DATE DEFAULT CURRENT_DATE,
  repair_cost     INTEGER DEFAULT 0,
  repair_shop     TEXT,
  notes           TEXT,
  staff           TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);


-- ============================================================
-- インデックス
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_check_events_vehicle  ON check_events(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_check_events_created  ON check_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_check_events_prev     ON check_events(prev_event_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_twins_store   ON vehicle_twins(store);
CREATE INDEX IF NOT EXISTS idx_vehicle_twins_status  ON vehicle_twins(status);
CREATE INDEX IF NOT EXISTS idx_repair_records_vehicle ON repair_records(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_repair_records_store   ON repair_records(store);


-- ============================================================
-- RLS（読み書き許可）
-- ============================================================
ALTER TABLE vehicle_twins  ENABLE ROW LEVEL SECURITY;
ALTER TABLE check_events   ENABLE ROW LEVEL SECURITY;
ALTER TABLE repair_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "vt_all"  ON vehicle_twins  FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "ce_all"  ON check_events   FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "rr_all"  ON repair_records FOR ALL USING (true) WITH CHECK (true);


-- ============================================================
-- チェーンを辿るビュー（最新10件）
-- ============================================================
CREATE OR REPLACE VIEW vehicle_chain AS
SELECT
  e.id,
  e.vehicle_id,
  e.event_type,
  e.resv_no,
  e.customer_name,
  e.staff,
  jsonb_array_length(e.damages_snapshot) AS total_damages,
  jsonb_array_length(e.new_damages)      AS new_damage_count,
  e.staff_confirmed,
  e.prev_event_id,
  e.created_at,
  v.plate,
  v.model
FROM check_events e
JOIN vehicle_twins v ON e.vehicle_id = v.id
ORDER BY e.created_at DESC;


-- ============================================================
-- 高松店: 車両データは空（後で登録）
-- 登録例:
-- INSERT INTO vehicle_twins (id, store, plate, model, year, color)
-- VALUES ('TKM-001', 'takamatsu', '香川500さ12-34', 'アルファード', 2022, 'ホワイト');
-- ============================================================
