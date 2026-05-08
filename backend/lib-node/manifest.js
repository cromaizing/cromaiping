/**
 * CESP v1.0 매니페스트 검증
 *
 * 표준: https://openpeon.com/spec
 */
const { ValidationError } = require('./github');

const VALID_CATEGORIES = [
  // 핵심
  'session.start',
  'task.acknowledge',
  'task.complete',
  'task.error',
  'input.required',
  'resource.limit',
  // 확장
  'user.spam',
  'session.end',
  'task.progress',
];

const NAME_PATTERN = /^[a-z0-9][a-z0-9_-]*$/;
const FILE_NAME_PATTERN = /^[a-zA-Z0-9._-]+$/;
const MAX_NAME_LENGTH = 64;
const MAX_DISPLAY_NAME_LENGTH = 128;
const MAX_DESCRIPTION_LENGTH = 256;
const MAX_TOTAL_SIZE = 50 * 1024 * 1024; // 50MB
const MAX_FILE_SIZE = 1024 * 1024;       // 1MB

/**
 * openpeon.json 객체 검증
 * @param {object} manifest - 파싱된 JSON
 * @returns {object} 검증된 메타데이터 (정규화됨)
 * @throws ValidationError
 */
function validateManifest(manifest) {
  if (!manifest || typeof manifest !== 'object') {
    throw new ValidationError('MANIFEST_INVALID', 'openpeon.json이 객체가 아닙니다');
  }

  // 필수 필드
  if (manifest.cesp_version !== '1.0') {
    throw new ValidationError('MANIFEST_INVALID',
      `cesp_version은 '1.0'이어야 합니다 (받음: ${manifest.cesp_version})`,
      'cesp_version');
  }

  const name = manifest.name;
  if (typeof name !== 'string' || !NAME_PATTERN.test(name) || name.length > MAX_NAME_LENGTH) {
    throw new ValidationError('NAME_INVALID',
      `name은 소문자/숫자/하이픈/언더스코어만 사용 가능 (1-${MAX_NAME_LENGTH}자, 첫 글자 영숫자)`,
      'name');
  }

  const displayName = manifest.display_name;
  if (typeof displayName !== 'string' || displayName.length === 0 || displayName.length > MAX_DISPLAY_NAME_LENGTH) {
    throw new ValidationError('MANIFEST_INVALID',
      `display_name은 1-${MAX_DISPLAY_NAME_LENGTH}자여야 합니다`,
      'display_name');
  }

  const version = manifest.version;
  if (typeof version !== 'string' || !/^\d+\.\d+\.\d+/.test(version)) {
    throw new ValidationError('MANIFEST_INVALID',
      'version은 SemVer 형식이어야 합니다 (예: 1.0.0)',
      'version');
  }

  const categories = manifest.categories;
  if (!categories || typeof categories !== 'object') {
    throw new ValidationError('MANIFEST_INVALID',
      'categories 객체가 필요합니다',
      'categories');
  }

  const categoryNames = Object.keys(categories);
  if (categoryNames.length === 0) {
    throw new ValidationError('MANIFEST_INVALID',
      '최소 1개 카테고리가 필요합니다',
      'categories');
  }

  let totalSoundCount = 0;
  const allFiles = []; // 검증할 파일 경로 목록

  for (const catName of categoryNames) {
    if (!VALID_CATEGORIES.includes(catName)) {
      throw new ValidationError('MANIFEST_INVALID',
        `알 수 없는 카테고리: ${catName} (허용: ${VALID_CATEGORIES.join(', ')})`,
        `categories.${catName}`);
    }

    const cat = categories[catName];
    if (!cat || typeof cat !== 'object' || !Array.isArray(cat.sounds)) {
      throw new ValidationError('MANIFEST_INVALID',
        `categories.${catName}.sounds는 배열이어야 합니다`,
        `categories.${catName}.sounds`);
    }

    for (let i = 0; i < cat.sounds.length; i++) {
      const sound = cat.sounds[i];
      if (!sound || typeof sound !== 'object') {
        throw new ValidationError('MANIFEST_INVALID',
          `categories.${catName}.sounds[${i}]는 객체여야 합니다`);
      }

      const file = sound.file;
      if (typeof file !== 'string' || file.length === 0) {
        throw new ValidationError('MANIFEST_INVALID',
          `categories.${catName}.sounds[${i}].file은 문자열이어야 합니다`,
          `categories.${catName}.sounds[${i}].file`);
      }
      if (file.includes('..') || file.startsWith('/')) {
        throw new ValidationError('MANIFEST_INVALID',
          `상대 경로 + 부모 디렉토리 참조 금지: ${file}`);
      }
      if (!file.startsWith('sounds/')) {
        // CESP는 sounds/ 폴더 권장 (강제는 아니지만 표준 따름)
      }

      // 파일명 ASCII 검증
      const fileName = file.split('/').pop();
      if (!FILE_NAME_PATTERN.test(fileName)) {
        throw new ValidationError('MANIFEST_INVALID',
          `파일명은 영숫자/.-_ 만 사용 가능: ${fileName}`,
          `categories.${catName}.sounds[${i}].file`);
      }

      const label = sound.label;
      if (label !== undefined && (typeof label !== 'string' || label.length > 256)) {
        throw new ValidationError('MANIFEST_INVALID',
          `label은 256자 이하 문자열이어야 합니다`);
      }

      allFiles.push({ category: catName, file, label: label || file });
      totalSoundCount++;
    }
  }

  if (totalSoundCount === 0) {
    throw new ValidationError('MANIFEST_INVALID',
      '최소 1개 사운드가 필요합니다');
  }

  // 권장 필드 (없으면 경고)
  const warnings = [];
  if (!manifest.description) warnings.push('description 권장');
  if (!manifest.author) warnings.push('author 권장');
  if (!manifest.license) warnings.push('license 권장');

  // 카테고리 누락 경고
  for (const cat of ['session.start', 'task.complete', 'task.error']) {
    if (!categories[cat] || categories[cat].sounds.length === 0) {
      warnings.push(`${cat} 카테고리에 사운드가 없습니다 — 해당 이벤트 시 알림이 울리지 않습니다`);
    }
  }

  return {
    name,
    display_name: displayName,
    description: typeof manifest.description === 'string' ? manifest.description.slice(0, MAX_DESCRIPTION_LENGTH) : null,
    version,
    license: typeof manifest.license === 'string' ? manifest.license : null,
    language: typeof manifest.language === 'string' ? manifest.language : 'en',
    tags: Array.isArray(manifest.tags) ? manifest.tags.slice(0, 10).filter(t => typeof t === 'string') : [],
    author: manifest.author && typeof manifest.author === 'object' ? {
      name: manifest.author.name,
      github: manifest.author.github,
    } : null,
    categories: categoryNames,
    category_aliases: manifest.category_aliases || {},
    sound_count: totalSoundCount,
    files: allFiles,
    warnings,
  };
}

module.exports = {
  validateManifest,
  VALID_CATEGORIES,
  MAX_TOTAL_SIZE,
  MAX_FILE_SIZE,
};
