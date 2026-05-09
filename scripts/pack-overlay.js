#!/usr/bin/env osascript -l JavaScript
// 크로마이핑 팩 오버레이 — peon-ping 패턴 + 투명 배경 + GIF 픽셀 사이즈
// NSImage + NSImageView로 GIF 처리 (WKWebView 안 씀)
//
// 사용법:
//   osascript -l JavaScript pack-overlay.js <gif_path> <message> <accent_color> <duration_seconds> <position>
//
// 색상 프리셋: violet / pink / coral / blue / green / red / yellow

ObjC.import('Cocoa');
ObjC.import('QuartzCore');

function run(argv) {
  var gifPath  = argv[0] || '';
  var message  = argv[1] || '';
  var color    = argv[2] || 'violet';
  var dismiss  = parseFloat(argv[3]);
  if (isNaN(dismiss)) dismiss = 4.5;
  var position = argv[4] || 'top-right';

  // GIF 파일 검증
  var hasIcon = (gifPath !== '' && $.NSFileManager.defaultManager.fileExistsAtPath(gifPath));
  if (!hasIcon) return;

  // 색상 프리셋 (텍스트 박스 액센트용)
  var r = 124/255, g = 58/255, b = 237/255;
  switch (color) {
    case 'violet': r = 124/255; g = 58/255;  b = 237/255; break;
    case 'pink':   r = 217/255; g = 70/255;  b = 239/255; break;
    case 'coral':  r = 251/255; g = 113/255; b = 133/255; break;
    case 'blue':   r = 30/255;  g = 80/255;  b = 180/255; break;
    case 'green':  r = 22/255;  g = 163/255; b = 74/255;  break;
    case 'red':    r = 220/255; g = 38/255;  b = 38/255;  break;
    case 'yellow': r = 245/255; g = 158/255; b = 11/255;  break;
  }

  // ★ NSApplication 초기화 + Accessory mode
  $.NSApplication.sharedApplication;
  $.NSApp.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  // ★ GIF 실제 픽셀 사이즈 가져오기
  var iconImage = $.NSImage.alloc.initWithContentsOfFile(gifPath);
  if (!iconImage || iconImage.isNil()) return;

  var imageSize = iconImage.size;
  var origW = imageSize.width;
  var origH = imageSize.height;

  // 화면용 적절한 사이즈로 스케일 (가로 max 320, 세로 max 360 — 비율 유지)
  // 작은 GIF (200x150 등)는 그대로, 큰 GIF는 더 제약적인 축으로 fit
  var maxWidth = 320, maxHeight = 360, minWidth = 200;
  var widthScale = (origW > maxWidth) ? (maxWidth / origW) : 1.0;
  var heightScale = (origH > maxHeight) ? (maxHeight / origH) : 1.0;
  var scale = Math.min(widthScale, heightScale);  // 더 제약적인 축으로 통일
  var gifWidth = Math.round(origW * scale);
  var gifHeight = Math.round(origH * scale);
  // 너무 작은 GIF는 minWidth로 보장 (가로) — 텍스트 박스 가독성
  if (gifWidth < minWidth) {
    var upscale = minWidth / gifWidth;
    gifWidth = minWidth;
    gifHeight = Math.round(gifHeight * upscale);
  }

  // 텍스트 영역 (GIF 위 오버레이 — Netflix 스타일 하단 그라디언트)
  var textHeight = 44;

  var winWidth = gifWidth;
  var winHeight = gifHeight;  // GIF 사이즈와 동일 (텍스트는 GIF 위 overlay)

  // 화면 위치
  var screen = $.NSScreen.mainScreen;
  var visibleFrame = screen.visibleFrame;
  var margin = 20;
  var x, y;
  switch (position) {
    case 'top-left':
      x = visibleFrame.origin.x + margin;
      y = visibleFrame.origin.y + visibleFrame.size.height - winHeight - margin;
      break;
    case 'top-center':
      x = visibleFrame.origin.x + (visibleFrame.size.width - winWidth) / 2;
      y = visibleFrame.origin.y + visibleFrame.size.height - winHeight - margin;
      break;
    case 'bottom-left':
      x = visibleFrame.origin.x + margin;
      y = visibleFrame.origin.y + margin;
      break;
    case 'bottom-right':
      x = visibleFrame.origin.x + visibleFrame.size.width - winWidth - margin;
      y = visibleFrame.origin.y + margin;
      break;
    case 'bottom-center':
      x = visibleFrame.origin.x + (visibleFrame.size.width - winWidth) / 2;
      y = visibleFrame.origin.y + margin;
      break;
    case 'top-right':
    default:
      x = visibleFrame.origin.x + visibleFrame.size.width - winWidth - margin;
      y = visibleFrame.origin.y + visibleFrame.size.height - winHeight - margin;
  }
  var frame = $.NSMakeRect(x, y, winWidth, winHeight);

  // ★ 투명 배경 NSWindow
  var win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
    frame,
    $.NSWindowStyleMaskBorderless,
    $.NSBackingStoreBuffered,
    false
  );

  win.setBackgroundColor($.NSColor.clearColor);  // ★ 투명
  win.setOpaque(false);
  win.setHasShadow(true);  // 그림자만 (윈도우 외곽선)
  win.setLevel($.NSStatusWindowLevel);
  win.setIgnoresMouseEvents(true);
  win.setCollectionBehavior(
    $.NSWindowCollectionBehaviorCanJoinAllSpaces |
    $.NSWindowCollectionBehaviorStationary
  );

  // 둥근 모서리 (GIF 영역에 적용)
  win.contentView.wantsLayer = true;
  win.contentView.layer.cornerRadius = 16;
  win.contentView.layer.masksToBounds = true;

  var contentView = win.contentView;

  // ★ GIF 표시 (전체 영역)
  var iconView = $.NSImageView.alloc.initWithFrame(
    $.NSMakeRect(0, 0, gifWidth, gifHeight)
  );
  iconView.setImage(iconImage);
  iconView.setImageScaling($.NSImageScaleProportionallyUpOrDown);
  iconView.setAnimates(true);  // GIF 애니메이션
  contentView.addSubview(iconView);

  // ★ 텍스트 박스 (NSBox 사용 — CGColor 변환 안 씀)
  var textBox = $.NSBox.alloc.initWithFrame(
    $.NSMakeRect(0, 0, gifWidth, textHeight)
  );
  textBox.setBoxType($.NSBoxCustom);
  textBox.setBorderType($.NSNoBorder);
  textBox.setTitle($(''));
  textBox.setFillColor($.NSColor.colorWithSRGBRedGreenBlueAlpha(0, 0, 0, 0.72));
  textBox.setContentViewMargins({ width: 0, height: 0 });
  contentView.addSubview(textBox);

  // 액센트 색상 막대 (왼쪽 세로줄)
  var accentBar = $.NSBox.alloc.initWithFrame(
    $.NSMakeRect(12, 11, 3, 18)
  );
  accentBar.setBoxType($.NSBoxCustom);
  accentBar.setBorderType($.NSNoBorder);
  accentBar.setTitle($(''));
  accentBar.setFillColor($.NSColor.colorWithSRGBRedGreenBlueAlpha(r, g, b, 1.0));
  contentView.addSubview(accentBar);

  // 메시지 라벨 (GIF 하단)
  var label = $.NSTextField.alloc.initWithFrame(
    $.NSMakeRect(22, 12, gifWidth - 32, 18)
  );
  label.setStringValue($(message));
  label.setBezeled(false);
  label.setDrawsBackground(false);
  label.setEditable(false);
  label.setSelectable(false);
  label.setTextColor($.NSColor.whiteColor);
  label.setAlignment($.NSTextAlignmentLeft);
  label.setFont($.NSFont.boldSystemFontOfSize(13));
  label.setLineBreakMode($.NSLineBreakByTruncatingTail);
  contentView.addSubview(label);

  // 크로마이핑 작은 배지 (라벨 아래)
  var badge = $.NSTextField.alloc.initWithFrame(
    $.NSMakeRect(22, -2, gifWidth - 32, 14)
  );
  badge.setStringValue($('CROMAIPING'));
  badge.setBezeled(false);
  badge.setDrawsBackground(false);
  badge.setEditable(false);
  badge.setSelectable(false);
  badge.setTextColor($.NSColor.colorWithSRGBRedGreenBlueAlpha(1, 1, 1, 0.6));
  badge.setAlignment($.NSTextAlignmentLeft);
  badge.setFont($.NSFont.boldSystemFontOfSize(8));
  contentView.addSubview(badge);

  // 윈도우 표시
  win.orderFrontRegardless;

  // 자동 dismiss
  if (dismiss > 0) {
    var dismissTimer = $.NSTimer.timerWithTimeIntervalTargetSelectorUserInfoRepeats(
      dismiss, $.NSApp, 'terminate:', null, false
    );
    $.NSRunLoop.mainRunLoop.addTimerForMode(dismissTimer, 'NSRunLoopCommonModes');
    $.NSApp.performSelectorWithObjectAfterDelay('terminate:', null, dismiss);
  }

  // 이벤트 루프 시작
  $.NSApp.run;
}
