/**
 * 设计令牌（Design Tokens）
 * 单一事实来源：间距 / 圆角 / 字号 / 阴影 / 动效时长。
 * 页面里禁止再硬编码这些数值，统一引用本文件——改一处即全端生效。
 */
export class Space {
  /** 4 图标与文字的微间距 */
  static readonly XS: number = 4;
  /** 8 同一行内元素间距 */
  static readonly SM: number = 8;
  /** 12 卡片之间 */
  static readonly MD: number = 12;
  /** 16 区块之间 */
  static readonly LG: number = 16;
  /** 24 页面边距 / 大区块 */
  static readonly XL: number = 24;
}

export class Radius {
  static readonly SM: number = 12;
  static readonly MD: number = 16;
  static readonly LG: number = 20;
  static readonly XL: number = 24;
  /** 胶囊形按钮 */
  static readonly PILL: number = 999;
}

/** 字号阶梯：宝宝端偏大、家长端偏紧凑，但都取自同一阶梯 */
export class Type {
  static readonly MICRO: number = 11;
  static readonly CAPTION: number = 13;
  static readonly BODY: number = 16;
  static readonly SUBTITLE: number = 18;
  static readonly TITLE: number = 20;
  /** 页面主标题 */
  static readonly HEADLINE: number = 28;
  /** 宝宝端强调（任务名 / 大按钮） */
  static readonly DISPLAY: number = 32;
}

export class Elevation {
  /** 卡片轻投影 */
  static readonly CARD: ShadowOptions = { radius: 8, color: '#1A000000', offsetY: 2 };
  /** 浮层 / 按钮投影 */
  static readonly FLOAT: ShadowOptions = { radius: 16, color: '#33000000', offsetY: 6 };
}

export class Motion {
  /** 按压反馈 */
  static readonly TAP: number = 120;
  /** 常规过渡 */
  static readonly BASE: number = 300;
  /** 水位 / 星星生长 */
  static readonly SLOW: number = 800;
}

/** 触控目标最小边长（儿童手指，UI 规范） */
export const MIN_TOUCH: number = 44;
