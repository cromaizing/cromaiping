class Cromaiping < Formula
  desc "AI 코딩 도구용 한국형 사운드 알림 시스템 (CESP v1.0 호환)"
  homepage "https://cromaizing.com/cromaiping"
  url "https://github.com/cromaizing/cromaiping/releases/download/v0.1.0/cromaiping-0.1.0.tar.gz"
  sha256 "9533ca70d2877fad62a441acce0d866dd7530957494c4e982095ff6411af1df4"
  version "0.1.0"
  license "MIT"

  depends_on "python@3.11" => :recommended

  def install
    libexec.install Dir["*"]

    # CLI 명령어 shim 생성
    (bin/"cromaiping").write <<~SH
      #!/bin/bash
      exec bash "#{libexec}/cromaiping.sh" "$@"
    SH
    (bin/"cromaiping").chmod 0755
  end

  def caveats
    <<~EOS
      🎵 크로마이핑이 설치되었습니다.

      Claude Code 훅을 등록하려면 다음 명령어를 한 번만 실행해주세요:
        bash #{opt_libexec}/install.sh

      그 후 Claude Code를 재시작하시면 사운드 알림이 동작합니다.

      기본 명령어:
        cromaiping status         # 상태 확인
        cromaiping list           # 설치된 팩 목록
        cromaiping preview        # 사운드 미리듣기
        cromaiping packs list --registry  # 레지스트리 팩 목록
        cromaiping help           # 전체 도움말

      홈페이지: https://cromaizing.com/cromaiping
      GitHub:   https://github.com/cromaizing/cromaiping
    EOS
  end

  test do
    assert_match "크로마이핑", shell_output("#{bin}/cromaiping version")
  end
end
