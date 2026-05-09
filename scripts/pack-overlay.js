#!/usr/bin/env osascript -l JavaScript
// 크로마이핑 팩 오버레이 — GIF + 텍스트 알림
//
// 사용법:
//   osascript -l JavaScript pack-overlay.js <gif_path> <message> <bg_gradient> <duration_ms> <position>
//
// 예시:
//   osascript -l JavaScript pack-overlay.js \
//     ~/.claude/hooks/cromaiping/packs/karina/overlay/karina.gif \
//     "작업이 완료됐어요!" \
//     "linear-gradient(135deg, #d946ef, #fb7185, #7c3aed)" \
//     4500 \
//     "top-right"

ObjC.import('Cocoa');
ObjC.import('WebKit');

function run(argv) {
  var gifPath  = argv[0] || '';
  var message  = argv[1] || '';
  var bgStyle  = argv[2] || 'linear-gradient(135deg, #7c3aed, #d946ef, #fb7185)';
  var duration = parseFloat(argv[3]) || 4500;
  var position = argv[4] || 'top-right';

  if (!gifPath || !$.NSFileManager.defaultManager.fileExistsAtPath(gifPath)) {
    return;
  }

  // 윈도우 사이즈 (GIF 320x280 + 메시지 영역)
  var winWidth = 360;
  var winHeight = 380;

  // 화면 위치 계산 (메인 스크린 기준)
  var screen = $.NSScreen.mainScreen;
  var screenFrame = screen.visibleFrame;
  var margin = 20;

  var x, y;
  switch (position) {
    case 'top-left':
      x = screenFrame.origin.x + margin;
      y = screenFrame.origin.y + screenFrame.size.height - winHeight - margin;
      break;
    case 'top-center':
      x = screenFrame.origin.x + (screenFrame.size.width - winWidth) / 2;
      y = screenFrame.origin.y + screenFrame.size.height - winHeight - margin;
      break;
    case 'bottom-left':
      x = screenFrame.origin.x + margin;
      y = screenFrame.origin.y + margin;
      break;
    case 'bottom-right':
      x = screenFrame.origin.x + screenFrame.size.width - winWidth - margin;
      y = screenFrame.origin.y + margin;
      break;
    case 'bottom-center':
      x = screenFrame.origin.x + (screenFrame.size.width - winWidth) / 2;
      y = screenFrame.origin.y + margin;
      break;
    case 'top-right':
    default:
      x = screenFrame.origin.x + screenFrame.size.width - winWidth - margin;
      y = screenFrame.origin.y + screenFrame.size.height - winHeight - margin;
  }

  var rect = $.NSMakeRect(x, y, winWidth, winHeight);

  // borderless transparent NSPanel (always-on-top)
  var styleMask = $.NSWindowStyleMaskBorderless;
  var panel = $.NSPanel.alloc.initWithContentRectStyleMaskBackingDefer(
    rect, styleMask, $.NSBackingStoreBuffered, false
  );
  panel.opaque = false;
  panel.backgroundColor = $.NSColor.clearColor;
  panel.level = $.NSStatusWindowLevel;  // 항상 맨 위
  panel.collectionBehavior =
    (1 << 0)  /* Default */ |
    (1 << 8); /* canJoinAllSpaces */
  panel.ignoresMouseEvents = false;
  panel.movableByWindowBackground = false;

  // WKWebView (HTML로 GIF 렌더링)
  var config = $.WKWebViewConfiguration.alloc.init;
  var contentRect = $.NSMakeRect(0, 0, winWidth, winHeight);
  var webView = $.WKWebView.alloc.initWithFrameConfiguration(contentRect, config);
  webView.setValueForKey(false, 'drawsBackground');  // 투명 배경

  // 텍스트 escape
  function htmlEscape(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  var safeMsg = htmlEscape(message);
  var fileURL = 'file://' + encodeURI(gifPath);

  // 애니메이션 + 디자인 HTML
  var html = `<!DOCTYPE html>
<html><head><meta charset="UTF-8">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body {
    background: transparent;
    width: 100vw;
    height: 100vh;
    overflow: hidden;
    font-family: 'Pretendard Variable', Pretendard, -apple-system, system-ui, sans-serif;
  }
  .card {
    width: 100%;
    height: 100%;
    background: ${bgStyle};
    border-radius: 20px;
    overflow: hidden;
    box-shadow: 0 8px 32px rgba(124, 58, 237, 0.4);
    display: flex;
    flex-direction: column;
    animation: slideIn 0.3s cubic-bezier(0.16, 1, 0.3, 1);
    position: relative;
  }
  .gif-wrap {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    background: rgba(0,0,0,0.05);
  }
  .gif-wrap img {
    max-width: 100%;
    max-height: 100%;
    object-fit: contain;
    border-radius: 12px;
    margin: 12px;
  }
  .text-wrap {
    padding: 14px 18px 18px;
    background: linear-gradient(180deg, transparent, rgba(0,0,0,0.15));
    text-align: center;
  }
  .msg {
    color: #ffffff;
    font-size: 15px;
    font-weight: 600;
    letter-spacing: -0.01em;
    text-shadow: 0 2px 8px rgba(0,0,0,0.3);
    line-height: 1.4;
  }
  .badge {
    display: inline-block;
    padding: 3px 10px;
    background: rgba(255,255,255,0.2);
    backdrop-filter: blur(8px);
    border-radius: 9999px;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.05em;
    color: rgba(255,255,255,0.95);
    margin-bottom: 6px;
    text-transform: uppercase;
  }
  @keyframes slideIn {
    from { opacity: 0; transform: translateY(-12px) scale(0.96); }
    to   { opacity: 1; transform: translateY(0) scale(1); }
  }
  .card.dismissing {
    animation: slideOut 0.25s ease-in forwards;
  }
  @keyframes slideOut {
    to { opacity: 0; transform: translateY(-8px) scale(0.97); }
  }
</style>
</head><body>
<div class="card" id="card">
  <div class="gif-wrap"><img src="${fileURL}" alt=""/></div>
  <div class="text-wrap">
    <div class="badge">크로마이핑</div>
    <div class="msg">${safeMsg}</div>
  </div>
</div>
<script>
  setTimeout(function(){
    document.getElementById('card').classList.add('dismissing');
  }, ${duration - 250});
</script>
</body></html>`;

  webView.loadHTMLStringBaseURL(html, $.NSURL.fileURLWithPath('/'));

  panel.contentView = webView;
  panel.makeKeyAndOrderFront(null);

  // 자동 dismiss
  $.NSRunLoop.currentRunLoop.runUntilDate(
    $.NSDate.dateWithTimeIntervalSinceNow(duration / 1000)
  );
  panel.orderOut(null);
}
