import { HabitIcon } from './HabitIcon';
import { Radius, Space, Type } from '../theme/Theme';

/**
 * 通用「图标 + 标题 + 右侧操作」行卡片。
 * 家长端任务/心愿/推荐任务三处列表共用，右侧操作由 trailing 插槽注入。
 */
@Component
export struct HabitRow {
  @Prop icon: string = '';
  @Prop title: string = '';
  /** 图标下方小字（分类 / 星星价等），为空则不显示 */
  @Prop meta: string = '';
  @Prop iconSize: number = 40;
  /** 插槽默认值必须是 struct 内 @Builder 方法 */
  @BuilderParam trailing: () => void = this.emptyTrailing;

  @Builder
  emptyTrailing() {
  }

  build() {
    Row({ space: Space.MD }) {
      HabitIcon({ icon: this.icon, iconSize: this.iconSize, radius: Radius.SM })
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(Type.TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.cocoa_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .alignSelf(ItemAlign.Start)
        if (this.meta !== '') {
          Text(this.meta)
            .fontSize(Type.CAPTION)
            .fontColor($r('app.color.mist_gray'))
            .alignSelf(ItemAlign.Start)
        }
      }
      .layoutWeight(1)
      .constraintSize({ minWidth: 0 })

      Row({ space: Space.SM }) {
        this.trailing();
      }
    }
    .width('100%')
    .padding(Space.MD + 2)
    .backgroundColor(Color.White)
    .borderRadius(Radius.LG)
  }
}
