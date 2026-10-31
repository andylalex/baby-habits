import { TaskItem } from '../commons/models/Models';
import { AppButton, AppButtonVariant } from '../commons/components/AppButton';
import { HabitRow } from '../commons/components/HabitRow';
import { CardSurface, SectionTitle } from '../commons/components/Primitives';
import { ParentScaffold } from '../commons/components/ParentScaffold';
import { TaskDao, StatsDao, ProfileDao } from '../commons/db/Dao';
import { SeedData } from '../commons/db/SeedData';
import { AgeEngine, AgeAdvice } from '../commons/utils/AgeEngine';
import { AgeTemplates } from '../commons/utils/AgeTemplate';
import { AgeUtil } from '../commons/utils/AgeUtil';
import { Radius, Space, Type, MIN_TOUCH } from '../commons/theme/Theme';

/**
 * 家长端 · 智能建议（本地规则版）：分龄任务推荐 + 近 7 天完成率评估。
 * 后续替换为 HarmonyOS 7 端侧大模型生成（数据不出手机）。
 */
@Entry
@Component
struct ParentAdvice {
  @State age: number = 4;
  @State activeTitles: Set<string> = new Set();
  @State rate: number = -1;
  /** 年龄来源：来自生日（true）还是手动调整（false） */
  @State ageFromBirthday: boolean = false;

  aboutToAppear(): void {
    this.reload();
  }

  async reload(): Promise<void> {
    const tasks = await TaskDao.listActive(SeedData.DEMO_KID_ID);
    const titles: Set<string> = new Set();
    for (const t of tasks) {
      titles.add(t.title);
    }
    this.activeTitles = titles;
    this.rate = await StatsDao.weeklyRate(SeedData.DEMO_KID_ID);
    // 年龄默认取生日算出的值（家长在「宝宝档案」填生日）；没填生日才用默认档
    const profile = await ProfileDao.get(SeedData.DEMO_KID_ID);
    if (profile !== null && profile.age > 0) {
      this.age = AgeUtil.templateAge(profile.age);
      this.ageFromBirthday = true;
    }
  }

  advice(): AgeAdvice {
    return AgeEngine.adviceFor(this.age);
  }

  async addTask(t: TaskItem): Promise<void> {
    await TaskDao.insert(SeedData.DEMO_KID_ID, t, 99);
    await this.reload();
  }

  goodWeek(): boolean {
    return this.rate >= 0.6;
  }

  @Builder
  RateCard() {
    CardSurface({ cardPadding: Space.LG, radius: Radius.XL }) {
      Row({ space: Space.SM }) {
        Text('本周完成率')
          .fontSize(Type.SUBTITLE)
          .fontColor($r('app.color.cocoa_text'))
          .layoutWeight(1)
        Text(this.rate < 0 ? '—' : AgeEngine.rateLabel(this.rate))
          .fontSize(Type.TITLE + 4)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.goodWeek() ? $r('app.color.done_green') : $r('app.color.brand_orange'))
      }
      .width('100%')
      Progress({ value: this.rate < 0 ? 0 : this.rate * 100, total: 100, type: ProgressType.Linear })
        .width('100%')
        .color(this.goodWeek() ? $r('app.color.done_green') : $r('app.color.star_yellow'))
      Text(AgeEngine.evaluate(this.rate))
        .fontSize(Type.BODY - 1)
        .fontColor($r('app.color.cocoa_text'))
        .width('100%')
    }
  }

  @Builder
  AgeStepper() {
    CardSurface({ cardPadding: Space.MD }) {
      Row({ space: Space.SM }) {
        Text('宝宝年龄')
          .fontSize(Type.SUBTITLE)
          .fontColor($r('app.color.cocoa_text'))
          .layoutWeight(1)
        AppButton({
          label: '−',
          variant: AppButtonVariant.Soft,
          btnHeight: MIN_TOUCH,
          fontSize: Type.TITLE,
          onTap: () => {
            if (this.age > AgeTemplates.AGES[0]) {
              this.age--;
              this.ageFromBirthday = false;
            }
          }
        })
        Text(`${this.age} 岁`)
          .fontSize(Type.TITLE + 2)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.cocoa_text'))
          .width(64)
          .textAlign(TextAlign.Center)
        AppButton({
          label: '＋',
          variant: AppButtonVariant.Soft,
          btnHeight: MIN_TOUCH,
          fontSize: Type.TITLE,
          onTap: () => {
            if (this.age < AgeTemplates.AGES[AgeTemplates.AGES.length - 1]) {
              this.age++;
              this.ageFromBirthday = false;
            }
          }
        })
      }
      .width('100%')

      // 年龄来源说明：自动跟随生日 or 手动调整，避免家长困惑「为什么换了档位」
      Text(this.ageFromBirthday ? '年龄按宝宝档案里的生日自动计算' : '已手动调整年龄（改生日会重新自动匹配）')
        .fontSize(Type.MICRO + 1)
        .fontColor($r('app.color.mist_gray'))
        .alignSelf(ItemAlign.Start)

      Text(this.advice().stageLabel)
        .fontSize(Type.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.cocoa_text'))
        .alignSelf(ItemAlign.Start)
      Text(this.advice().principle)
        .fontSize(Type.CAPTION + 1)
        .fontColor($r('app.color.mist_gray'))
        .alignSelf(ItemAlign.Start)
    }
  }

  @Builder
  AdviceList() {
    Column({ space: Space.SM }) {
      ForEach(this.advice().tasks, (t: TaskItem) => {
        HabitRow({ icon: t.icon, title: t.title, meta: `⭐${t.starValue}` }) {
          if (this.activeTitles.has(t.title)) {
            Text('已添加 ✓')
              .fontSize(Type.CAPTION)
              .fontColor($r('app.color.done_green'))
          } else {
            AppButton({
              label: '添加',
              variant: AppButtonVariant.Primary,
              btnHeight: 36,
              fontSize: Type.CAPTION,
              onTap: () => {
                this.addTask(t);
              }
            })
          }
        }
      }, (t: TaskItem) => t.title)
    }
    .width('100%')
  }

  @Builder
  Body() {
    Scroll() {
      Column({ space: Space.MD }) {
        this.RateCard()
        this.AgeStepper()
        SectionTitle({ text: '推荐任务' })
        this.AdviceList()
      }
      .width('100%')
      .padding({ bottom: Space.MD })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  build() {
    Column() {
      // content 尾随闭包传入，保持 this 指向本页（具名传 this.Body 会丢 this）
      ParentScaffold({ title: '🧠 智能建议' }) {
        this.Body()
      }
    }
    .width('100%')
    .height('100%')
  }
}
