/**
 * GitHub URL 파서 + tarball 다운로더
 *
 * cromaizing.com 백엔드에서 활용. 의존성: axios, tar-stream
 *
 * 흐름:
 *   parseGithubUrl(url) → { owner, repo, ref, path }
 *   downloadArchive({owner, repo, ref}) → Buffer (tarball)
 *   extractTarball(buf) → { files: [{path, buffer}], totalSize }
 */
const axios = require('axios');
const tar = require('tar-stream');
const zlib = require('zlib');
const { Readable } = require('stream');

/**
 * GitHub URL 파싱
 * 지원 형식:
 *   https://github.com/owner/repo
 *   https://github.com/owner/repo/tree/main
 *   https://github.com/owner/repo/tree/main/subpath
 *   https://github.com/owner/repo@v1.0.0
 *   owner/repo (shorthand)
 */
function parseGithubUrl(input) {
  if (!input || typeof input !== 'string') {
    throw new ValidationError('URL_INVALID', 'GitHub URL이 비어있거나 문자열이 아닙니다');
  }

  let trimmed = input.trim();

  // owner/repo shorthand
  if (/^[\w.-]+\/[\w.-]+$/.test(trimmed)) {
    const [owner, repo] = trimmed.split('/');
    return { owner, repo, ref: 'main', path: '' };
  }

  // @ref 처리 (예: github.com/user/repo@v1.0.0)
  let ref = 'main';
  const atMatch = trimmed.match(/@([\w.-]+)$/);
  if (atMatch) {
    ref = atMatch[1];
    trimmed = trimmed.slice(0, atMatch.index);
  }

  // URL 정규화
  if (!trimmed.startsWith('http')) trimmed = 'https://' + trimmed;

  let url;
  try {
    url = new URL(trimmed);
  } catch (e) {
    throw new ValidationError('URL_INVALID', '올바르지 않은 URL 형식입니다');
  }

  if (url.hostname !== 'github.com' && url.hostname !== 'www.github.com') {
    throw new ValidationError('URL_INVALID', 'github.com 도메인의 URL만 지원합니다');
  }

  const parts = url.pathname.split('/').filter(Boolean);
  if (parts.length < 2) {
    throw new ValidationError('URL_INVALID', 'owner/repo 형식이 필요합니다');
  }

  const [owner, repo, treeOrBlob, urlRef, ...subPath] = parts;

  if (treeOrBlob === 'tree' || treeOrBlob === 'blob') {
    if (urlRef) ref = urlRef;
  }

  return {
    owner,
    repo: repo.replace(/\.git$/, ''),
    ref,
    path: subPath.join('/'),
  };
}

/**
 * GitHub archive tarball 다운로드 (인증 X — public repo만)
 * 사이즈 제한: 100MB (다운로드 한계, CESP는 50MB지만 검증 전에 거를 수 있게 여유)
 */
async function downloadArchive({ owner, repo, ref = 'main' }) {
  // 우선순위: tag → branch
  const urls = [
    `https://api.github.com/repos/${owner}/${repo}/tarball/refs/tags/${ref}`,
    `https://api.github.com/repos/${owner}/${repo}/tarball/${ref}`,
    `https://github.com/${owner}/${repo}/archive/refs/tags/${ref}.tar.gz`,
    `https://github.com/${owner}/${repo}/archive/${ref}.tar.gz`,
  ];

  for (const url of urls) {
    try {
      const response = await axios.get(url, {
        responseType: 'arraybuffer',
        timeout: 30000,
        maxContentLength: 100 * 1024 * 1024, // 100MB
        headers: {
          'User-Agent': 'cromaiping-validator/1.0',
          'Accept': 'application/vnd.github.v3.raw',
        },
        validateStatus: (s) => s >= 200 && s < 300,
      });
      return Buffer.from(response.data);
    } catch (e) {
      // 다음 URL 시도
      continue;
    }
  }

  throw new ValidationError('REPO_NOT_FOUND',
    `GitHub 저장소에 접근할 수 없습니다: ${owner}/${repo}@${ref}`);
}

/**
 * tarball 압축 해제 → 파일 리스트
 *
 * 반환:
 *   {
 *     rootDir: 'owner-repo-sha/',  // tarball 최상위 디렉토리
 *     files: [
 *       { path: 'owner-repo-sha/openpeon.json', buffer: Buffer, size: 1234 },
 *       ...
 *     ],
 *     totalSize: 401234
 *   }
 */
function extractTarball(buf) {
  return new Promise((resolve, reject) => {
    const files = [];
    let rootDir = null;
    let totalSize = 0;

    const extract = tar.extract();

    extract.on('entry', (header, stream, next) => {
      // 디렉토리 X, 심볼릭링크 X
      if (header.type !== 'file') {
        stream.resume();
        next();
        return;
      }

      const path = header.name;

      // 첫 항목으로 root dir 추정 (예: "user-repo-abc123/")
      if (!rootDir) {
        const slashIdx = path.indexOf('/');
        rootDir = slashIdx >= 0 ? path.slice(0, slashIdx) : '';
      }

      // ../ traversal 차단
      if (path.includes('..')) {
        stream.resume();
        next();
        return;
      }

      const chunks = [];
      stream.on('data', (chunk) => {
        chunks.push(chunk);
        totalSize += chunk.length;
      });
      stream.on('end', () => {
        files.push({
          path,
          buffer: Buffer.concat(chunks),
          size: chunks.reduce((s, c) => s + c.length, 0),
        });
        next();
      });
      stream.on('error', next);
    });

    extract.on('finish', () => {
      resolve({ rootDir, files, totalSize });
    });

    extract.on('error', reject);

    // gzip 해제 → tar 파싱
    Readable.from(buf).pipe(zlib.createGunzip()).pipe(extract);
  });
}

/**
 * raw URL 빌더 (미리듣기용)
 * https://raw.githubusercontent.com/<owner>/<repo>/<ref>/<path>
 */
function rawUrl({ owner, repo, ref }, filePath) {
  return `https://raw.githubusercontent.com/${owner}/${repo}/${ref}/${filePath.replace(/^\//, '')}`;
}

/**
 * 검증 에러 클래스
 */
class ValidationError extends Error {
  constructor(code, message, field = null) {
    super(message);
    this.name = 'ValidationError';
    this.code = code;
    this.field = field;
  }
  toJSON() {
    return { code: this.code, field: this.field, message: this.message };
  }
}

module.exports = {
  parseGithubUrl,
  downloadArchive,
  extractTarball,
  rawUrl,
  ValidationError,
};
