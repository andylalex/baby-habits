import { MilestoneDao } from '../commons/db/Dao';
import { SeedData } from '../commons/db/SeedData';
import { MilestoneItem } from '../commons/models/Models';
import { ParentScaffold } from '../commons/components/ParentScaffold';
import { SectionTitle } from '../commons/components/Primitives';
import { AppButton, AppButtonVariant } from '../commons/components/AppButton';
import { Space, Type } from '../commons/theme/Theme';

const KIND_LABELS: string[] = ['连续打卡天数', '累计获得星星', '累计完成打卡'];
const KIND_ICONS: string[] = ['🔥', '⭐', '✅'];
const KIND_VALUES: string[] = ['streak', 'stars', 'checkins'];

/**
 * 家长端 · 里程碑管理：新增目标 + 进度查看 + 达成兑现。
 * 待兑现条目点「已兑现」确认 → 进宝宝端纪念墙。
 */
@Entry
@Component
struct ParentMilestones {
  @State items: MilestoneItem[] = [];
  @State progresses: Map<number, number> = new Map();
  /** 新增表单 */
  @State formTitle: string = '';
  @State formKind: number = 0; // 0 streak / 1 stars / 2 checkins
  @State formTarget: string = '';
  @State formReward: string = '';
  @State formOpen: boolean = false;
  @State hint: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  async reload(): Promise<void> {
    const kidId = SeedData.DEMO_KID_ID;
    this.items = await MilestoneDao.list(kidId);
    const map = new Map<number, number>();
    for (const m of this.items) {
      map.set(m.id, await MilestoneDao.progressOf(m.kind, kidId));
    }
    this.progresses = map;
  }

  statusText(m: MilestoneItem): string {
    if (m.status === 2) {
      return '已兑现';
    }
    return m.status === 1 ? '待兑现' : '进行中';
  }

  async submit(): Promise<void> {
    const title = this.formTitle.trim();
    const target = Number(this.formTarget);
    const reward = this.formReward.trim();
    if (title === '') {
      this.hint = '请填写里程碑名称';
      return;
    }
    if (!Number.isInteger(target) || target <= 0) {
      this.hint = '目标数量要是正整数';
      return;
    }
    if (reward === '') {
      this.hint = '请填写达成奖励（给宝宝看的）';
      return;
    }
    await MilestoneDao.insert(SeedData.DEMO_KID_ID, new MilestoneItem(
      0, title, KIND_ICONS[this.formKind], KIND_VALUES[this.formKind], target, reward, 0, '', ''
    ));
    this.formTitle = '';
    this.formTarget = '';
    this.formReward = '';
    this.formOpen = false;
    this.hint = '';
    await this.reload();
  }

  async confirmOne(m: MilestoneItem): Promise<void> {
    await MilestoneDao.confirm(SeedData.DEMO_KID_ID, m.id);
    await this.reload();
  }

  @Builder
  MilestoneRow(m: MilestoneItem) {
    Column({ space: 6 }) {
      Row({ space: Space.SM }) {
        Text(`${m.icon} ${m.title}`)
          .fontSize(Type.TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.cocoa_text'))
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.statusText(m))
          .fontSize(Type.CAPTION)
          .fontColor(m.status === 1 ? '#B4711D' : (m.status === 2 ? '#2E7D32' : '#8A8A8A'))
          .backgroundColor(m.status === 1 ? '#FFF3DD' : (m.status === 2 ? '#E8F5E9' : '#F0F0F0'))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(10)
      }
      .width('100%')

      Text(`奖励：${m.reward}`)
        .fontSize(Type.CAPTION)
        .fontColor($r('app.color.mist_gray'))
        .alignSelf(ItemAlign.Start)

      Row({ space: 8 }) {
        Progress({ value: Math.min(this.progresses.get(m.id) ?? 0, m.target), total: m.target, type: ProgressType.Linear })
          .layoutWeight(1)
          .height(8)
          .color(m.status >= 1 ? $r('app.color.star_yellow') : '#D9D2C4')
        Text(`${this.progresses.get(m.id) ?? 0}/${m.target}`)
          .fontSize(11)
          .fontColor($r('app.color.mist_gray'))
      }
      .width('100%')

      if (m.status === 1) {
        AppButton({
          label: '已兑现奖励（进入宝宝纪念墙）',
          variant: AppButtonVariant.Primary,
          btnHeight: 44,
          fontSize: Type.BODY,
          block: true,
          onTap: () => {
            this.confirmOne(m);
          }
        })
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding(Space.MD)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .border({
      width: m.status === 1 ? 2 : 1,
      color: m.status === 1 ? $r('app.color.star_yellow') : '#EEE6D8'
    })
  }

  @Builder
  AddForm() {
    Column({ space: Space.SM }) {
      SectionTitle({ text: '新增里程碑', textSize: Type.BODY })
      TextInput({ placeholder: '名称，如：坚持刷牙 7 天', text: this.formTitle })
        .height(48)
        .fontSize(Type.BODY)
        .backgroundColor(Color.White)
        .borderRadius(12)
        .onChange((v: string) => {
          this.formTitle = v;
        })
      Row({ space: Space.SM }) {
        ForEach(KIND_LABELS, (label: string, i: number) => {
          Text(`${KIND_ICONS[i]} ${label}`)
            .fontSize(Type.CAPTION)
            .fontColor(this.formKind === i ? Color.White : $r('app.color.cocoa_text'))
            .backgroundColor(this.formKind === i ? $r('app.color.brand_orange') : '#F0EBE2')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .borderRadius(16)
            .onClick(() => {
              this.formKind = i;
            })
        }, (label: string) => label)
      }
      .width('100%')

      TextInput({ placeholder: '目标数量（正整数），如 7', text: this.formTarget })
        .type(InputType.Number)
        .height(48)
        .fontSize(Type.BODY)
        .backgroundColor(Color.White)
        .borderRadius(12)
        .onChange((v: string) => {
          this.formTarget = v;
        })
      TextInput({ placeholder: '达成奖励，如：周末去公园', text: this.formReward })
        .height(48)
        .fontSize(Type.BODY)
        .backgroundColor(Color.White)
        .borderRadius(12)
        .onChange((v: string) => {
          this.formReward = v;
        })

      if (this.hint !== '') {
        Text(this.hint)
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.danger'))
          .alignSelf(ItemAlign.Start)
      }

      AppButton({
        label: '保存里程碑',
        variant: AppButtonVariant.Primary,
        btnHeight: 52,
        fontSize: Type.TITLE,
        block: true,
        onTap: () => {
          this.submit();
        }
      })
    }
    .width('100%')
    .padding(Space.MD)
    .backgroundColor('#FBF7EF')
    .borderRadius(16)
  }

  @Builder
  Body() {
    Column({ space: Space.MD }) {
      if (this.formOpen) {
        this.AddForm();
      } else {
        AppButton({
          label: '＋ 新增里程碑',
          variant: AppButtonVariant.Soft,
          btnHeight: 48,
          fontSize: Type.BODY,
          block: true,
          onTap: () => {
            this.formOpen = true;
          }
        })
      }

      SectionTitle({ text: '全部站点', textSize: Type.BODY })
      if (this.items.length === 0) {
        Text('还没有里程碑，点上方按钮添加一个吧')
          .fontSize(Type.BODY)
          .fontColor($r('app.color.mist_gray'))
      } else {
        ForEach(this.items, (m: MilestoneItem) => {
          this.MilestoneRow(m)
        }, (m: MilestoneItem) => `${m.id}`)
      }
    }
    .width('100%')
  }

  build() {
    Column() {
      ParentScaffold({ title: '里程碑管理' }) {
        this.Body()
      }
    }
    .width('100%')
    .height('100%')
  }
}
