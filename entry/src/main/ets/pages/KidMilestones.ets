import { MilestoneDao } from '../commons/db/Dao';
import { SeedData } from '../commons/db/SeedData';
import { MilestoneItem } from '../commons/models/Models';
import { AppButton, AppButtonVariant } from '../commons/components/AppButton';
import { SectionTitle } from '../commons/components/Primitives';
import { Breakpoint } from '../commons/utils/BreakpointSystem';
import { Sound } from '../commons/utils/Sound';
import { Space, Type } from '../commons/theme/Theme';

interface MilestoneProgress {
  item: MilestoneItem;
  current: number;
  pct: number;
}

/**
 * 儿童端 · 里程碑旅行路线图：纵向站点连线。
 * 三态：已达成亮金 / 进行中(当前站)脉冲 / 未来灰。
 * 下方纪念墙展示家长已兑现的里程碑卡。
 */
@Entry
@Component
struct KidMilestones {
  @StorageProp('currentBreakpoint') breakpoint: Breakpoint = 'sm';
  /** 顶部系统避让区高度（vp）：窗口沉浸式下布局已铺满全屏，需自行避让状态栏 */
  @StorageProp('safeAreaTop') safeAreaTop: number = 28;
  /** 底部系统避让区高度（vp，导航条/手势条） */
  @StorageProp('safeAreaBottom') safeAreaBottom: number = 0;
  @State items: MilestoneItem[] = [];
  @State progresses: MilestoneProgress[] = [];

  aboutToAppear(): void {
    Sound.init();
    this.reload();
  }

  async reload(): Promise<void> {
    this.items = await MilestoneDao.list(SeedData.DEMO_KID_ID);
    const active = this.items.filter((m: MilestoneItem) => m.status < 2);
    const out: MilestoneProgress[] = [];
    for (const m of active) {
      const current = await MilestoneDao.progressOf(m.kind, SeedData.DEMO_KID_ID);
      const pct = Math.min(100, Math.round(current / Math.max(1, m.target) * 100));
      out.push({ item: m, current: current, pct: pct } as MilestoneProgress);
    }
    this.progresses = out;
  }

  isSm(): boolean {
    return this.breakpoint === 'sm';
  }

  /** 已兑现（纪念墙） */
  confirmed(): MilestoneItem[] {
    return this.items.filter((m: MilestoneItem) => m.status === 2);
  }

  /** 路线站点（未兑现，按目标值升序即旅行顺序） */
  route(): MilestoneProgress[] {
    return this.progresses;
  }

  @Builder
  StationCell(p: MilestoneProgress, index: number, total: number) {
    Row({ space: Space.MD }) {
      // 左侧：站点圆点 + 连线
      Column() {
        Text(p.item.icon)
          .fontSize(this.isSm() ? 28 : 34)
          .opacity(p.item.status === 1 ? 1.0 : 0.9)
        // 圆点
        Circle({ width: 18, height: 18 })
          .fill(p.item.status === 1 ? $r('app.color.star_yellow') : '#D9D2C4')
          .stroke(p.item.status === 1 ? '#E8A51F' : '#C7BFAE')
          .strokeWidth(2)
        // 连线（最后一站不画）
        if (index < total - 1) {
          Column()
            .width(3)
            .height(44)
            .backgroundColor('#E8E0D4')
            .borderRadius(2)
        }
      }
      .width(52)
      .alignItems(HorizontalAlign.Center)

      // 右侧：卡片信息
      Column({ space: 4 }) {
        Row() {
          Text(p.item.title)
            .fontSize(this.isSm() ? Type.TITLE : Type.HEADLINE)
            .fontWeight(FontWeight.Bold)
            .fontColor(p.item.status === 1 ? $r('app.color.cocoa_text') : $r('app.color.mist_gray'))
            .layoutWeight(1)
          if (p.item.status === 1) {
            Text('进行中')
              .fontSize(11)
              .fontColor('#B4711D')
              .backgroundColor('#FFF3DD')
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(10)
          }
        }
        .width('100%')

        Text(`奖励：${p.item.reward}`)
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.mist_gray'))
          .alignSelf(ItemAlign.Start)

        // 进度条
        Row({ space: 8 }) {
          Progress({ value: p.pct, total: 100, type: ProgressType.Linear })
            .layoutWeight(1)
            .height(8)
            .color(p.item.status === 1 ? $r('app.color.star_yellow') : '#D9D2C4')
          Text(`${p.current}/${p.item.target}`)
            .fontSize(11)
            .fontColor($r('app.color.mist_gray'))
        }
        .width('100%')
        .margin({ top: 2 })
      }
      .layoutWeight(1)
      .padding(12)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .border({
        width: p.item.status === 1 ? 2 : 1,
        color: p.item.status === 1 ? $r('app.color.star_yellow') : '#EEE6D8'
      })
      .shadow(p.item.status === 1
        ? { radius: 10, color: '#33E8A51F', offsetY: 4 }
        : { radius: 0, color: '#00000000' })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .onClick(() => {
      if (p.item.status === 1) {
        Sound.speak(`当前目标：${p.item.title}，已完成 ${p.pct}%`);
      } else {
        Sound.speak(`下一站：${p.item.title}，完成后可以得到${p.item.reward}`);
      }
    })
  }

  @Builder
  MemoryCell(m: MilestoneItem) {
    Column({ space: 4 }) {
      Text(m.icon)
        .fontSize(this.isSm() ? 30 : 38)
      Text(m.title)
        .fontSize(Type.BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.cocoa_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(m.reward)
        .fontSize(11)
        .fontColor($r('app.color.mist_gray'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('已兑现 🎉')
        .fontSize(11)
        .fontColor('#2E7D32')
        .backgroundColor('#E8F5E9')
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .borderRadius(10)
        .margin({ top: 2 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFDF6')
    .borderRadius(16)
    .border({ width: 2, color: $r('app.color.star_yellow') })
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: Space.MD }) {
          Column({ space: 2 }) {
            Text('成长旅行')
              .fontSize(this.isSm() ? Type.HEADLINE : Type.DISPLAY)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.cocoa_text'))
              .alignSelf(ItemAlign.Start)
            Text('每完成一个目标，就到达一站！')
              .fontSize(Type.CAPTION)
              .fontColor($r('app.color.mist_gray'))
              .alignSelf(ItemAlign.Start)
          }
          .width('100%')

          SectionTitle({ text: '旅行路线', textSize: Type.BODY })
          if (this.route().length === 0) {
            Text('全部站点都到达啦，等爸爸妈妈设置新目标！')
              .fontSize(Type.BODY)
              .fontColor($r('app.color.mist_gray'))
              .padding(Space.MD)
          } else {
            ForEach(this.route(), (p: MilestoneProgress, index: number) => {
              this.StationCell(p, index, this.route().length)
            }, (p: MilestoneProgress) => `${p.item.id}`)
          }

          if (this.confirmed().length > 0) {
            SectionTitle({ text: '纪念墙', textSize: Type.BODY })
            ForEach(this.confirmed(), (m: MilestoneItem) => {
              this.MemoryCell(m)
            }, (m: MilestoneItem) => `c${m.id}`)
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
        .constraintSize({ maxWidth: 560 })
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
