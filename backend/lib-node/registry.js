/**
 * registry.json 빌더
 *
 * DB의 active 팩을 cromaiping CLI가 fetch하는 형식으로 변환.
 * peon-ping registry 형식 호환.
 */

/**
 * DB row 배열 → registry.json 객체
 *
 * @param {Array} packs - pack_metadata 테이블 row들 (status='active')
 * @returns {object} registry.json
 */
function buildRegistry(packs, options = {}) {
  const {
    homepage = 'https://cromaizing.com/cromaiping',
    name = '크로마이핑 공식 레지스트리',
    description = '한국 사용자를 위해 큐레이션된 사운드 팩 모음',
  } = options;

  return {
    registry_version: '1.0',
    name,
    description,
    homepage,
    updated: new Date().toISOString(),
    _doc: {
      ko: '본 레지스트리는 cromaizing.com 회원이 등록한 사운드 팩 메타데이터입니다. ' +
          '실제 다운로드는 등록자의 GitHub 저장소에서 직접 이루어지며, ' +
          'cromaizing은 인덱서로서 콘텐츠를 호스팅하지 않습니다.',
    },
    packs: packs.map(packToRegistryEntry),
    _attribution: {
      license_notice: '각 팩의 라이선스는 등록자가 명시한 라이선스를 따릅니다.',
      ko: '저작권은 각 팩 등록자에게 있으며, 침해 신고는 ' +
          'https://cromaizing.com/cromaiping/report 에서 가능합니다.',
    },
  };
}

/**
 * DB row 한 개 → registry 항목
 */
function packToRegistryEntry(row) {
  return {
    name: row.name,
    display_name: row.display_name,
    description: row.description || '',
    language: row.language || 'en',
    tags: parseTags(row.tags),
    license: row.license || '',
    source_repo: row.source_repo,
    source_ref: row.source_ref || 'main',
    source_path: row.source_path || '',
    sound_count: row.sound_count,
    total_size_bytes: row.total_size_bytes,
    sha256: row.sha256,
    categories: parseCategories(row.categories),

    // 크로마이핑 전용 추가 필드 (선택)
    cromaizing_post_url: `https://cromaizing.com/cromaiping/packs/${row.name}`,
    cromaizing_submitter: row.submitter_username || null,
    cromaizing_download_count: row.download_count || 0,
  };
}

function parseTags(tags) {
  if (Array.isArray(tags)) return tags;
  if (typeof tags === 'string') {
    try { return JSON.parse(tags); } catch { return []; }
  }
  return [];
}

function parseCategories(categories) {
  if (Array.isArray(categories)) return categories;
  if (typeof categories === 'string') {
    try { return JSON.parse(categories); } catch { return []; }
  }
  return [];
}

module.exports = {
  buildRegistry,
  packToRegistryEntry,
};
