import { uiMaterial } from '@kit.ArkUI';

/**
 * 沉浸光感（Immersive Material）材质工厂。
 *
 * 为什么要做这一层：
 * 1. `ImmersiveMaterial` **只在支持沉浸材质的设备上才有效果**，不支持的设备上设置了也不起作用
 *    （组件样式仍由已设置的通用属性决定）。官方明确「不支持的设备上可设置但无效果」，
 *    所以材质实例可以无条件设置，不需要在调用点写 if/else —— 这也是本文件只提供工厂、
 *    不返回 undefined 的原因（返回 undefined 会让 `systemMaterial` 走「按不设置处理」的分支，
 *    与「设置但无效果」不是一回事）。
 * 2. `systemMaterial` 通用属性对 **Button / Select / Toggle 等选择类组件只在
 *    Navigation·NavDestination 标题栏或横向 Tabs 的底部 TabBar 中生效**；
 *    页面内悬浮的圆形按钮必须由**外层容器**承载材质（内层按钮背景透明，让玻璃透出）——
 *    本工程底部悬浮栏用的就是这个套路。
 * 3. 材质一旦生效会接管 `backgroundColor` / `borderColor` / `borderWidth` / `shadow`
 *    （背景色被清空为透明、边框被清空为无边框）。**因此材质必须写在这些属性之后**，
 *    不然材质会被后设的背景色盖住，玻璃透不出来。
 */
export class MaterialSupport {
  /**
   * 薄材质（THIN）：适合小面积悬浮控件 —— 圆形按钮、胶囊。
   * interactive=true 提供按压形变与光感交互反馈，替代系统默认的按压态。
   */
  static thin(interactive: boolean = true): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      interactive: interactive,
      applyShadow: true,
      lightEffect: { color: undefined }
    });
  }

  /**
   * 厚材质（THICK）：适合浮层面板 —— 菜单、弹窗。
   * 官方菜单设计指南建议菜单采用沉浸光感样式，以增强浮层与页面之间的空间层级；
   * 菜单常覆盖图片/列表等复杂背景，THICK 是稳妥起点。
   */
  static thick(colorInvert: boolean = false): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THICK,
      colorInvert: colorInvert,
      interactive: true,
      applyShadow: true
    });
  }
}
