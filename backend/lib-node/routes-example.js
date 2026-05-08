/**
 * Express / Next.js API 라우트 예시 구현
 *
 * cromaizing.com 백엔드 개발자가 그대로 가져다 쓸 수 있는 참조 구현.
 * 실제 인프라(DB 클라이언트, 인증 미들웨어)에 맞게 조정 필요.
 *
 * 의존성:
 *   - axios, tar-stream (lib-node/github.js)
 *   - cromaizing.com 기존: express, pg (PostgreSQL), 세션 미들웨어
 */
const express = require('express');
const { validatePackFromGithub } = require('./validator');
const {
  generatePostBody,
  generatePostTitle,
  generatePostTags,
} = require('./post-template');
const { buildRegistry } = require('./registry');

const router = express.Router();

// ─────────────────────────────────────────────
// 인증 미들웨어 (cromaizing.com 기존 세션 시스템 가정)
// ─────────────────────────────────────────────
function requireAuth(req, res, next) {
  if (!req.session?.user_id) {
    return res.status(401).json({ error: '로그인이 필요합니다' });
  }
  next();
}

function requireAdmin(req, res, next) {
  if (!req.session?.user?.is_admin) {
    return res.status(403).json({ error: '관리자 권한이 필요합니다' });
  }
  next();
}

// ─────────────────────────────────────────────
// 1. 검증 + 미리보기
// ─────────────────────────────────────────────
router.post('/packs/preview', requireAuth, async (req, res) => {
  const { github_url } = req.body;
  if (!github_url) {
    return res.status(400).json({ error: 'github_url이 필요합니다' });
  }

  // DB에서 이름 중복 체크 함수 주입
  const checkNameDuplicate = async (name) => {
    const r = await req.db.query(
      'SELECT 1 FROM pack_metadata WHERE name = $1 AND status = $2',
      [name, 'active']
    );
    return r.rowCount > 0;
  };

  const result = await validatePackFromGithub(github_url, { checkNameDuplicate });

  res.status(result.valid ? 200 : 400).json(result);
});

// ─────────────────────────────────────────────
// 2. 등록 (즉시 게시글 생성)
// ─────────────────────────────────────────────
router.post('/packs/submit', requireAuth, async (req, res) => {
  const { github_url } = req.body;
  if (!github_url) {
    return res.status(400).json({ error: 'github_url이 필요합니다' });
  }

  // 레이트 리밋 체크 (예: 일 5팩)
  const today = new Date().toISOString().slice(0, 10);
  const todayCount = await req.db.query(
    `SELECT COUNT(*) FROM pack_metadata
     WHERE submitter_user_id = $1 AND created_at::date = $2`,
    [req.session.user_id, today]
  );
  if (parseInt(todayCount.rows[0].count) >= 5) {
    return res.status(429).json({
      error: '일일 등록 한도(5팩)를 초과했습니다',
    });
  }

  // 검증
  const checkNameDuplicate = async (name) => {
    const r = await req.db.query(
      'SELECT 1 FROM pack_metadata WHERE name = $1', [name]
    );
    return r.rowCount > 0;
  };

  const validation = await validatePackFromGithub(github_url, { checkNameDuplicate });

  if (!validation.valid) {
    return res.status(400).json(validation);
  }

  // 트랜잭션으로 게시글 + 메타데이터 동시 INSERT
  const client = await req.db.connect();
  try {
    await client.query('BEGIN');

    // 자동 본문 생성
    const submitter = await client.query(
      'SELECT username FROM users WHERE id = $1',
      [req.session.user_id]
    );
    const submitterUsername = submitter.rows[0]?.username || 'user';

    const postBody = generatePostBody({
      metadata: validation.metadata,
      sounds: validation.sounds,
      submitter_username: submitterUsername,
      created_at: new Date(),
      report_url: `/cromaiping/packs/${validation.metadata.name}/report`,
    });

    const postTitle = generatePostTitle(validation.metadata);
    const postTags = generatePostTags(validation.metadata);

    // 1) cromaizing.com posts 테이블에 INSERT
    const postResult = await client.query(
      `INSERT INTO posts (category_id, user_id, title, content, tags, created_at)
       VALUES (
         (SELECT id FROM categories WHERE slug = 'cromaiping-packs'),
         $1, $2, $3, $4, NOW()
       )
       RETURNING id`,
      [req.session.user_id, postTitle, postBody, JSON.stringify(postTags)]
    );
    const postId = postResult.rows[0].id;

    // 2) pack_metadata 테이블에 INSERT
    const m = validation.metadata;
    const packResult = await client.query(
      `INSERT INTO pack_metadata
       (post_id, submitter_user_id, name, display_name, description,
        github_url, source_repo, source_ref, source_path,
        sha256, sound_count, total_size_bytes,
        language, license, tags, categories, preview_sound_url, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, 'active')
       RETURNING id`,
      [
        postId,
        req.session.user_id,
        m.name,
        m.display_name,
        m.description,
        m.github_url,
        m.source_repo,
        m.source_ref,
        m.source_path,
        m.sha256,
        m.sound_count,
        m.total_size_bytes,
        m.language,
        m.license,
        JSON.stringify(m.tags),
        JSON.stringify(m.categories),
        m.preview_sound_url,
      ]
    );

    await client.query('COMMIT');

    // registry cache invalidate (선택)
    invalidateRegistryCache?.();

    res.status(201).json({
      pack_metadata_id: packResult.rows[0].id,
      post_id: postId,
      post_url: `/cromaiping/packs/${m.name}`,
      name: m.name,
    });
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
});

// ─────────────────────────────────────────────
// 3. 목록 (4컬럼 게시판)
// ─────────────────────────────────────────────
router.get('/packs/list', async (req, res) => {
  const {
    q,
    lang,
    tag,
    sort = 'latest',
    page = 1,
    limit = 20,
  } = req.query;

  const safeLimit = Math.min(parseInt(limit) || 20, 100);
  const offset = ((parseInt(page) || 1) - 1) * safeLimit;

  const orderBy = ({
    latest: 'pm.created_at DESC',
    popular: 'pm.download_count DESC',
    name: 'pm.name ASC',
  })[sort] || 'pm.created_at DESC';

  const result = await req.db.query(`
    SELECT
      pm.name,
      pm.display_name,
      pm.created_at,
      pm.preview_sound_url,
      pm.download_count,
      pm.language,
      u.username AS submitter_username
    FROM pack_metadata pm
    LEFT JOIN users u ON u.id = pm.submitter_user_id
    WHERE pm.status = 'active'
      AND ($1::text IS NULL OR pm.display_name ILIKE '%' || $1 || '%' OR pm.description ILIKE '%' || $1 || '%')
      AND ($2::text IS NULL OR pm.language = $2)
      AND ($3::text IS NULL OR pm.tags @> jsonb_build_array($3))
    ORDER BY ${orderBy}
    LIMIT $4 OFFSET $5
  `, [q || null, lang || null, tag || null, safeLimit, offset]);

  const totalResult = await req.db.query(`
    SELECT COUNT(*) FROM pack_metadata pm
    WHERE status = 'active'
      AND ($1::text IS NULL OR pm.display_name ILIKE '%' || $1 || '%')
      AND ($2::text IS NULL OR pm.language = $2)
  `, [q || null, lang || null]);

  res.json({
    total: parseInt(totalResult.rows[0].count),
    page: parseInt(page),
    packs: result.rows.map(row => ({
      ...row,
      post_url: `/cromaiping/packs/${row.name}`,
    })),
  });
});

// ─────────────────────────────────────────────
// 4. 개별 팩 상세
// ─────────────────────────────────────────────
router.get('/packs/:name', async (req, res) => {
  const result = await req.db.query(`
    SELECT pm.*, u.username AS submitter_username, p.content AS post_body, p.title AS post_title
    FROM pack_metadata pm
    LEFT JOIN users u ON u.id = pm.submitter_user_id
    LEFT JOIN posts p ON p.id = pm.post_id
    WHERE pm.name = $1 AND pm.status = 'active'
  `, [req.params.name]);

  if (result.rowCount === 0) {
    return res.status(404).json({ error: '팩을 찾을 수 없습니다' });
  }

  // view count 비동기 증가
  req.db.query(
    'UPDATE pack_metadata SET view_count = view_count + 1 WHERE id = $1',
    [result.rows[0].id]
  ).catch(() => {});

  res.json(result.rows[0]);
});

// ─────────────────────────────────────────────
// 5. 레지스트리 (CLI용)
// ─────────────────────────────────────────────
router.get('/registry.json', async (req, res) => {
  // 캐싱 헤더
  res.set('Cache-Control', 'public, max-age=300'); // 5분

  const result = await req.db.query(`
    SELECT pm.*, u.username AS submitter_username
    FROM pack_metadata pm
    LEFT JOIN users u ON u.id = pm.submitter_user_id
    WHERE pm.status = 'active'
    ORDER BY pm.download_count DESC, pm.created_at DESC
  `);

  res.json(buildRegistry(result.rows));
});

// ─────────────────────────────────────────────
// 6. 신고
// ─────────────────────────────────────────────
router.post('/packs/:name/report', async (req, res) => {
  const { reason, description, rightsholder_email, rightsholder_name } = req.body;

  const pack = await req.db.query(
    'SELECT id FROM pack_metadata WHERE name = $1', [req.params.name]
  );
  if (pack.rowCount === 0) {
    return res.status(404).json({ error: '팩을 찾을 수 없습니다' });
  }

  const result = await req.db.query(
    `INSERT INTO pack_reports
     (pack_metadata_id, reporter_user_id, reason, description, rightsholder_email, rightsholder_name)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id`,
    [
      pack.rows[0].id,
      req.session?.user_id || null,
      reason,
      description,
      rightsholder_email,
      rightsholder_name,
    ]
  );

  // TODO: 관리자에게 알림 (이메일/슬랙)
  // notifyAdminsOfReport(result.rows[0].id);

  res.status(201).json({ report_id: result.rows[0].id });
});

// ─────────────────────────────────────────────
// 7. 내 팩 삭제
// ─────────────────────────────────────────────
router.delete('/packs/:name', requireAuth, async (req, res) => {
  const result = await req.db.query(
    `UPDATE pack_metadata SET status = 'removed', updated_at = NOW()
     WHERE name = $1 AND submitter_user_id = $2
     RETURNING id`,
    [req.params.name, req.session.user_id]
  );

  if (result.rowCount === 0) {
    return res.status(403).json({ error: '본인이 등록한 팩만 삭제 가능합니다' });
  }

  res.status(204).end();
});

// ─────────────────────────────────────────────
// 관리자 라우트
// ─────────────────────────────────────────────
router.get('/admin/reports', requireAdmin, async (req, res) => {
  const status = req.query.status || 'open';
  const result = await req.db.query(`
    SELECT * FROM v_pending_reports
    WHERE status = $1
  `, [status]);
  res.json(result.rows);
});

router.post('/admin/packs/:name/freeze', requireAdmin, async (req, res) => {
  await req.db.query(
    `UPDATE pack_metadata SET status = 'frozen', updated_at = NOW() WHERE name = $1`,
    [req.params.name]
  );
  res.json({ ok: true });
});

router.delete('/admin/packs/:name', requireAdmin, async (req, res) => {
  await req.db.query(
    `UPDATE pack_metadata SET status = 'removed', updated_at = NOW() WHERE name = $1`,
    [req.params.name]
  );
  res.status(204).end();
});

module.exports = router;
