import { TaskItem } from '../commons/models/Models';
import { AppButton, AppButtonVariant } from '../commons/components/AppButton';
import { CardSurface, SectionTitle } from '../commons/components/Primitives';
import { TaskDao, ProfileDao, SettingsDao } from '../commons/db/Dao';
import { SeedData } from '../commons/db/SeedData';
import { AgeTemplates } from '../commons/utils/AgeTemplate';
import { AgeUtil } from '../commons/utils/AgeUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Radius, Space, Type, MIN_TOUCH } from '../commons/theme/Theme';

/** settings 键：家长跳过首次引导的标记（与 EntryAbility 读取同一个键） */
const SKIP_SETTING_KEY: string = 'profile_setup_skipped';

/**
 * 宝宝档案（名字 + 生日）：首次引导 与 家长模式内修改 共用一页。
 *
 * 两种进入方式：
 * · 首次进入（档案不完整：没生日）→ EntryAbility 把本页作为首页加载。
 *   此时页面**没有返回按钮**（否则返回会直接退出应用），提供「先跳过」。
 * · 家长模式「宝宝档案」→ 从 ParentHome pushUrl 进来，底部有返回按钮。
 *
 * 职责：
 * · 保存名字与生日；
 * · 由生日算出年龄 → 给出该年龄档的分龄任务模板（首次设置时直接套用为默认任务）。
 */
@Entry
@Component
struct KidProfile {
  /** 顶部系统避让区高度（vp） */
  @StorageProp('safeAreaTop') safeAreaTop: number = 28;
  /** 底部系统避让区高度（vp） */
  @StorageProp('safeAreaBottom') safeAreaBottom: number = 0;

  /** 宝宝名字（输入框） */
  @State name: string = '';
  /** 生日（YYYY-MM-DD，空串 = 未选） */
  @State birthday: string = '';
  /** 载入时的年龄档（用于判断改了生日后档位是否变化） */
  @State loadedAgeBucket: number = -1;
  /** 是否是「首次设置」（进入时没有生日）：此时保存会直接套用默认模板 */
  @State firstSetup: boolean = false;
  /** 是否为家长模式进入（true → 有返回按钮；false → 首页加载，底部是「先跳过」） */
  @StorageProp('profileEditMode') editMode: boolean = false;
  /** 提交中：防重复点击 */
  @State busy: boolean = false;
  /** 结果提示文案 */
  @State hint: string = '';

  aboutToAppear(): void {
    this.load();
  }

  async load(): Promise<void> {
    const profile = await ProfileDao.get(SeedData.DEMO_KID_ID);
    if (profile !== null) {
      this.name = profile.name;
      this.birthday = profile.birthday;
    }
    // 没有生日 = 档案未完善 = 首次设置（此时才套用默认模板）
    this.firstSetup = this.birthday === '';
    this.loadedAgeBucket = this.firstSetup ? -1 : AgeUtil.templateAge(AgeUtil.ageOf(this.birthday));
  }

  /** 当前生日算出的年龄（-1 = 未选） */
  age(): number {
    return AgeUtil.ageOf(this.birthday);
  }

  /** 当前年龄对应的模板档位（未选生日时用默认档） */
  bucket(): number {
    return AgeUtil.templateAge(this.age());
  }

  /** 模板档位是否与载入时不同（改了生日导致跨档） */
  ageBucketChanged(): boolean {
    return !this.firstSetup && this.loadedAgeBucket !== this.bucket();
  }

  /** 弹出系统日期选择器：UIContext.showDatePickerDialog，回调直接给 Date（无需处理 0-based 月份） */
  pickBirthday(): void {
    const now = new Date();
    // 可选范围：18 年前 ~ 今天（生日不能选未来）
    const start = new Date(now.getFullYear() - 18, 0, 1);
    let selected = AgeUtil.parseDate(this.birthday);
    if (selected === null) {
      // 默认给 4 岁（与默认模板档一致），而不是「今天」
      selected = new Date(now.getFullYear() - 4, now.getMonth(), now.getDate());
    }
    this.getUIContext().showDatePickerDialog({
      start: start,
      end: now,
      selected: selected,
      onDateAccept: (value: Date) => {
        this.birthday = AgeUtil.formatDate(value.getFullYear(), value.getMonth() + 1, value.getDate());
      }
    });
  }

  /** 该年龄档的模板任务清单 */
  templateTasks(): TaskItem[] {
    return AgeTemplates.tasksOf(this.bucket());
  }

  /**
   * 保存档案。
   * · 首次设置 → 直接用该年龄档的模板重建任务列表（=「按生日提供默认模板」）。
   * · 家长模式改生日且跨了档位 → **不自动覆盖**家长的任务，只提示可去任务管理套用，
   *   避免把家长已经调过的任务冲掉。
   */
  async save(): Promise<void> {
    if (this.busy) {
      return;
    }
    const name = this.name.trim();
    if (name === '') {
      this.hint = '请先给宝宝起个名字';
      return;
    }
    if (this.birthday === '') {
      this.hint = '请选择宝宝的生日';
      return;
    }
    this.busy = true;
    const wasFirstSetup = this.firstSetup;
    try {
      const kidId = SeedData.DEMO_KID_ID;
      await ProfileDao.update(kidId, name, this.birthday);
      if (this.firstSetup) {
        const list = this.templateTasks();
        await TaskDao.replaceAll(kidId, list);
        this.hint = `已为 ${name} 准备好 ${list.length} 个 ${this.bucket()} 岁习惯任务`;
      } else if (this.ageBucketChanged()) {
        this.hint = `已保存。年龄变为 ${this.bucket()} 岁，可在任务管理里套用新模板`;
      } else {
        this.hint = '已保存';
      }
      this.loadedAgeBucket = this.bucket();
      this.firstSetup = false;
      // 首次设置完成 → 进入宝宝主界面（引导页是本次启动的首页，替换掉避免返回退出应用）
      if (wasFirstSetup) {
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' });
        return;
      }
    } catch (err) {
      hilog.error(0x0001, 'KidProfile', 'save failed: %{public}s', String(err));
      this.hint = '保存失败，请重试';
    }
    this.busy = false;
  }

  /** 跳过首次设置：进入宝宝主界面（档案留空，之后可在家长模式补） */
  skip(): void {
    // 记住"跳过"：下次启动不再强制弹引导页（否则每次开 App 都拦一次，家长会烦）
    SettingsDao.set(SKIP_SETTING_KEY, '1').catch((err: Object) => {
      hilog.info(0x0001, 'KidProfile', 'save skip flag failed: %{public}s', String(err));
    });
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' });
  }

  @Builder
  NameField() {
    Column({ space: Space.SM }) {
      SectionTitle({ text: '宝宝的名字', textSize: Type.BODY })
      TextInput({ placeholder: '宝宝叫什么名字呀', text: this.name })
        .layoutWeight(1)
        .constraintSize({ minWidth: 0, minHeight: MIN_TOUCH })
        .fontSize(Type.BODY)
        .backgroundColor($r('app.color.soft_blue'))
        .borderRadius(Radius.MD)
        .onChange((v: string) => {
          this.name = v;
        })
    }
    .width('100%')
  }

  @Builder
  BirthdayField() {
    Column({ space: Space.SM }) {
      SectionTitle({ text: '宝宝的生日', textSize: Type.BODY })
      Row({ space: Space.SM }) {
        Text(this.birthday === '' ? '点击选择生日' : AgeUtil.birthdayLabel(this.birthday))
          .fontSize(Type.BODY)
          .fontColor(this.birthday === '' ? $r('app.color.mist_gray') : $r('app.color.cocoa_text'))
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('📅 选择')
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.brand_orange'))
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.soft_yellow'))
          .borderRadius(Radius.PILL)
          .onClick(() => {
            this.pickBirthday();
          })
      }
      .width('100%')
      .padding(Space.MD)
      .backgroundColor(Color.White)
      .borderRadius(Radius.LG)
      .border({ width: 1, color: $r('app.color.hairline') })
    }
    .width('100%')
  }

  /** 生日 → 年龄 → 该年龄档模板的预览 */
  @Builder
  TemplatePreview() {
    Column({ space: Space.SM }) {
      SectionTitle({ text: '将为宝宝推荐', textSize: Type.BODY })
      CardSurface({ cardPadding: Space.MD }) {
        Row({ space: Space.SM }) {
          Text(this.age() >= 0 ? `${this.age()} 岁` : '—')
            .fontSize(Type.HEADLINE - 6)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand_orange'))
          Column({ space: 2 }) {
            Text(AgeTemplates.packOf(this.bucket()).stageLabel)
              .fontSize(Type.BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.cocoa_text'))
            Text(AgeTemplates.packOf(this.bucket()).principle)
              .fontSize(Type.CAPTION)
              .fontColor($r('app.color.mist_gray'))
          }
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')

        Text(this.firstSetup
          ? '保存后会按这个年龄档自动准备好一批习惯任务，家长可在「任务管理」里继续调整。'
          : '修改生日会改变推荐年龄档，任务列表可在「任务管理」里按新档位调整。')
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.mist_gray'))
          .alignSelf(ItemAlign.Start)
          .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  Body() {
    Scroll() {
      Column({ space: Space.LG }) {
        if (this.firstSetup) {
          Column({ space: Space.SM }) {
            Text('👋 欢迎来到宝宝好习惯')
              .fontSize(Type.HEADLINE)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.cocoa_text'))
            Text('先告诉我们宝宝的名字和生日，我们按年龄准备一份合适的习惯任务。')
              .fontSize(Type.BODY)
              .fontColor($r('app.color.mist_gray'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        this.NameField()
        this.BirthdayField()
        this.TemplatePreview()

        if (this.hint !== '') {
          Text(this.hint)
            .fontSize(Type.BODY)
            .fontColor(this.hint.indexOf('失败') >= 0 || this.hint.indexOf('请') >= 0
              ? $r('app.color.danger') : $r('app.color.done_green'))
            .alignSelf(ItemAlign.Start)
            .width('100%')
        }

        AppButton({
          label: this.busy ? '保存中…' : (this.firstSetup ? '开始使用' : '保存修改'),
          variant: AppButtonVariant.Primary,
          btnHeight: 54,
          isEnabled: !this.busy,
          block: true,
          onTap: () => {
            this.save();
          }
        })

        if (this.editMode) {
          AppButton({
            label: '← 返回',
            variant: AppButtonVariant.Soft,
            btnHeight: 48,
            block: true,
            onTap: () => {
              this.getUIContext().getRouter().back();
            }
          })
        } else {
          AppButton({
            label: '先跳过，稍后再设置',
            variant: AppButtonVariant.Outline,
            btnHeight: 44,
            fontSize: Type.CAPTION,
            block: true,
            onTap: () => {
              this.skip();
            }
          })
        }
      }
      .width('100%')
      .padding({ bottom: Space.XL })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  build() {
    Column() {
      Column({ space: Space.MD }) {
        Row({ space: Space.SM }) {
          Text('👶 宝宝档案')
            .fontSize(Type.HEADLINE)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.cocoa_text'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        this.Body()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      // 顶部留白避让状态栏，底部留白避让导航条/手势条
      .padding({
        left: Space.XL - 4,
        right: Space.XL - 4,
        top: this.safeAreaTop + 8,
        bottom: this.safeAreaBottom + 16
      })
      .backgroundColor($r('app.color.cream_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
  }
}
