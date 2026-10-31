/**
 * 任务/心愿插画统一渲染组件。
 * icon 字段约定：'raw:xxx.png' 渲染 rawfile 插画；否则按 emoji 文本渲染（兼容旧数据）。
 * 插画资源：src/main/resources/rawfile/icons/
 */
@Component
export struct HabitIcon {
  @Prop icon: string = '';
  /** 边长（vp），避开基类 size 属性故命名 iconSize */
  @Prop iconSize: number = 64;
  /** 插画圆角 */
  @Prop radius: number = 16;

  build() {
    if (this.icon.startsWith('raw:')) {
      Image($rawfile(this.icon.slice(4)))
        .width(this.iconSize)
        .height(this.iconSize)
        .borderRadius(this.radius)
        .objectFit(ImageFit.Cover)
    } else {
      Text(this.icon)
        .fontSize(this.iconSize)
    }
  }
}
