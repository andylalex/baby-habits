import { AbilityConstant, UIAbility, Want, errorManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { DatabaseHelper } from '../commons/db/DatabaseHelper';
import { SeedDao, ProfileDao, SettingsDao } from '../commons/db/Dao';
import { BreakpointSystem } from '../commons/utils/BreakpointSystem';
import { SeedData } from '../commons/db/SeedData';

const DOMAIN = 0x0001;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  /** 首页（宝宝模式主界面） */
  private static readonly HOME_PAGE: string = 'pages/Index';
  /** 首次引导页：设置宝宝名字与生日（档案不完整时作为首页加载） */
  private static readonly SETUP_PAGE: string = 'pages/KidProfile';
  /** settings 键：家长跳过首次引导的标记 */
  private static readonly SKIP_SETTING_KEY: string = 'profile_setup_skipped';
  /** 卡片/提醒等外部入口指定的目标页（无则回首页 Index） */
  private pendingPage: string = EntryAbility.HOME_PAGE;
  private mainStage: window.WindowStage | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    // want 带 url（桌面卡片/提醒）→ 跳该页；否则回首页（宝宝模式主界面）
    this.pendingPage = EntryAbility.pageFrom(want) || EntryAbility.HOME_PAGE;
    // 渲染期 JS 异常兜底：注册后未捕获 JS 异常不再杀进程，改为回调 + 落盘日志
    errorManager.on('error', {
      onUnhandledException: (errMsg: string) => {
        hilog.error(DOMAIN, TAG, 'unhandled exception: %{public}s', errMsg);
        // 同步到全局状态：页面顶部红字显示，便于无日志环境定位渲染异常
        const brief = errMsg.length > 400 ? errMsg.substring(0, 400) : errMsg;
        AppStorage.setOrCreate<string>('lastCrash', brief);
        try {
          const path = `${this.context.filesDir}/crash.log`;
          const file = fileIo.openSync(path,
            fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.APPEND);
          fileIo.writeSync(file.fd, `[${new Date().toISOString()}] ${errMsg}\n`);
          fileIo.closeSync(file);
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'write crash.log failed: %{public}s', JSON.stringify(e));
        }
      }
    });
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(DOMAIN, TAG, 'onWindowStageCreate');
    this.mainStage = windowStage;
    try {
      // M1：初始化数据库 + 演示数据
      await DatabaseHelper.init(this.context);
      await SeedDao.ensureSeeded();
      // 「宝宝档案」页的进入方式标记：默认首页加载（无返回按钮），家长模式进入时置 true
      AppStorage.setOrCreate<boolean>('profileEditMode', false);
      // 档案不完整（没生日）且此前没跳过 → 首次引导：先设置宝宝名字与生日，再按年龄套默认模板
      if (!await ProfileDao.isComplete(SeedData.DEMO_KID_ID) && !await EntryAbility.setupSkipped()) {
        this.pendingPage = EntryAbility.SETUP_PAGE;
      }
      // M1：断点系统写入全局状态，页面按 sm/md/lg 响应式布局
      const win = await windowStage.getMainWindow();
      await BreakpointSystem.attach(win);
      // 【窗口级沉浸式布局】官方方案四：
      // 页面布局范围从【安全区】扩展为【整个窗口】（含状态栏与导航条）。
      // 这是弹窗/全屏层能真正"铺满设备"的根本前提——否则页面的 100% 只等于安全区高度。
      // 各页面与弹窗内部再用 safeAreaTop/safeAreaBottom 自行避让内容。
      await EntryAbility.enableImmersiveLayout(win);
      AppStorage.setOrCreate<string>('currentRole', 'kid');
      AppStorage.setOrCreate<number>('activeKidId', SeedData.DEMO_KID_ID);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'init failed: %{public}s', String(err));
    }
    windowStage.loadContent(this.pendingPage, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
      }
    });
  }

  /** 家长此前是否跳过过首次引导（跳过就不再自动弹引导页，改由家长模式里补填） */
  private static async setupSkipped(): Promise<boolean> {
    try {
      const v = await SettingsDao.get(EntryAbility.SKIP_SETTING_KEY);
      return v === '1';
    } catch (err) {
      hilog.info(DOMAIN, TAG, 'read setup_skipped failed: %{public}s', String(err));
      return false;
    }
  }

  /**
   * 开启窗口级沉浸式布局（全屏布局）+ 系统栏背景透明。
   * 布局范围扩展到整个窗口后，页面/弹窗的 100% 高度才是真正的设备高度。
   */  private static async enableImmersiveLayout(win: window.Window): Promise<void> {
    try {
      await win.setWindowLayoutFullScreen(true);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setWindowLayoutFullScreen failed: %{public}s', String(err));
    }
    try {
      // 状态栏/导航条背景透明，弹窗的深色遮罩才能连续铺到屏幕边缘。
      // 内容色用深色：本 App 常态是浅色奶油背景，深色图标才看得清；
      // 全屏看图弹窗的遮罩是半透明黑（#E6000000），透出的仍是浅奶油底，同样适用。
      const props: window.SystemBarProperties = {
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: '#000000',
        navigationBarContentColor: '#000000'
      };
      await win.setWindowSystemBarProperties(props);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', String(err));
    }
  }

  /** 应用已在后台时，卡片点击/提醒点击通过 onNewWant 进来：切到目标页 */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const page = EntryAbility.pageFrom(want);
    // page 为空 = want 未带 url（普通启动），保持当前页面不动
    if (page !== '' && this.mainStage !== null) {
      this.mainStage.loadContent(page, (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, 'loadContent from want failed: %{public}s', JSON.stringify(err));
        }
      });
    }
  }

  /** 从 want 参数解析目标页（桌面卡片 router 动作带 params.url）；无 url 返回空串 */
  private static pageFrom(want: Want): string {
    const params = want.parameters as Record<string, Object> | undefined;
    const url = params?.['url'] as string | undefined;
    if (url !== undefined && url !== '' && url.indexOf('pages/') === 0) {
      return url;
    }
    return '';
  }
}
