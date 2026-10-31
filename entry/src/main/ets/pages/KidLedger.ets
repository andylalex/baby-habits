import { LedgerEntry } from '../commons/models/Models';
import { StarDao } from '../commons/db/Dao';
import { SeedData } from '../commons/db/SeedData';
import { AppButton, AppButtonVariant } from '../commons/components/AppButton';
import { SectionTitle } from '../commons/components/Primitives';
import { Breakpoint } from '../commons/utils/BreakpointSystem';
import { Sound } from '../commons/utils/Sound';
import { Space, Type } from '../commons/theme/Theme';

/**
 * 儿童端 · 星星账本：每一颗星星的来龙去脉（收入绿 / 支出粉）。
 * 数据全本地：stars_ledger 流水表，余额永远等于流水 SUM。
 */
@Entry
@Component
struct KidLedger {
  @StorageProp('currentBreakpoint') breakpoint: Breakpoint = 'sm';
  /** 顶部系统避让区高度（vp）：窗口沉浸式下布局已铺满全屏，需自行避让状态栏 */
  @StorageProp('safeAreaTop') safeAreaTop: number = 28;
  /** 底部系统避让区高度（vp，导航条/手势条） */
  @StorageProp('safeAreaBottom') safeAreaBottom: number = 0;
  @State entries: LedgerEntry[] = [];
  @State balance: number = 0;

  aboutToAppear(): void {
    Sound.init();
    this.reload();
  }

  async reload(): Promise<void> {
    this.balance = await StarDao.balance(SeedData.DEMO_KID_ID);
    this.entries = await StarDao.listLedger(SeedData.DEMO_KID_ID, 300);
  }

  isSm(): boolean {
    return this.breakpoint === 'sm';
  }

  /** 条目的日期部分（YYYY-MM-DD → 中文短日期） */
  dateOf(e: LedgerEntry): string {
    const d = e.createdAt.length >= 10 ? e.createdAt.substring(0, 10) : e.createdAt;
    const parts = d.split('-');
    if (parts.length === 3) {
      return `${Number(parts[1])}月${Number(parts[2])}日`;
    }
    return d;
  }

  /** 同日相邻条目才显示日期分隔，避免满屏重复日期 */
  showDate(index: number): boolean {
    if (index === 0) {
      return true;
    }
    const cur = this.entries[index].createdAt.substring(0, 10);
    const prev = this.entries[index - 1].createdAt.substring(0, 10);
    return cur !== prev;
  }

  iconOf(e: LedgerEntry): string {
    if (e.delta < 0) {
      return '🎁';
    }
    return e.reason === 'bonus' ? '✨' : '⭐';
  }

  @Builder
  RowItem(e: LedgerEntry) {
    Row({ space: Space.MD }) {
      Text(this.iconOf(e))
        .fontSize(this.isSm() ? 24 : 28)
        .width(48)
        .height(48)
        .textAlign(TextAlign.Center)
        .backgroundColor(e.delta < 0 ? $r('app.color.soft_pink') : $r('app.color.soft_yellow'))
        .borderRadius(24)
      Column({ space: 2 }) {
        Text(e.title)
          .fontSize(this.isSm() ? Type.BODY : Type.TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.cocoa_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .alignSelf(ItemAlign.Start)
        Text(this.dateOf(e))
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.mist_gray'))
          .alignSelf(ItemAlign.Start)
      }
      .layoutWeight(1)
      .constraintSize({ minWidth: 0 })

      Text(`${e.delta > 0 ? '+' : ''}${e.delta}`)
        .fontSize(this.isSm() ? Type.TITLE : Type.HEADLINE)
        .fontWeight(FontWeight.Bold)
        .fontColor(e.delta < 0 ? $r('app.color.danger') : $r('app.color.done_green'))
    }
    .width('100%')
    .padding(Space.MD)
    .backgroundColor(Color.White)
    .borderRadius(20)
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: Space.SM }) {
          // 顶部：余额总览
          Row({ space: Space.MD }) {
            Column({ space: 2 }) {
              Text('星星账本')
                .fontSize(this.isSm() ? Type.HEADLINE : Type.DISPLAY)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.cocoa_text'))
                .alignSelf(ItemAlign.Start)
              Text('每一颗星星从哪来、到哪去')
                .fontSize(Type.CAPTION)
                .fontColor($r('app.color.mist_gray'))
                .alignSelf(ItemAlign.Start)
            }
            .layoutWeight(1)
            .constraintSize({ minWidth: 0 })

            Row({ space: 6 }) {
              Text('🫙')
                .fontSize(this.isSm() ? 22 : 28)
              Text(`${this.balance}`)
                .fontSize(this.isSm() ? 22 : 28)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.cocoa_text'))
            }
            .padding({ left: 18, right: 18, top: 10, bottom: 10 })
            .backgroundColor($r('app.color.soft_blue'))
            .borderRadius(999)
            .onClick(() => {
              Sound.speak(`你有 ${this.balance} 颗星星`);
            })
          }
          .width('100%')

          if (this.entries.length === 0) {
            Column({ space: 8 }) {
              Text('🌱')
                .fontSize(48)
              Text('还没有星星记录')
                .fontSize(Type.TITLE)
                .fontColor($r('app.color.cocoa_text'))
              Text('去完成任务，赚取第一颗星星吧！')
                .fontSize(Type.BODY)
                .fontColor($r('app.color.mist_gray'))
            }
            .width('100%')
            .padding({ top: 80, bottom: 80 })
          } else {
            SectionTitle({ text: '收支明细', textSize: Type.BODY })
            ForEach(this.entries, (e: LedgerEntry, index: number) => {
              Column({ space: 6 }) {
                if (this.showDate(index)) {
                  Text(this.dateOf(e))
                    .fontSize(Type.CAPTION)
                    .fontColor($r('app.color.mist_gray'))
                    .alignSelf(ItemAlign.Start)
                    .padding({ left: 4, top: 4 })
                }
                this.RowItem(e)
              }
              .width('100%')
            }, (e: LedgerEntry) => `${e.id}`)
          }

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
