import { BadgeDao } from '../commons/db/Dao';
import { SeedData } from '../commons/db/SeedData';
import { BADGES, BadgeDef } from '../commons/utils/Badges';
import { AppButton, AppButtonVariant } from '../commons/components/AppButton';
import { SectionTitle } from '../commons/components/Primitives';
import { Breakpoint } from '../commons/utils/BreakpointSystem';
import { Sound } from '../commons/utils/Sound';
import { Space, Type } from '../commons/theme/Theme';

/**
 * 儿童端 · 成就墙：已解锁勋章彩色发光，未解锁灰色 + 条件提示。
 * 解锁判定全本地（BadgeDao.evaluate 在首页 Index 每次刷新后触发，幂等）。
 */
@Entry
@Component
struct KidBadges {
  @StorageProp('currentBreakpoint') breakpoint: Breakpoint = 'sm';
  /** 顶部系统避让区高度（vp）：窗口沉浸式下布局已铺满全屏，需自行避让状态栏 */
  @StorageProp('safeAreaTop') safeAreaTop: number = 28;
  /** 底部系统避让区高度（vp，导航条/手势条） */
  @StorageProp('safeAreaBottom') safeAreaBottom: number = 0;
  @State unlocked: Set<string> = new Set();

  aboutToAppear(): void {
    Sound.init();
    this.reload();
  }

  async reload(): Promise<void> {
    this.unlocked = await BadgeDao.unlockedIds(SeedData.DEMO_KID_ID);
  }

  isSm(): boolean {
    return this.breakpoint === 'sm';
  }

  /** 每行勋章数：手机 3，平板 4，大屏 5 */
  columns(): number {
    if (this.breakpoint === 'lg') {
      return 5;
    }
    return this.breakpoint === 'md' ? 4 : 3;
  }

  /** 主动分行，避免 Flex wrap 在 Scroll 内测量问题 */
  badgeRows(): BadgeDef[][] {
    const cols = this.columns();
    const rows: BadgeDef[][] = [];
    for (let i = 0; i < BADGES.length; i += cols) {
      const slice: BadgeDef[] = [];
      for (let j = i; j < Math.min(i + cols, BADGES.length); j++) {
        slice.push(BADGES[j]);
      }
      rows.push(slice);
    }
    return rows;
  }

  @Builder
  BadgeCell(b: BadgeDef) {
    Column({ space: 6 }) {
      Text(b.icon)
        .fontSize(this.isSm() ? 36 : 48)
        .opacity(this.unlocked.has(b.id) ? 1.0 : 0.35)
      Text(b.title)
        .fontSize(this.isSm() ? Type.CAPTION : Type.BODY)
        .fontWeight(this.unlocked.has(b.id) ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.unlocked.has(b.id) ? $r('app.color.cocoa_text') : $r('app.color.mist_gray'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (!this.unlocked.has(b.id)) {
        Text(b.condition)
          .fontSize(11)
          .fontColor($r('app.color.mist_gray'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .padding({ left: 4, right: 4 })
      }
    }
    .width('100%')
    .height(this.isSm() ? 116 : 136)
    .justifyContent(FlexAlign.Center)
    .padding(6)
    .backgroundColor(this.unlocked.has(b.id) ? Color.White : '#F7F3EC')
    .borderRadius(20)
    .border({
      width: this.unlocked.has(b.id) ? 2 : 1,
      color: this.unlocked.has(b.id) ? $r('app.color.star_yellow') : '#E8E0D4'
    })
    .shadow(this.unlocked.has(b.id)
      ? { radius: 10, color: '#33E8A51F', offsetY: 4 }
      : { radius: 0, color: '#00000000' })
    .onClick(() => {
      if (this.unlocked.has(b.id)) {
        Sound.speak(`已获得勋章：${b.title}`);
      } else {
        Sound.speak(`还差一点点：${b.condition}`);
      }
    })
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: Space.SM }) {
          Column({ space: 2 }) {
            Text('我的勋章')
              .fontSize(this.isSm() ? Type.HEADLINE : Type.DISPLAY)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.cocoa_text'))
              .alignSelf(ItemAlign.Start)
            Text(`已经点亮 ${this.unlocked.size} / ${BADGES.length} 枚`)
              .fontSize(Type.CAPTION)
              .fontColor($r('app.color.mist_gray'))
              .alignSelf(ItemAlign.Start)
          }
          .width('100%')

          SectionTitle({ text: '成就墙', textSize: Type.BODY })
          ForEach(this.badgeRows(), (row: BadgeDef[]) => {
            Row({ space: Space.SM }) {
              ForEach(row, (b: BadgeDef) => {
                Column() {
                  this.BadgeCell(b)
                }
                .layoutWeight(1)
                .constraintSize({ minWidth: 0 })
              }, (b: BadgeDef) => b.id)
            }
            .width('100%')
          }, (row: BadgeDef[]) => row.map((b: BadgeDef) => b.id).join('-'))

          AppButton({
            label: '← 返回',
            variant: AppButtonVariant.Soft,
            btnHeight: 48,
            onTap: () => {
              this.getUIContext().getRouter().back();
            }
          })
            .width(this.isSm() ? '100%' : 320)
            .margin({ top: Space.SM })
        }
        .width('100%')
        .constraintSize({ maxWidth: 640 })
        .padding({ left: 24, right: 24, top: this.safeAreaTop + 12, bottom: this.safeAreaBottom + 32 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.cream_background'))
  }
}
