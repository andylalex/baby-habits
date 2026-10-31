import { Radius, Type, MIN_TOUCH } from '../theme/Theme';

/** 按钮视觉变体：全端只允许这四种，杜绝各页自定义配色 */
export enum AppButtonVariant {
  /** 主行动：品牌橙 */
  Primary,
  /** 次级行动：奶油黄底 */
  Soft,
  /** 破坏性行动：粉底红字（停用 / 下架 / 重置） */
  Danger,
  /** 描边幽灵按钮：筛选胶囊、次要入口 */
  Outline
}

/**
 * 全端统一按钮。
 * 统一：最小触控高度 44、圆角、字号、按压反馈、禁用态。
 */
@Component
export struct AppButton {
  @Prop label: string = '';
  @Prop variant: AppButtonVariant = AppButtonVariant.Primary;
  /** 按钮高度（避开基类 height 属性故命名 btnHeight） */
  @Prop btnHeight: number = 52;
  @Prop fontSize: number = Type.BODY;
  /** 是否可点击（避开基类 enabled 属性故命名 isEnabled） */
  @Prop isEnabled: boolean = true;
  /** true 时撑满父容器宽度（表单主按钮） */
  @Prop block: boolean = false;
  onTap: () => void = () => {
  };

  bgColor(): ResourceColor {
    switch (this.variant) {
      case AppButtonVariant.Primary:
        return $r('app.color.brand_orange');
      case AppButtonVariant.Soft:
        return $r('app.color.soft_yellow');
      case AppButtonVariant.Danger:
        return $r('app.color.soft_pink');
      default:
        return Color.White;
    }
  }

  fgColor(): ResourceColor {
    switch (this.variant) {
      case AppButtonVariant.Primary:
        return Color.White;
      case AppButtonVariant.Danger:
        return $r('app.color.danger');
      default:
        return $r('app.color.cocoa_text');
    }
  }

  build() {
    Button(this.label)
      .fontSize(this.fontSize)
      .fontWeight(this.variant === AppButtonVariant.Primary ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.fgColor())
      .backgroundColor(this.bgColor())
      .borderRadius(Radius.PILL)
      .height(this.btnHeight)
      .constraintSize({ minHeight: MIN_TOUCH })
      .width(this.block ? '100%' : 'auto')
      // 手机窄屏防溢出：按钮不超出父容器（labelStyle 会在渲染期抛异常，已移除）
      .constraintSize({ maxWidth: '100%' })
      .padding({ left: 20, right: 20 })
      .enabled(this.isEnabled)
      .opacity(this.isEnabled ? 1.0 : 0.45)
      .border(this.variant === AppButtonVariant.Outline ?
        { width: 2, color: $r('app.color.hairline') } :
        { width: 0, color: Color.Transparent })
      .onClick(() => {
        this.onTap();
      })
  }
}
