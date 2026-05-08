/**
 * 자동 게시글 본문 생성
 *
 * 입력: 검증된 메타데이터 + 등록자 정보
 * 출력: 마크다운 본문
 *
 * 의존성: 없음 (간단한 문자열 치환)
 */
const fs = require('fs');
const path = require('path');

const TEMPLATE_PATH = path.join(__dirname, '..', 'templates', 'post-body.md.tmpl');

const LANGUAGE_NAMES = {
  ko: '한국어',
  en: 'English',
  ja: '日本語',
  zh: '中文',
  es: 'Español',
  fr: 'Français',
  ru: 'Русский',
  de: 'Deutsch',
};

const LANGUAGE_EMOJIS = {
  ko: '🇰🇷',
  en: '🇺🇸',
  ja: '🇯🇵',
  zh: '🇨🇳',
  es: '🇪🇸',
  fr: '🇫🇷',
  ru: '🇷🇺',
  de: '🇩🇪',
};

const CATEGORY_LABELS_KO = {
  'session.start': '세션 시작',
  'task.acknowledge': '작업 시작',
  'task.complete': '작업 완료',
  'task.error': '에러 발생',
  'input.required': '입력 대기',
  'resource.limit': '리소스 한계',
  'user.spam': '빠른 입력 감지',
  'session.end': '세션 종료',
  'task.progress': '작업 진행 중',
};

/**
 * 자동 게시글 본문 생성
 *
 * @param {object} params
 * @param {object} params.metadata - validatePackFromGithub의 metadata
 * @param {object} params.sounds - 카테고리별 사운드 (preview_url 포함)
 * @param {string} params.submitter_username - cromaizing.com 사용자명
 * @param {Date} params.created_at - 등록 시각
 * @param {string} [params.report_url] - 신고 링크 URL
 * @returns {string} 마크다운 본문
 */
function generatePostBody({ metadata, sounds, submitter_username, created_at, report_url }) {
  const template = fs.readFileSync(TEMPLATE_PATH, 'utf-8');

  const lang = metadata.language || 'en';
  const langName = LANGUAGE_NAMES[lang] || lang.toUpperCase();
  const langEmoji = LANGUAGE_EMOJIS[lang] || '🌐';

  // 사이즈 인간 친화적 변환
  const sizeBytes = metadata.total_size_bytes || 0;
  let sizeHuman;
  if (sizeBytes < 1024) sizeHuman = `${sizeBytes} B`;
  else if (sizeBytes < 1024 * 1024) sizeHuman = `${(sizeBytes / 1024).toFixed(0)} KB`;
  else sizeHuman = `${(sizeBytes / 1024 / 1024).toFixed(1)} MB`;

  // 카테고리별 첫 사운드 URL 추출
  const categoryRows = [];
  for (const [catName, soundList] of Object.entries(sounds || {})) {
    if (!soundList || soundList.length === 0) continue;
    const firstSound = soundList[0];
    categoryRows.push({
      category_name: catName,
      category_label: CATEGORY_LABELS_KO[catName] || catName,
      first_sound_url: firstSound.preview_url || '#',
    });
  }

  // 단순 변수 치환
  let body = template
    .replace(/\{\{display_name\}\}/g, escape(metadata.display_name || metadata.name))
    .replace(/\{\{name\}\}/g, escape(metadata.name))
    .replace(/\{\{description\}\}/g, escape(metadata.description || ''))
    .replace(/\{\{submitter_username\}\}/g, escape(submitter_username || 'unknown'))
    .replace(/\{\{created_at\}\}/g, formatDate(created_at || new Date()))
    .replace(/\{\{license\}\}/g, escape(metadata.license || 'Unknown'))
    .replace(/\{\{language\}\}/g, lang)
    .replace(/\{\{language_emoji\}\}/g, langEmoji)
    .replace(/\{\{language_name\}\}/g, langName)
    .replace(/\{\{sound_count\}\}/g, String(metadata.sound_count || 0))
    .replace(/\{\{total_size_human\}\}/g, sizeHuman)
    .replace(/\{\{total_size_bytes\}\}/g, String(sizeBytes))
    .replace(/\{\{github_url\}\}/g, metadata.github_url || '#')
    .replace(/\{\{source_repo\}\}/g, escape(metadata.source_repo || ''))
    .replace(/\{\{report_url\}\}/g, report_url || `/cromaiping/packs/${metadata.name}/report`);

  // each_category 블록 처리
  body = body.replace(
    /\{\{#each_category\}\}([\s\S]*?)\{\{\/each_category\}\}/g,
    (_, blockContent) => {
      return categoryRows.map(row =>
        blockContent
          .replace(/\{\{category_name\}\}/g, row.category_name)
          .replace(/\{\{category_label\}\}/g, row.category_label)
          .replace(/\{\{first_sound_url\}\}/g, row.first_sound_url)
      ).join('');
    }
  );

  return body.trim();
}

/**
 * 게시글 제목 자동 생성
 */
function generatePostTitle(metadata) {
  const lang = metadata.language || 'en';
  const emoji = LANGUAGE_EMOJIS[lang] || '🎵';
  return `${emoji} ${metadata.display_name}`;
}

/**
 * 게시글 태그 자동 생성
 */
function generatePostTags(metadata) {
  const tags = ['cromaiping'];
  if (metadata.language) tags.push(`lang:${metadata.language}`);
  if (Array.isArray(metadata.tags)) {
    tags.push(...metadata.tags.slice(0, 5));
  }
  return tags;
}

// 헬퍼
function escape(s) {
  return String(s ?? '').replace(/[<>]/g, c => ({ '<': '&lt;', '>': '&gt;' }[c]));
}

function formatDate(d) {
  const date = d instanceof Date ? d : new Date(d);
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${y}년 ${m}월 ${day}일`;
}

module.exports = {
  generatePostBody,
  generatePostTitle,
  generatePostTags,
  CATEGORY_LABELS_KO,
};
