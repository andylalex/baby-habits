import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { PinLock } from '../commons/utils/PinLock';
import { FingerprintAuth } from '../commons/utils/FingerprintAuth';
import { Reminder } from '../commons/utils/Reminder';
import { AppButton, AppButtonVariant } from '../commons/components/AppButton';
import { ParentScaffold } from '../commons/components/ParentScaffold';
import { CardSurface, SectionTitle } from '../commons/components/Primitives';
import { Radius, Space, Type, Elevation } from '../commons/theme/Theme';

/**
 * 家长端首页（M2）：PIN 家长锁门 + 功能导航。
 * 首次进入需设置 4 位 PIN，之后每次进入需验证（技术方案 §5.1：每次验证，不记住会话）。
 */
@Entry
@Component
struct ParentHome {
  @State locked: boolean = true;
  @State needSetPin: boolean = false;
  @State pinInput: string = '';
  @State pinConfirm: string = '';
  @State errorHint: string = '';
  /** 指纹解锁相关状态 */
  @State fpAvailable: boolean = false;
  /** 指纹不可用原因（未录入 / 设备不支持等），可直接展示 */
  @State fpReason: string = '';
  @State fpBusy: boolean = false;
  /** 是否切换到密码（PIN）解锁备用 */
  @State usePin: boolean = false;
  /** 提交中：防重复点击重复写入 */
  @State busy: boolean = false;
  /** 渲染异常诊断：全局错误观察器写入，页面顶部红字显示 */
  @StorageProp('lastCrash') lastCrash: string = '';
  /** 早晚打卡提醒设置 */
  @State reminderOn: boolean = false;
  @State morningTime: string = '07:30';
  @State eveningTime: string = '20:30';
  @State reminderBusy: boolean = false;

  async aboutToAppear(): Promise<void> {
    this.locked = true;
    this.pinInput = '';
    this.pinConfirm = '';
    this.errorHint = '';
    this.usePin = false;
    this.fpBusy = false;
    this.loadReminder();
    try {
      this.needSetPin = !(await PinLock.hasPin());
    } catch (err) {
      this.needSetPin = true; // 读不到存储时按首次设置处理，不阻断进入
    }
    // 指纹能力探测：ACCESS_BIOMETRIC 是 system_grant 权限，声明即授权，无需运行时申请
    const cap = FingerprintAuth.check();
    this.fpAvailable = cap.available;
    this.fpReason = cap.reason;
    if (!this.fpAvailable) {
      // 无指纹能力时直接走密码解锁
      this.usePin = true;
      return;
    }
    // 有指纹能力：进入即自动发起指纹验证，不需要用户再点一下
    // 延迟一拍，等界面渲染出来再弹系统指纹框，避免首帧未就绪导致失败
    setTimeout(() => {
      this.startFingerprint();
    }, 220);
  }

  /** 发起指纹解锁 */
  startFingerprint(): void {
    if (this.fpBusy) {
      return;
    }
    this.fpBusy = true;
    this.errorHint = '';
    FingerprintAuth.auth(
      () => {
        this.fpBusy = false;
        this.locked = false;
      },
      (msg: string) => {
        this.fpBusy = false;
        this.errorHint = msg;
      }
    );
  }

  /** 读取提醒设置（失败给默认值，不阻断页面） */
  async loadReminder(): Promise<void> {
    try {
      this.reminderOn = await Reminder.isOn();
      this.morningTime = await Reminder.morningTime();
      this.eveningTime = await Reminder.eveningTime();
    } catch (err) {
      // 保持默认
    }
  }

  ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 开关提醒 */
  async toggleReminder(on: boolean): Promise<void> {
    if (this.reminderBusy) {
      return;
    }
    this.reminderBusy = true;
    try {
      if (on) {
        await Reminder.enable(this.ctx());
      } else {
        await Reminder.disable();
      }
      this.reminderOn = on;
    } catch (err) {
      this.errorHint = '提醒设置失败，请检查系统通知权限';
    }
    this.reminderBusy = false;
  }

  /** 改时间：弹系统时间选择器 */
  pickTime(which: 'morning' | 'evening'): void {
    const cur = Reminder.parseTime(which === 'morning' ? this.morningTime : this.eveningTime);
    TimePickerDialog.show({
      selected: new Date(2026, 0, 1, cur[0], cur[1]),
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        const hhmm = `${value.hour.toString().padStart(2, '0')}:${value.minute.toString().padStart(2, '0')}`;
        if (which === 'morning') {
          this.morningTime = hhmm;
        } else {
          this.eveningTime = hhmm;
        }
        Reminder.setTime(this.ctx(), which, hhmm).catch(() => {
          this.errorHint = '保存时间失败';
        });
      }
    });
  }

  async submitPin(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.pinInput.length !== 4) {
      this.errorHint = '请输入 4 位数字';
      return;
    }
    if (this.needSetPin) {
      if (this.pinConfirm.length !== 4) {
        this.errorHint = '请再输入一次确认';
        return;
      }
      if (this.pinInput !== this.pinConfirm) {
        this.errorHint = '两次输入不一致';
        this.pinConfirm = '';
        return;
      }
      this.busy = true;
      try {
        await PinLock.setPin(this.pinInput);
        this.locked = false;
      } catch (err) {
        this.errorHint = '保存失败，再试一次';
      }
      this.busy = false;
      return;
    }
    this.busy = true;
    try {
      const ok = await PinLock.verify(this.pinInput);
      if (ok) {
        this.locked = false;
      } else {
        this.errorHint = '密码不对，再试一次';
        this.pinInput = '';
      }
    } catch (err) {
      this.errorHint = '验证失败，再试一次';
    }
    this.busy = false;
  }

  @Builder
  PinField(placeholder: string, value: string, onChange: (v: string) => void) {
    TextInput({ placeholder: placeholder, text: value })
      .type(InputType.NUMBER_PASSWORD)
      .maxLength(4)
      .width('72%')
      .height(56)
      .fontSize(Type.TITLE + 2)
      .textAlign(TextAlign.Center)
      .backgroundColor(Color.White)
      .borderRadius(Radius.MD)
      .onChange((v: string) => {
        onChange(v);
      })
  }

  /** 指纹解锁界面：默认进入家长模式的方式（无指纹能力时自动回退密码） */
  @Builder
  FingerprintPad() {
    Column({ space: Space.LG }) {
      Text('🔒 家长模式')
        .fontSize(Type.HEADLINE - 4)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.cocoa_text'))
      Text('正在验证指纹，防止宝宝误操作管理功能')
        .fontSize(Type.CAPTION + 1)
        .fontColor($r('app.color.mist_gray'))

      Button() {
        Column({ space: 10 }) {
          Text('👆')
            .fontSize(60)
            .fontColor($r('app.color.cocoa_text'))
          Text(this.fpBusy ? '验证中…' : '再试一次')
            .fontSize(Type.BODY)
            .fontColor($r('app.color.cocoa_text'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width(180)
      .height(180)
      .borderRadius(90)
      .backgroundColor($r('app.color.soft_yellow'))
      .stateEffect(true)
      .onClick(() => {
        this.startFingerprint();
      })

      if (this.errorHint.length > 0) {
        Text(this.errorHint)
          .fontSize(Type.BODY)
          .fontColor($r('app.color.danger'))
      }

      Text('使用密码解锁')
        .fontSize(Type.CAPTION)
        .fontColor($r('app.color.brand_orange'))
        .padding({ top: 4, bottom: 4 })
        .onClick(() => {
          this.usePin = true;
          this.errorHint = '';
        })

      AppButton({
        label: '← 返回',
        variant: AppButtonVariant.Soft,
        btnHeight: 48,
        onTap: () => {
          router.back();
        }
      })
        .width('50%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: Space.XL, right: Space.XL })
    .backgroundColor($r('app.color.cream_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  PinPad() {
    Column({ space: Space.LG }) {
      Text(this.needSetPin ? '设置家长密码' : '请输入家长密码')
        .fontSize(Type.HEADLINE - 4)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.cocoa_text'))
      Text(this.needSetPin ? '防止宝宝误操作管理功能' : ' ')
        .fontSize(Type.CAPTION + 1)
        .fontColor($r('app.color.mist_gray'))

      this.PinField('4 位数字密码', this.pinInput, (v: string) => {
        this.pinInput = v;
        this.errorHint = '';
      })

      if (this.needSetPin) {
        this.PinField('再输入一次', this.pinConfirm, (v: string) => {
          this.pinConfirm = v;
          this.errorHint = '';
        })
      }

      if (this.errorHint.length > 0) {
        Text(this.errorHint)
          .fontSize(Type.BODY)
          .fontColor($r('app.color.danger'))
      }

      // 指纹不可用原因（如"还没有录入指纹"），提示用户如何启用指纹
      if (!this.fpAvailable && this.fpReason.length > 0) {
        Text(this.fpReason)
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.mist_gray'))
      }

      AppButton({
        label: this.busy ? '处理中…' : '确定',
        variant: AppButtonVariant.Primary,
        btnHeight: 56,
        fontSize: Type.TITLE,
        isEnabled: !this.busy,
        onTap: () => {
          this.submitPin();
        }
      })
        .width('72%')

      AppButton({
        label: '← 返回',
        variant: AppButtonVariant.Soft,
        btnHeight: 48,
        onTap: () => {
          router.back();
        }
      })
        .width('50%')

      if (this.fpAvailable) {
        Text('← 返回指纹解锁')
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.brand_orange'))
          .padding({ top: 4, bottom: 4 })
          .onClick(() => {
            this.usePin = false;
            this.errorHint = '';
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: Space.XL, right: Space.XL })
    .backgroundColor($r('app.color.cream_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  NavBtn(label: string, desc: string, url: string, enabled: boolean) {
    Button() {
      // 窄屏两行排布：标题行 + 说明行，避免横向挤压导致文字被截断
      Column({ space: 2 }) {
        Row({ space: Space.SM }) {
          Text(label)
            .fontSize(Type.TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.cocoa_text'))
            .layoutWeight(1)
            .constraintSize({ minWidth: 0 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('›')
            .fontSize(Type.TITLE + 2)
            .fontColor($r('app.color.mist_gray'))
        }
        .width('100%')
        Text(desc)
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.mist_gray'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .alignSelf(ItemAlign.Start)
          .width('100%')
      }
      .width('100%')
      .padding(Space.LG)
    }
    .width('100%')
    .backgroundColor(Color.White)
    .borderRadius(Radius.XL)
    .shadow(Elevation.CARD)
    .enabled(enabled)
    .opacity(enabled ? 1.0 : 0.55)
    .onClick(() => {
      // 从家长模式进「宝宝档案」→ 页面底部给「返回」按钮（而非首页加载时的「先跳过」）
      if (url === 'pages/KidProfile') {
        AppStorage.setOrCreate<boolean>('profileEditMode', true);
      }
      router.pushUrl({ url: url });
    })
  }

  @Builder
  Body() {
    Column({ space: Space.SM }) {
      SectionTitle({ text: '日常管理', textSize: Type.BODY })
      CardSurface({ cardPadding: 0 }) {
        Column({ space: Space.XS }) {
          this.NavBtn('📝 任务管理', '模板添加 / 自定义 / 审核开关', 'pages/ParentTasks', true)
          this.NavBtn('👶 宝宝档案', '名字 / 生日 / 年龄档位', 'pages/KidProfile', true)
          this.NavBtn('🎁 心愿商店', '三档定价 / 上下架', 'pages/ParentRewards', true)
          this.NavBtn('🧠 智能建议', '分龄任务推荐 / 完成率评估', 'pages/ParentAdvice', true)
          this.NavBtn('🗺️ 里程碑', '成长路线图 / 达成兑现', 'pages/ParentMilestones', true)
        }
        .width('100%')
      }

      SectionTitle({ text: '打卡提醒', textSize: Type.BODY })
      CardSurface({ cardPadding: Space.MD }) {
        Row({ space: Space.SM }) {
          Column({ space: 2 }) {
            Text('早晚提醒')
              .fontSize(Type.TITLE)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.cocoa_text'))
              .alignSelf(ItemAlign.Start)
            Text('到点弹通知提醒打卡，应用没打开也有效')
              .fontSize(Type.CAPTION)
              .fontColor($r('app.color.mist_gray'))
              .alignSelf(ItemAlign.Start)
          }
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })

          Toggle({ type: ToggleType.Switch, isOn: this.reminderOn })
            .selectedColor($r('app.color.brand_orange'))
            .onChange((isOn: boolean) => {
              this.toggleReminder(isOn);
            })
        }
        .width('100%')

        if (this.reminderOn) {
          Row({ space: Space.SM }) {
            Column({ space: 2 }) {
              Text('☀️ 早上')
                .fontSize(Type.CAPTION)
                .fontColor($r('app.color.mist_gray'))
                .alignSelf(ItemAlign.Start)
              Text(this.morningTime)
                .fontSize(Type.TITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.cocoa_text'))
            }
            .layoutWeight(1)
            .padding(Space.SM)
            .backgroundColor($r('app.color.soft_yellow'))
            .borderRadius(Radius.MD)
            .onClick(() => {
              this.pickTime('morning');
            })

            Column({ space: 2 }) {
              Text('🌙 晚上')
                .fontSize(Type.CAPTION)
                .fontColor($r('app.color.mist_gray'))
                .alignSelf(ItemAlign.Start)
              Text(this.eveningTime)
                .fontSize(Type.TITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.cocoa_text'))
            }
            .layoutWeight(1)
            .padding(Space.SM)
            .backgroundColor($r('app.color.soft_blue'))
            .borderRadius(Radius.MD)
            .onClick(() => {
              this.pickTime('evening');
            })
          }
          .width('100%')
        }
      }

      SectionTitle({ text: '即将上线', textSize: Type.BODY })
      CardSurface({ cardPadding: 0 }) {
        Column({ space: Space.XS }) {
          this.NavBtn('📊 数据看板', '热力图 / 连续记录 / 完成率', 'pages/ParentStats', true)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  build() {
    Column() {
      // 渲染异常诊断条：有全局错误时置顶显示（定位后删除）
      if (this.lastCrash !== '') {
        Text(`⚠ ${this.lastCrash}`)
          .fontSize(12)
          .fontColor(Color.Red)
          .backgroundColor('#FFFFE0E0')
          .padding(8)
          .width('100%')
      }
      if (this.locked) {
        if (this.usePin || !this.fpAvailable) {
          this.PinPad();
        } else {
          this.FingerprintPad();
        }
      } else {
        // content 必须用尾随闭包传入：具名 content: this.Body 为按值传递，
        // Body 内 this 会指向 ParentScaffold，访问 this.NavBtn 报 undefined
        ParentScaffold({ title: '家长模式' }) {
          this.Body()
        }
      }
    }
    .width('100%')
    .height('100%')
  }
}
