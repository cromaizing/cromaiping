/**
 * 오디오 파일 매직바이트 검증
 *
 * CESP는 WAV / MP3 / OGG만 허용. 매직바이트로 진위 확인.
 * .exe / .sh 등이 .wav 확장자로 위장한 경우 차단.
 */
const { ValidationError } = require('./github');

/**
 * 버퍼의 매직바이트로 오디오 형식 감지
 * @param {Buffer} buf
 * @returns {string|null} 'wav' | 'mp3' | 'ogg' | null
 */
function detectAudioFormat(buf) {
  if (!buf || buf.length < 4) return null;

  // WAV: "RIFF" (52 49 46 46)
  if (buf[0] === 0x52 && buf[1] === 0x49 && buf[2] === 0x46 && buf[3] === 0x46) {
    // 추가: "WAVE" 확인 (offset 8)
    if (buf.length >= 12 &&
        buf[8] === 0x57 && buf[9] === 0x41 && buf[10] === 0x56 && buf[11] === 0x45) {
      return 'wav';
    }
    return null; // RIFF지만 WAVE 아님 (예: AVI)
  }

  // MP3 with ID3 tag: "ID3" (49 44 33)
  if (buf[0] === 0x49 && buf[1] === 0x44 && buf[2] === 0x33) {
    return 'mp3';
  }

  // MP3 sync frame: 0xFFFB / 0xFFF3 / 0xFFF2
  if (buf[0] === 0xFF) {
    const second = buf[1];
    if (second === 0xFB || second === 0xF3 || second === 0xF2 || second === 0xFA) {
      return 'mp3';
    }
  }

  // OGG: "OggS" (4F 67 67 53)
  if (buf[0] === 0x4F && buf[1] === 0x67 && buf[2] === 0x67 && buf[3] === 0x53) {
    return 'ogg';
  }

  return null;
}

/**
 * 파일 확장자와 실제 형식 일치 검증
 * @param {string} filePath
 * @param {Buffer} buf
 * @returns {string} 감지된 형식
 * @throws ValidationError
 */
function verifyAudioFile(filePath, buf) {
  const ext = filePath.toLowerCase().split('.').pop();

  if (!['wav', 'mp3', 'ogg'].includes(ext)) {
    throw new ValidationError('INVALID_AUDIO',
      `지원하지 않는 오디오 확장자: .${ext} (허용: .wav, .mp3, .ogg)`,
      filePath);
  }

  const detected = detectAudioFormat(buf);
  if (!detected) {
    throw new ValidationError('INVALID_AUDIO',
      `${filePath}: 오디오 매직바이트 검증 실패 (위조된 파일일 수 있음)`,
      filePath);
  }

  if (detected !== ext) {
    throw new ValidationError('INVALID_AUDIO',
      `${filePath}: 확장자(.${ext})와 실제 형식(${detected}) 불일치`,
      filePath);
  }

  return detected;
}

module.exports = {
  detectAudioFormat,
  verifyAudioFile,
};
