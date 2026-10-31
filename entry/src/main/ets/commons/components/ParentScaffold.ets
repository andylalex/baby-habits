import { AppButton, AppButtonVariant } from './AppButton';
import { Space, Type } from '../theme/Theme';

/**
 * 家长端页面骨架：标题栏 + 内容区 + 底部返回。
 * 统一：沉浸式安全区、顶部状态栏留白、奶油底、区块间距、返回按钮。
 * 四个家长页共用，新增页面不要再手写根容器。
 */
@Component
export struct ParentScaffold {
  @Prop title: string = '';
  /** 顶部系统避让区高度（vp，来自 getWindowAvoidArea）：窗口沉浸式下需自行避让状态栏 */
  @StorageProp('safeAreaTop') safeAreaTop: number = 28;
  /** 底部系统避让区高度（vp，导航条/手势条） */
  @StorageProp('safeAreaBottom') safeAreaBottom: number = 0;
  /** 标题栏右侧操作按钮文案，空串则不显示（用普通回调参数替代 actions 插槽：
   *  尾随闭包要求组件有且仅有一个 @BuilderParam，多插槽组件无法使用尾随闭包） */
  actionLabel: string = '';
  onActionTap: () => void = () => {
  }
  /** 主内容插槽：调用方必须用尾随闭包传入（按引用传递，this 指向调用方页面） */
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    Column({ space: Space.MD }) {
      Row({ space: Space.SM }) {
        Text(this.title)
          .fontSize(Type.HEADLINE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.cocoa_text'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.actionLabel !== '') {
          AppButton({
            label: this.actionLabel,
            variant: AppButtonVariant.Danger,
            btnHeight: 40,
            fontSize: Type.CAPTION,
            onTap: this.onActionTap
          })
        }
      }
      .width('100%')

      this.content();

      AppButton({
        label: '← 返回',
        variant: AppButtonVariant.Soft,
        btnHeight: 48,
        onTap: () => {
          this.getUIContext().getRouter().back();
        }
      })
        .alignSelf(ItemAlign.Center)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    // 顶部留白避让状态栏（窗口沉浸式下布局已铺满全屏，必须自行避让）
    // 底部留白避让导航条/手势条
    .padding({
      left: Space.XL - 4,
      right: Space.XL - 4,
      top: this.safeAreaTop + 8,
      bottom: this.safeAreaBottom + 16
    })
    .backgroundColor($r('app.color.cream_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
