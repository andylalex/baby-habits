/**
 * 弹窗/全屏覆盖层的尺寸适配规则（所有弹窗共用，保证多设备一致）。
 *
 * 目标：弹窗在手机 / 平板 / 折叠屏 / PC、横竖屏下都能完整显示——
 *  · 内容宽度：窄屏用百分比（随屏宽），宽屏限宽居中（不被拉伸变形）
 *  · 内容高度：不超过可用高度，超出时内部可滚动
 *  · 安全区：顶部避让状态栏/挖孔，底部避让导航条
 *  · 大图：按可用宽高同时约束，保持比例，不溢出屏幕
 *
 * 【铺满设备的关键】
 * `expandSafeArea` 只扩展【绘制区域】，不改布局位置和大小 —— 弹窗背景能画到状态栏下，
 * 但内部内容仍被安全区限制，视觉上"没覆盖设备"。
 * `ignoreLayoutSafeArea` 才会让组件的【布局位置和大小】一并扩展到非安全区，
 * 配合内容自身的 padding 避让，才是真正的全屏铺满。
 */
export class SheetFit {
  /** 弹窗内容最大宽度（vp）：超宽屏上不让卡片无限拉宽 */
  static readonly MAX_W: number = 520;
  /** 全屏看图的内容最大宽度（vp） */
  static readonly MAX_W_FULL: number = 900;

  /**
   * 弹窗卡片宽度：窄屏 92%（随屏宽），宽屏固定 MAX_W（超宽屏不无限拉伸）。
   * 传入视口宽做兜底，确保任何情况下都不超出屏幕。
   */
  static cardWidth(isSm: boolean, screenW: number = 0): string {
    if (isSm) {
      return '92%';
    }
    if (screenW > 0 && screenW < SheetFit.MAX_W) {
      return '92%';
    }
    return `${SheetFit.MAX_W}`;
  }

  /**
   * 弹窗内容区的垂直内边距：顶部避让状态栏，底部避让导航条。
   * @param safeTop 顶部安全区高度（vp）
   */
  static padTop(safeTop: number): number {
    return safeTop + 12;
  }

  static padBottom(safeBottom: number): number {
    return safeBottom + 12;
  }
}
