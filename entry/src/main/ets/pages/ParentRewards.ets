import { RewardItem } from '../commons/models/Models';
import { HabitIcon } from '../commons/components/HabitIcon';
import { AppButton, AppButtonVariant } from '../commons/components/AppButton';
import { HabitRow } from '../commons/components/HabitRow';
import { CardSurface, SectionTitle, EmptyHint } from '../commons/components/Primitives';
import { ParentScaffold } from '../commons/components/ParentScaffold';
import { RewardDao } from '../commons/db/Dao';
import { SeedData } from '../commons/db/SeedData';
import { Radius, Space, Type, MIN_TOUCH } from '../commons/theme/Theme';

/** 心愿可选图标：内置插画 + 兜底 emoji */
const REWARD_ICONS: string[] = ['🎁', '✨', '📺', '🛝', '🧱', '🍦', '🚗', '🎠'];

/** 三档定价的档位默认值 */
const TIER_DEFAULT_COST: number[] = [5, 15, 40];

/**
 * 家长端 · 心愿商店：三档定价（切换档位自动带出建议星数）+ 上架/下架。
 */
@Entry
@Component
struct ParentRewards {
  @State rewards: RewardItem[] = [];
  @State newTitle: string = '';
  @State newIcon: string = REWARD_ICONS[0];
  @State newCost: number = 5;
  @State newTier: number = 1;

  aboutToAppear(): void {
    this.reload();
  }

  async reload(): Promise<void> {
    this.rewards = await RewardDao.listActive(SeedData.DEMO_KID_ID);
  }

  tierLabel(tier: number): string {
    return tier === 1 ? '小心愿' : (tier === 2 ? '中愿望' : '大愿望');
  }

  tierRange(tier: number): string {
    return tier === 1 ? '5-10⭐' : (tier === 2 ? '15-30⭐' : '40⭐+');
  }

  /** 档位与定价联动：切档位时带出该档建议星数 */
  pickTier(tier: number): void {
    this.newTier = tier;
    this.newCost = TIER_DEFAULT_COST[tier - 1];
  }

  async addReward(): Promise<void> {
    await RewardDao.insert(SeedData.DEMO_KID_ID,
      new RewardItem(0, this.newTitle.trim(), this.newIcon, this.newCost, this.newTier));
    this.newTitle = '';
    this.newCost = TIER_DEFAULT_COST[this.newTier - 1];
    await this.reload();
  }

  /** 图标选择器：横向滑动挑选 */
  @Builder
  IconPicker() {
    Scroll() {
      Row({ space: Space.SM }) {
        ForEach(REWARD_ICONS, (icon: string) => {
          Stack({ alignContent: Alignment.Center }) {
            Text(icon)
              .fontSize(26)
          }
          .width(48)
          .height(48)
          .borderRadius(Radius.MD)
          .backgroundColor(this.newIcon === icon ? $r('app.color.soft_yellow') : Color.White)
          .border({
            width: 2,
            color: this.newIcon === icon ? $r('app.color.brand_orange') : $r('app.color.hairline')
          })
          .onClick(() => {
            this.newIcon = icon;
          })
        }, (icon: string) => icon)
      }
      .padding(Space.XS)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  RewardList() {
    if (this.rewards.length === 0) {
      EmptyHint({ text: '还没有上架心愿，添加一个吧' })
    } else {
      Column({ space: Space.SM }) {
        ForEach(this.rewards, (r: RewardItem) => {
          HabitRow({
            icon: r.icon,
            title: r.title,
            meta: `${this.tierLabel(r.tier)} · ⭐${r.starCost}`
          }) {
            AppButton({
              label: '下架',
              variant: AppButtonVariant.Danger,
              btnHeight: 36,
              fontSize: Type.CAPTION,
              onTap: () => {
                RewardDao.deactivate(r.id).then(() => {
                  this.reload();
                });
              }
            })
          }
        }, (r: RewardItem) => `${r.id}`)
      }
      .width('100%')
    }
  }

  /** 档位选择：两行文字（名称 + 星数区间），窄屏三等分也不会挤压变形 */
  @Builder
  TierChip(tier: number) {
    Column({ space: 2 }) {
      Text(this.tierLabel(tier))
        .fontSize(Type.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.newTier === tier ? Color.White : $r('app.color.cocoa_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.tierRange(tier))
        .fontSize(Type.MICRO)
        .fontColor(this.newTier === tier ? '#FFE8D6' : $r('app.color.mist_gray'))
        .maxLines(1)
    }
    .layoutWeight(1)
    .constraintSize({ minWidth: 0 })
    .height(56)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 4, right: 4 })
    .backgroundColor(this.newTier === tier ? $r('app.color.brand_orange') : Color.White)
    .borderRadius(Radius.MD)
    .border({
      width: 2,
      color: this.newTier === tier ? $r('app.color.brand_orange') : $r('app.color.hairline')
    })
    .onClick(() => {
      this.pickTier(tier);
    })
  }

  @Builder
  Body() {
    Scroll() {
      Column({ space: Space.MD }) {
        SectionTitle({ text: '上架新心愿' })
        CardSurface({ cardPadding: Space.MD }) {
          Row({ space: Space.SM }) {
            HabitIcon({ icon: this.newIcon, iconSize: 40, radius: Radius.SM })
            TextInput({ placeholder: '奖励名称', text: this.newTitle })
              .layoutWeight(1)
              .constraintSize({ minWidth: 0, minHeight: MIN_TOUCH })
              .fontSize(Type.BODY)
              .backgroundColor($r('app.color.soft_blue'))
              .borderRadius(Radius.MD)
              .onChange((v: string) => {
                this.newTitle = v;
              })
          }
          .width('100%')

          Row({ space: Space.SM }) {
            ForEach([1, 2, 3], (tier: number) => {
              this.TierChip(tier);
            }, (tier: number) => `${tier}`)
          }
          .width('100%')

          Row({ space: Space.SM }) {
            AppButton({
              label: `⭐${this.newCost}`,
              variant: AppButtonVariant.Soft,
              btnHeight: MIN_TOUCH,
              onTap: () => {
                this.newCost = this.newCost >= 120 ? 5 : this.newCost + 5;
              }
            })
            AppButton({
              label: '上架心愿',
              variant: AppButtonVariant.Primary,
              btnHeight: MIN_TOUCH,
              block: true,
              isEnabled: this.newTitle.trim().length > 0,
              onTap: () => {
                this.addReward();
              }
            })
              .layoutWeight(1)
              .constraintSize({ minWidth: 0 })
          }
          .width('100%')

          this.IconPicker()
        }

        SectionTitle({ text: `已上架（${this.rewards.length}）` })
        this.RewardList()
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
      ParentScaffold({ title: '心愿商店' }) {
        this.Body()
      }
    }
    .width('100%')
    .height('100%')
  }
}
