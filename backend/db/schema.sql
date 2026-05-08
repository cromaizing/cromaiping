-- ─────────────────────────────────────────────────────────────
-- 크로마이핑 팩 마켓플레이스 DB 스키마 (PostgreSQL 기준)
-- cromaizing.com 기존 posts 테이블과 1:1 연결
-- ─────────────────────────────────────────────────────────────

-- 1. 팩 메타데이터 테이블
-- cromaizing.com 게시판의 posts 테이블과 1:1 매핑
-- 게시글 = 팩 / 메타데이터는 별도 분리 (게시판 시스템 침범 X)
CREATE TABLE IF NOT EXISTS pack_metadata (
  id BIGSERIAL PRIMARY KEY,

  -- cromaizing.com posts 테이블 외래키 (게시글과 1:1)
  post_id BIGINT NOT NULL UNIQUE,

  -- 등록자 (cromaizing.com users 테이블 외래키)
  submitter_user_id BIGINT NOT NULL,

  -- CESP 식별자 (전역 고유)
  name VARCHAR(64) NOT NULL UNIQUE
    CHECK (name ~ '^[a-z0-9][a-z0-9_-]*$'),

  -- 표시명 (한글 OK)
  display_name VARCHAR(128) NOT NULL,

  -- 설명 (선택)
  description VARCHAR(512),

  -- GitHub 정보
  github_url TEXT NOT NULL,
  source_repo VARCHAR(256) NOT NULL,         -- e.g. "user/my-pack"
  source_ref VARCHAR(64) DEFAULT 'main',     -- tag or branch
  source_path VARCHAR(256) DEFAULT '',       -- subdirectory in repo

  -- 검증 정보
  sha256 CHAR(64) NOT NULL,
  sound_count INT NOT NULL CHECK (sound_count > 0),
  total_size_bytes BIGINT NOT NULL CHECK (total_size_bytes <= 52428800), -- 50MB

  -- 메타데이터
  language VARCHAR(8) DEFAULT 'ko',          -- BCP 47
  license VARCHAR(64),                       -- SPDX
  tags JSONB DEFAULT '[]',                   -- ["gaming", "korean"] 등
  categories JSONB NOT NULL,                 -- ["session.start", "task.complete", ...]

  -- 미리듣기 (대표 사운드 URL)
  preview_sound_url TEXT,

  -- 통계
  download_count BIGINT DEFAULT 0,
  view_count BIGINT DEFAULT 0,

  -- 상태
  status VARCHAR(16) NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'frozen', 'removed', 'broken')),

  -- 헬스체크
  last_health_check_at TIMESTAMPTZ,

  -- 타임스탬프
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- 외래키 (스키마 통합 시 활성화)
  CONSTRAINT fk_pack_post FOREIGN KEY (post_id)
    REFERENCES posts(id) ON DELETE CASCADE
  -- CONSTRAINT fk_pack_user FOREIGN KEY (submitter_user_id)
  --   REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX idx_pack_metadata_status ON pack_metadata(status);
CREATE INDEX idx_pack_metadata_language ON pack_metadata(language);
CREATE INDEX idx_pack_metadata_submitter ON pack_metadata(submitter_user_id);
CREATE INDEX idx_pack_metadata_created ON pack_metadata(created_at DESC);
CREATE INDEX idx_pack_metadata_downloads ON pack_metadata(download_count DESC);
CREATE INDEX idx_pack_metadata_tags ON pack_metadata USING GIN (tags);


-- 2. 신고 테이블
-- 사용자가 부적절/저작권 침해 콘텐츠 신고
CREATE TABLE IF NOT EXISTS pack_reports (
  id BIGSERIAL PRIMARY KEY,

  -- 신고 대상 팩
  pack_metadata_id BIGINT NOT NULL,

  -- 신고자 (비로그인 신고도 허용 시 nullable)
  reporter_user_id BIGINT,

  -- 신고 사유
  reason VARCHAR(32) NOT NULL
    CHECK (reason IN ('copyright', 'inappropriate', 'broken', 'spam', 'other')),
  description TEXT,

  -- 권리자 직접 신고 시 (DMCA 대응)
  rightsholder_email VARCHAR(256),
  rightsholder_name VARCHAR(128),

  -- 처리 상태
  status VARCHAR(16) NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'in_review', 'resolved', 'rejected')),
  admin_note TEXT,
  resolved_by_user_id BIGINT,                -- 관리자 user_id

  -- 타임스탬프
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ,

  CONSTRAINT fk_report_pack FOREIGN KEY (pack_metadata_id)
    REFERENCES pack_metadata(id) ON DELETE CASCADE
);

CREATE INDEX idx_pack_reports_status ON pack_reports(status);
CREATE INDEX idx_pack_reports_pack ON pack_reports(pack_metadata_id);
CREATE INDEX idx_pack_reports_created ON pack_reports(created_at DESC);


-- 3. 다운로드 로그 (선택 — 통계용)
-- cromaiping CLI가 다운로드 시 ping (익명)
-- 누적은 pack_metadata.download_count에 일배치 집계
CREATE TABLE IF NOT EXISTS pack_download_logs (
  id BIGSERIAL PRIMARY KEY,
  pack_metadata_id BIGINT NOT NULL,
  ip_hash VARCHAR(64),                       -- IP는 SHA256 해시로만 저장 (개인정보 X)
  user_agent VARCHAR(256),
  cromaiping_version VARCHAR(32),            -- 클라이언트 버전
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT fk_dlog_pack FOREIGN KEY (pack_metadata_id)
    REFERENCES pack_metadata(id) ON DELETE CASCADE
);

CREATE INDEX idx_pack_dlog_pack_date ON pack_download_logs(pack_metadata_id, created_at);


-- 4. 트리거: updated_at 자동 갱신
CREATE OR REPLACE FUNCTION update_pack_metadata_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pack_metadata_updated_at
  BEFORE UPDATE ON pack_metadata
  FOR EACH ROW
  EXECUTE FUNCTION update_pack_metadata_updated_at();


-- ─────────────────────────────────────────────────────────────
-- 보조 뷰 (선택 — 자주 쓰는 쿼리 단순화)
-- ─────────────────────────────────────────────────────────────

-- 활성 팩 + 등록자 정보 조인 (registry.json 빌드용)
CREATE OR REPLACE VIEW v_active_packs AS
SELECT
  pm.*,
  u.username AS submitter_username,    -- cromaizing.com users.username 가정
  p.title AS post_title,
  p.created_at AS post_created_at
FROM pack_metadata pm
LEFT JOIN users u ON u.id = pm.submitter_user_id
LEFT JOIN posts p ON p.id = pm.post_id
WHERE pm.status = 'active';

-- 신고 우선순위 큐 (관리자용)
CREATE OR REPLACE VIEW v_pending_reports AS
SELECT
  pr.*,
  pm.name AS pack_name,
  pm.display_name AS pack_display_name,
  pm.github_url
FROM pack_reports pr
INNER JOIN pack_metadata pm ON pm.id = pr.pack_metadata_id
WHERE pr.status IN ('open', 'in_review')
ORDER BY
  CASE pr.reason
    WHEN 'copyright' THEN 1   -- 저작권 우선
    WHEN 'inappropriate' THEN 2
    ELSE 3
  END,
  pr.created_at ASC;
