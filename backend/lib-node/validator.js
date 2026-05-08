/**
 * 통합 검증 파이프라인
 *
 * 입력: GitHub URL
 * 출력: { valid, metadata, sounds, warnings, errors }
 *
 * 모든 단계 자동 — 사람 검토 없음 (자동 등록 모델).
 */
const crypto = require('crypto');
const path = require('path');
const {
  parseGithubUrl,
  downloadArchive,
  extractTarball,
  rawUrl,
  ValidationError,
} = require('./github');
const { validateManifest, MAX_TOTAL_SIZE, MAX_FILE_SIZE } = require('./manifest');
const { verifyAudioFile } = require('./magic-bytes');

/**
 * GitHub URL → 검증 결과
 *
 * @param {string} githubUrl
 * @param {object} options
 * @param {function} options.checkNameDuplicate - async fn(name) → bool
 * @returns {object} { valid, metadata, sounds, warnings, errors }
 */
async function validatePackFromGithub(githubUrl, options = {}) {
  const errors = [];
  let parsed, archive, extracted, manifestData;

  try {
    // 1. URL 파싱
    parsed = parseGithubUrl(githubUrl);

    // 2. tarball 다운로드
    archive = await downloadArchive(parsed);

    // 3. 압축 해제
    extracted = await extractTarball(archive);

    // 4. 매니페스트 찾기
    const manifestPath = findManifest(extracted, parsed.path);
    if (!manifestPath) {
      throw new ValidationError('MANIFEST_MISSING',
        `openpeon.json을 찾을 수 없습니다 (경로: ${parsed.path || 'root'})`);
    }

    // 5. 매니페스트 파싱 + 검증
    const manifestFile = extracted.files.find(f => f.path === manifestPath);
    let parsedManifest;
    try {
      parsedManifest = JSON.parse(manifestFile.buffer.toString('utf-8'));
    } catch (e) {
      throw new ValidationError('MANIFEST_INVALID',
        `openpeon.json JSON 파싱 실패: ${e.message}`);
    }
    manifestData = validateManifest(parsedManifest);

    // 6. 사이즈 제한 체크
    if (extracted.totalSize > MAX_TOTAL_SIZE) {
      throw new ValidationError('SIZE_LIMIT_EXCEEDED',
        `팩 전체 크기(${(extracted.totalSize / 1024 / 1024).toFixed(1)}MB)가 50MB 제한을 초과합니다`);
    }

    // 7. 모든 사운드 파일 매직바이트 검증
    const manifestDir = path.dirname(manifestPath);
    const sounds = {};

    for (const fileEntry of manifestData.files) {
      const fullPath = path.posix.join(manifestDir, fileEntry.file);
      const file = extracted.files.find(f => f.path === fullPath);

      if (!file) {
        throw new ValidationError('MANIFEST_INVALID',
          `매니페스트에 명시된 파일이 없습니다: ${fileEntry.file}`,
          fileEntry.file);
      }

      if (file.size > MAX_FILE_SIZE) {
        throw new ValidationError('SIZE_LIMIT_EXCEEDED',
          `${fileEntry.file}: 파일 크기(${(file.size / 1024).toFixed(0)}KB)가 1MB 제한 초과`,
          fileEntry.file);
      }

      // 매직바이트 검증
      verifyAudioFile(fileEntry.file, file.buffer);

      // 카테고리별 정리
      if (!sounds[fileEntry.category]) sounds[fileEntry.category] = [];
      sounds[fileEntry.category].push({
        file: fileEntry.file,
        label: fileEntry.label,
        preview_url: rawUrl({
          owner: parsed.owner,
          repo: parsed.repo,
          ref: parsed.ref,
        }, path.posix.join(parsed.path, fileEntry.file)),
        size_bytes: file.size,
      });
    }

    // 8. 이름 중복 체크 (DB 조회 필요 — options.checkNameDuplicate 활용)
    if (options.checkNameDuplicate) {
      const exists = await options.checkNameDuplicate(manifestData.name);
      if (exists) {
        throw new ValidationError('NAME_DUPLICATE',
          `'${manifestData.name}' 이름은 이미 등록되어 있습니다`,
          'name');
      }
    }

    // 9. 대표 미리듣기 URL 결정
    // 우선순위: task.complete[0] → session.start[0] → 첫 번째 카테고리[0]
    let previewUrl = null;
    for (const cat of ['task.complete', 'session.start']) {
      if (sounds[cat] && sounds[cat][0]) {
        previewUrl = sounds[cat][0].preview_url;
        break;
      }
    }
    if (!previewUrl && Object.keys(sounds).length > 0) {
      const firstCat = Object.keys(sounds)[0];
      previewUrl = sounds[firstCat][0]?.preview_url || null;
    }

    // 10. SHA-256 (전체 tarball)
    const sha256 = crypto.createHash('sha256').update(archive).digest('hex');

    // 성공
    return {
      valid: true,
      metadata: {
        ...manifestData,
        source_repo: `${parsed.owner}/${parsed.repo}`,
        source_ref: parsed.ref,
        source_path: parsed.path,
        github_url: `https://github.com/${parsed.owner}/${parsed.repo}`,
        sha256,
        total_size_bytes: extracted.totalSize,
        preview_sound_url: previewUrl,
      },
      sounds,
      warnings: manifestData.warnings,
      errors: [],
    };

  } catch (err) {
    if (err instanceof ValidationError) {
      return {
        valid: false,
        errors: [err.toJSON()],
      };
    }
    // 예상치 못한 에러
    return {
      valid: false,
      errors: [{
        code: 'INTERNAL_ERROR',
        message: `검증 중 오류 발생: ${err.message}`,
      }],
    };
  }
}

/**
 * 추출된 tarball에서 openpeon.json 찾기
 * 우선순위:
 *   1. <rootDir>/<source_path>/openpeon.json (사용자 지정 경로)
 *   2. <rootDir>/openpeon.json (root)
 *   3. 어디든 첫 번째로 발견되는 것
 */
function findManifest(extracted, sourcePath) {
  const { rootDir, files } = extracted;

  if (sourcePath) {
    const target = path.posix.join(rootDir, sourcePath, 'openpeon.json');
    if (files.find(f => f.path === target)) return target;
  }

  const rootTarget = path.posix.join(rootDir, 'openpeon.json');
  if (files.find(f => f.path === rootTarget)) return rootTarget;

  const found = files.find(f => f.path.endsWith('/openpeon.json'));
  return found ? found.path : null;
}

module.exports = {
  validatePackFromGithub,
};
