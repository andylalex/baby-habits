import { textToSpeech } from '@kit.CoreSpeechKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SettingsDao } from '../db/Dao';

const DOMAIN = 0x0001;
const TAG = 'Sound';

/**
 * 语音播报（HarmonyOS Core Speech Kit TTS，系统级免费）。
 * 懒加载引擎，全局单例；播报排队打断上一次。
 * 需要 ohos.permission.INTERNET（在线合成）。
 *
 * 全局开关：用户可在首页关闭播报，设置持久化到 settings 表，
 * 并通过 AppStorage 同步到所有页面（各页 speak 前会检查开关）。
 */
export class Sound {
  private static engine: textToSpeech.TextToSpeechEngine | null = null;
  private static creating: boolean = false;
  private static pending: string[] = [];
  /** 播报开关的全局同步键 */
  static readonly ENABLED_KEY: string = 'soundEnabled';
  /** settings 表里的持久化键 */
  private static readonly STORE_KEY: string = 'sound_enabled';

  /** 预热引擎（进入儿童页时调用，避免首次点击延迟）。播报关闭时不创建引擎 */
  static async init(): Promise<void> {
    if (!Sound.isEnabled()) {
      return;
    }
    await Sound.ensureEngine();
  }

  /** 当前是否开启播报（默认开） */
  static isEnabled(): boolean {
    const v = AppStorage.get<boolean>(Sound.ENABLED_KEY);
    return v === undefined ? true : v;
  }

  /** 设置播报开关并持久化；关闭时立即停止正在进行的播报 */
  static async setEnabled(on: boolean): Promise<void> {
    AppStorage.setOrCreate<boolean>(Sound.ENABLED_KEY, on);
    if (!on) {
      Sound.stopSpeaking();
    }
    try {
      await SettingsDao.set(Sound.STORE_KEY, on ? '1' : '0');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'save sound_enabled failed: %{public}s', String(err));
    }
  }

  /** 从持久化存储恢复开关状态（进入首页时调用） */
  static async loadEnabled(): Promise<boolean> {
    let on = true;
    try {
      const stored = await SettingsDao.get(Sound.STORE_KEY);
      if (stored !== null) {
        on = stored === '1';
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'load sound_enabled failed: %{public}s', String(err));
    }
    AppStorage.setOrCreate<boolean>(Sound.ENABLED_KEY, on);
    return on;
  }

  /** 停止当前播报并清空待播队列 */
  static stopSpeaking(): void {
    Sound.pending = [];
    const engine = Sound.engine;
    if (engine === null) {
      return;
    }
    try {
      if (engine.isBusy()) {
        engine.stop();
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'stop speak failed: %{public}s', String(err));
    }
  }

  private static async ensureEngine(): Promise<boolean> {
    if (Sound.engine !== null) {
      return true;
    }
    if (Sound.creating) {
      return false;
    }
    Sound.creating = true;
    const extraParams: Record<string, Object> = {
      'style': 'interaction-broadcast',
      'locate': 'CN',
      'name': 'BabyHabitsTTS'
    };
    const params: textToSpeech.CreateEngineParams = {
      language: 'zh-CN',
      person: 0,
      online: 1,
      extraParams: extraParams
    };
    try {
      const engine = await textToSpeech.createEngine(params);
      Sound.engine = engine;
      // 合成/播报错误通过监听器回报
      const listener: textToSpeech.SpeakListener = {
        onStart: (requestId: string, response: textToSpeech.StartResponse) => {
          hilog.info(DOMAIN, TAG, 'speak start %{public}s', requestId);
        },
        onComplete: (requestId: string, response: textToSpeech.CompleteResponse) => {
          hilog.info(DOMAIN, TAG, 'speak complete %{public}s type=%{public}d', requestId, response.type);
        },
        onStop: (requestId: string, response: textToSpeech.StopResponse) => {
          hilog.info(DOMAIN, TAG, 'speak stop %{public}s', requestId);
        },
        onData: (requestId: string, audio: ArrayBuffer) => {
          // 播放型合成无需处理音频数据
        },
        onError: (requestId: string, errorCode: number, errorMessage: string) => {
          hilog.error(DOMAIN, TAG, 'speak error %{public}s code=%{public}d %{public}s',
            requestId, errorCode, errorMessage);
        }
      };
      engine.setListener(listener);
      hilog.info(DOMAIN, TAG, 'tts engine ready');
      // 补播排队文本（期间开关被关掉则丢弃队列）
      const queue = Sound.pending;
      Sound.pending = [];
      if (Sound.isEnabled()) {
        for (const t of queue) {
          Sound.doSpeak(t);
        }
      }
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'tts engine create failed: %{public}s', String(err));
      return false;
    } finally {
      Sound.creating = false;
    }
  }

  /** 播报文本：引擎未就绪先入队，就绪后补播。播报开关关闭时直接忽略 */
  static speak(text: string): void {
    if (text === '') {
      return;
    }
    // 全局开关关闭：不再播报，也不入队
    if (!Sound.isEnabled()) {
      return;
    }
    if (Sound.engine === null) {
      Sound.pending.push(text);
      Sound.ensureEngine();
      return;
    }
    Sound.doSpeak(text);
  }

  private static doSpeak(text: string): void {
    const engine = Sound.engine;
    if (engine === null) {
      return;
    }
    try {
      if (engine.isBusy()) {
        engine.stop();
      }
      const extraParams: Record<string, Object> = {
        'queueMode': 0,
        'speed': 1,
        'volume': 2,
        'pitch': 1,
        'languageContext': 'zh-CN',
        'playType': 1, // 1=引擎直接外放；0 只回调音频数据不播放
        'soundChannel': 3
      };
      const speakParams: textToSpeech.SpeakParams = {
        requestId: `${Date.now()}`,
        extraParams: extraParams
      };
      engine.speak(text, speakParams);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'speak error: %{public}s', String(err));
    }
  }
}
