import { window } from '@kit.ArkUI';

export type Breakpoint = 'sm' | 'md' | 'lg';

/**
 * 断点判定：以窗口【最短边】为准，而不是宽度。
 * 原因：手机横屏（如 780×360）宽度已达 780，若只看宽度会被判成 md/lg，
 * 按平板布局渲染，但可用高度只有 360vp，弹窗/卡片必然放不下。
 * 用最短边判定后，横屏手机仍是 sm，折叠屏展开/平板才是大屏。
 */
export function classify(widthVp: number, heightVp: number = widthVp): Breakpoint {
  const shortest = Math.min(widthVp, heightVp);
  if (shortest < 600) {
    return 'sm';
  }
  if (shortest < 840) {
    return 'md';
  }
  return 'lg';
}

/**
 * M1 断点系统：监听主窗口尺寸变化，写入 AppStorage('currentBreakpoint')。
 * 页面内用 @StorageProp('currentBreakpoint') 订阅，驱动响应式布局。
 * 断点口径与技术方案 §2.1 一致：sm<600 / md 600-840 / lg≥840。
 */
export class BreakpointSystem {
  static async attach(win: window.Window): Promise<void> {
    const update = (widthPx: number): void => {
      // windowRect.width / windowSizeChange 的宽度单位均为像素(px)，
      // 而 classify 的阈值按 vp 设计，须先 px2vp 换算，否则手机(≈1080px)永远被判成 lg
      const w = px2vp(widthPx);
      const rect = win.getWindowProperties().windowRect;
      const h = px2vp(Number(rect.height));
      // 断点按最短边判定（横屏手机也算 sm），窗口宽高另行发布供弹窗自适应
      AppStorage.setOrCreate<Breakpoint>('currentBreakpoint', classify(w, h));
      AppStorage.setOrCreate<number>('windowWidth', w);
      AppStorage.setOrCreate<number>('windowHeight', h);
    };
    win.on('windowSizeChange', (size: window.Size) => {
      update(size.width);
    });
    const rect = win.getWindowProperties().windowRect;
    update(rect.width);
    BreakpointSystem.updateSafeArea(win);
    // 避让区变化（旋转/折叠展开/分屏切换）时重算
    win.on('avoidAreaChange', (): void => {
      BreakpointSystem.updateSafeArea(win);
    });
  }

  /**
   * 采集系统避让区（状态栏/导航栏/挖孔）高度，写入 AppStorage('safeAreaTop')。
   * 页面根若调了 expandSafeArea 顶进状态栏，悬浮元素须靠这个值自己避让，
   * 不能写死数值（刘海屏/挖孔屏状态栏高度不同）。
   */
  private static updateSafeArea(win: window.Window): void {
    let topPx: number = 0;
    try {
      topPx = Number(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height);
    } catch (err) {
      topPx = 0;
    }
    try {
      // 挖孔/刘海区域：部分设备形态下可能不支持，单独兜底
      const cutoutTop = Number(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT).topRect.height);
      if (cutoutTop > topPx) {
        topPx = cutoutTop;
      }
    } catch (err) {
      // 忽略：无挖孔区域
    }
    // 底部避让区（导航条/手势条）
    let bottomPx: number = 0;
    try {
      bottomPx = Number(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height);
    } catch (err) {
      bottomPx = 0;
    }
    if (bottomPx <= 0) {
      try {
        bottomPx = Number(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).bottomRect.height);
      } catch (err) {
        bottomPx = 0;
      }
    }
    // 避让区高度单位是 px，UI 用 vp，必须换算；都取不到时按常见值兜底
    AppStorage.setOrCreate<number>('safeAreaTop', topPx > 0 ? px2vp(topPx) : 28);
    AppStorage.setOrCreate<number>('safeAreaBottom', bottomPx > 0 ? px2vp(bottomPx) : 0);
  }
}

/** 全局状态键（AppStorage） */
export class AppKeys {
  static readonly BREAKPOINT: string = 'currentBreakpoint';
  static readonly ROLE: string = 'currentRole';
  static readonly ACTIVE_KID_ID: string = 'activeKidId';
  /** 顶部系统避让区高度（vp） */
  static readonly SAFE_AREA_TOP: string = 'safeAreaTop';
  /** 底部系统避让区高度（vp，导航条/手势条） */
  static readonly SAFE_AREA_BOTTOM: string = 'safeAreaBottom';
  /** 窗口宽度（vp） */
  static readonly WINDOW_WIDTH: string = 'windowWidth';
  /** 窗口高度（vp） */
  static readonly WINDOW_HEIGHT: string = 'windowHeight';
}
