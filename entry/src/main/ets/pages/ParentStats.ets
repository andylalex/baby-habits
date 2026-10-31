import { CheckinDao, StatsDao } from '../commons/db/Dao';
import { SeedData } from '../commons/db/SeedData';
import { ParentScaffold } from '../commons/components/ParentScaffold';
import { CardSurface, SectionTitle } from '../commons/components/Primitives';
import { Space, Type, Radius } from '../commons/theme/Theme';

/** 热力图一天的数据 */
interface HeatCell {
  date: string;
  count: number;
}

/**
 * 家长端 · 数据看板：打卡日历热力图（近 12 周）+ 连续记录 + 完成率。
 * 全部本地统计，无服务器。
 */
@Entry
@Component
struct ParentStats {
  @State streak: number = 0;
  @State longest: number = 0;
  @State weeklyRate: number = -1;
  @State totalDone: number = 0;
  @State weeks: HeatCell[][] = [];

  aboutToAppear(): void {
    this.reload();
  }

  dayStr(d: Date): string {
    const m = `${d.getMonth() + 1}`.padStart(2, '0');
    const day = `${d.getDate()}`.padStart(2, '0');
    return `${d.getFullYear()}-${m}-${day}`;
  }

  async reload(): Promise<void> {
    const kidId = SeedData.DEMO_KID_ID;
    const today = new Date();
    this.streak = await CheckinDao.currentStreak(kidId, this.dayStr(today));
    this.longest = await CheckinDao.longestStreak(kidId);
    this.weeklyRate = await StatsDao.weeklyRate(kidId);

    // 近 12 周（84 天），从今天往前对齐到周日
    const start = new Date(today.getTime() - 83 * 86400000);
    start.setDate(start.getDate() - start.getDay());
    const counts = await CheckinDao.dailyCounts(kidId, this.dayStr(start));
    let total = 0;
    const cells: HeatCell[] = [];
    for (let i = 0; i < 84; i++) {
      const d = new Date(start.getTime() + i * 86400000);
      const key = this.dayStr(d);
      const got = counts.get(key);
      const cnt = got === undefined ? 0 : got;
      total += cnt;
      cells.push({ date: key, count: cnt } as HeatCell);
    }
    this.totalDone = total;
    const wk: HeatCell[][] = [];
    for (let i = 0; i < cells.length; i += 7) {
      const slice: HeatCell[] = [];
      for (let j = i; j < Math.min(i + 7, cells.length); j++) {
        slice.push(cells[j]);
      }
      wk.push(slice);
    }
    this.weeks = wk;
  }

  /** 热力等级 0-4：0 无，1 轻松，2 正常，3 充实，4 超棒 */
  levelOf(cnt: number): number {
    if (cnt <= 0) {
      return 0;
    }
    if (cnt === 1) {
      return 1;
    }
    if (cnt === 2) {
      return 2;
    }
    if (cnt <= 4) {
      return 3;
    }
    return 4;
  }

  colorOf(level: number): string {
    switch (level) {
      case 1:
        return '#CDEBD3';
      case 2:
        return '#8FD3A0';
      case 3:
        return '#4CAF68';
      case 4:
        return '#2E8B4A';
      default:
        return '#EDE7DC';
    }
  }

  @Builder
  StatCard(label: string, value: string, tint: ResourceColor) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(Type.HEADLINE)
        .fontWeight(FontWeight.Bold)
        .fontColor(tint)
      Text(label)
        .fontSize(Type.CAPTION)
        .fontColor($r('app.color.mist_gray'))
    }
    .width('100%')
    .padding(Space.MD)
    .backgroundColor(Color.White)
    .borderRadius(Radius.LG)
  }

  @Builder
  Body() {
    Column({ space: Space.SM }) {
      SectionTitle({ text: '打卡记录', textSize: Type.BODY })
      CardSurface({ cardPadding: Space.MD }) {
        Row({ space: Space.SM }) {
          Column() {
            this.StatCard('当前连续', `${this.streak} 天`, '#E8641F')
          }
          .layoutWeight(1)
          Column() {
            this.StatCard('最长连续', `${this.longest} 天`, $r('app.color.cocoa_text'))
          }
          .layoutWeight(1)
        }
        .width('100%')
        Row({ space: Space.SM }) {
          Column() {
            this.StatCard('累计打卡', `${this.totalDone} 次`, $r('app.color.cocoa_text'))
          }
          .layoutWeight(1)
          Column() {
            this.StatCard('近 7 天完成率', this.weeklyRate < 0 ? '—' : `${Math.round(this.weeklyRate * 100)}%`, '#4CAF68')
          }
          .layoutWeight(1)
        }
        .width('100%')
      }

      SectionTitle({ text: '近 12 周热力图', textSize: Type.BODY })
      CardSurface({ cardPadding: Space.MD }) {
        Column({ space: 8 }) {
          // 12 列（周）× 7 行（星期）：Row 主动分行布局，无测量问题
          Row({ space: 4 }) {
            ForEach(this.weeks, (week: HeatCell[]) => {
              Column({ space: 4 }) {
                ForEach(week, (cell: HeatCell) => {
                  Column()
                    .width('100%')
                    .aspectRatio(1)
                    .backgroundColor(this.colorOf(this.levelOf(cell.count)))
                    .borderRadius(3)
                    .opacity(cell.date > this.todayStr() ? 0.3 : 1.0)
                }, (cell: HeatCell) => cell.date)
              }
              .layoutWeight(1)
              .constraintSize({ minWidth: 0 })
            }, (week: HeatCell[]) => week[0].date)
          }
          .width('100%')

          Row({ space: 6 }) {
            Text('少')
              .fontSize(11)
              .fontColor($r('app.color.mist_gray'))
            ForEach([0, 1, 2, 3, 4], (lv: number) => {
              Column()
                .width(12)
                .height(12)
                .backgroundColor(this.colorOf(lv))
                .borderRadius(3)
            }, (lv: number) => `${lv}`)
            Text('多')
              .fontSize(11)
              .fontColor($r('app.color.mist_gray'))
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  todayStr(): string {
    return this.dayStr(new Date());
  }

  build() {
    Column() {
      ParentScaffold({ title: '📊 数据看板' }) {
        this.Body()
      }
    }
    .width('100%')
    .height('100%')
  }
}
