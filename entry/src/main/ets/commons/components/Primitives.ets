import { Radius, Space, Type } from '../theme/Theme';

/** 白底圆角卡片：所有内容区块的统一容器 */
@Component
export struct CardSurface {
  /** 内边距（避开基类 padding 属性故命名 cardPadding） */
  @Prop cardPadding: number = Space.MD;
  @Prop radius: number = Radius.LG;
  /** 插槽默认值必须是 struct 内 @Builder 方法（模块级 @Builder function 在此 SDK 上会使尾随块传入后仍为 undefined） */
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    Column({ space: Space.SM }) {
      this.content();
    }
    .width('100%')
    .padding(this.cardPadding)
    .backgroundColor(Color.White)
    .borderRadius(this.radius)
  }
}

/** 区块小标题（左对齐，家长端统一 18vp） */
@Component
export struct SectionTitle {
  @Prop text: string = '';
  /** 字号（避开基类 size 属性故命名 textSize） */
  @Prop textSize: number = Type.SUBTITLE;

  build() {
    Text(this.text)
      .fontSize(this.textSize)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.cocoa_text'))
      .alignSelf(ItemAlign.Start)
      .width('100%')
  }
}

/** 空状态提示（灰字，左对齐） */
@Component
export struct EmptyHint {
  @Prop text: string = '';

  build() {
    Text(this.text)
      .fontSize(Type.CAPTION)
      .fontColor($r('app.color.mist_gray'))
      .alignSelf(ItemAlign.Start)
      .width('100%')
  }
}
