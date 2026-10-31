import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'DatabaseHelper';

/** 旧库照片迁移用的行结构 */
interface LegacyPhoto {
  checkinId: number;
  profileId: number;
  taskId: number;
  date: string;
  photoPath: string;
  createdAt: string;
}

const CREATE_TABLES: string[] = [
  `CREATE TABLE IF NOT EXISTS profiles(
     id INTEGER PRIMARY KEY AUTOINCREMENT,
     name TEXT NOT NULL,
     role INTEGER NOT NULL DEFAULT 0,
     birthday TEXT,
     created_at TEXT NOT NULL
   )`,
  `CREATE TABLE IF NOT EXISTS tasks(
     id INTEGER PRIMARY KEY AUTOINCREMENT,
     profile_id INTEGER NOT NULL,
     title TEXT NOT NULL,
     icon TEXT NOT NULL DEFAULT '',
     card_color TEXT NOT NULL DEFAULT '#FFE9C7',
     star_value INTEGER NOT NULL DEFAULT 1,
     category TEXT NOT NULL DEFAULT '生活',
     time_slots TEXT NOT NULL DEFAULT '不限',
     repeat_rule TEXT NOT NULL DEFAULT 'daily',
     need_review INTEGER NOT NULL DEFAULT 0,
     active INTEGER NOT NULL DEFAULT 1,
     sort INTEGER NOT NULL DEFAULT 0
   )`,
  `CREATE TABLE IF NOT EXISTS checkins(
     id INTEGER PRIMARY KEY AUTOINCREMENT,
     task_id INTEGER NOT NULL,
     profile_id INTEGER NOT NULL,
     date TEXT NOT NULL,
     photo_path TEXT,
     status INTEGER NOT NULL DEFAULT 1,
     created_at TEXT NOT NULL
   )`,
  `CREATE TABLE IF NOT EXISTS stars_ledger(
     id INTEGER PRIMARY KEY AUTOINCREMENT,
     profile_id INTEGER NOT NULL,
     delta INTEGER NOT NULL,
     reason_type TEXT NOT NULL,
     ref_id INTEGER,
     created_at TEXT NOT NULL
   )`,
  `CREATE TABLE IF NOT EXISTS rewards(
     id INTEGER PRIMARY KEY AUTOINCREMENT,
     profile_id INTEGER NOT NULL,
     title TEXT NOT NULL,
     icon TEXT NOT NULL DEFAULT '',
     star_cost INTEGER NOT NULL DEFAULT 5,
     tier INTEGER NOT NULL DEFAULT 1,
     stock INTEGER NOT NULL DEFAULT -1,
     active INTEGER NOT NULL DEFAULT 1
   )`,
  `CREATE TABLE IF NOT EXISTS redemptions(
     id INTEGER PRIMARY KEY AUTOINCREMENT,
     reward_id INTEGER NOT NULL,
     profile_id INTEGER NOT NULL,
     star_cost INTEGER NOT NULL,
     status INTEGER NOT NULL DEFAULT 0,
     created_at TEXT NOT NULL
   )`,
  `CREATE TABLE IF NOT EXISTS settings(
     key TEXT PRIMARY KEY,
     value TEXT
   )`,
  `CREATE TABLE IF NOT EXISTS badges(
     id INTEGER PRIMARY KEY AUTOINCREMENT,
     profile_id INTEGER NOT NULL,
     badge_id TEXT NOT NULL,
     unlocked_at TEXT NOT NULL,
     UNIQUE(profile_id, badge_id)
   )`,
  `CREATE TABLE IF NOT EXISTS milestones(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    icon TEXT NOT NULL DEFAULT '🚩',
    kind TEXT NOT NULL DEFAULT 'streak',
    target INTEGER NOT NULL DEFAULT 1,
    reward TEXT NOT NULL DEFAULT '',
    status INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    achieved_at TEXT,
    confirmed_at TEXT
  )`,
  `CREATE TABLE IF NOT EXISTS photos(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    checkin_id INTEGER NOT NULL,
    profile_id INTEGER NOT NULL,
    task_id INTEGER NOT NULL,
    date TEXT NOT NULL,
    photo_path TEXT NOT NULL,
    created_at TEXT NOT NULL
  )`
];

/**
 * RdbStore 单例：建库建表 + 迁移入口。
 * 约定：所有 DAO 经 getStore() 访问，UI 层不直接触碰 relationalStore。
 */
export class DatabaseHelper {
  private static store: relationalStore.RdbStore | null = null;

  static async init(context: common.Context): Promise<void> {
    if (DatabaseHelper.store) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: 'babyhabit.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(context, config);
    for (const sql of CREATE_TABLES) {
      await store.executeSql(sql);
    }
    // 体验版轻迁移：tasks 增加习惯分类列（已存在则忽略报错）
    try {
      await store.executeSql(`ALTER TABLE tasks ADD COLUMN category TEXT NOT NULL DEFAULT '生活'`);
    } catch (err) {
      hilog.info(DOMAIN, TAG, 'category column exists, skip: %{public}s', String(err));
    }
    // 体验版轻迁移：tasks 增加适合时段列（时段推荐用）
    try {
      await store.executeSql(`ALTER TABLE tasks ADD COLUMN time_slots TEXT NOT NULL DEFAULT '不限'`);
    } catch (err) {
      hilog.info(DOMAIN, TAG, 'time_slots column exists, skip: %{public}s', String(err));
    }
    await DatabaseHelper.migrateLegacyPhotos(store);
    DatabaseHelper.store = store;
    hilog.info(DOMAIN, TAG, 'database initialized');
  }

  /**
   * 旧数据迁移：照片从 checkins.photo_path 单字段搬到独立的 photos 表（支持一个任务多张）。
   * 只搬 checkins 里有、photos 表里没有的，避免重复。
   */
  private static async migrateLegacyPhotos(store: relationalStore.RdbStore): Promise<void> {
    try {
      const sql = `SELECT c.id AS cid, c.profile_id AS pid, c.task_id AS tid, c.date AS dt,
        c.photo_path AS pp, c.created_at AS ca
        FROM checkins c
        WHERE c.photo_path IS NOT NULL AND c.photo_path != ''
          AND NOT EXISTS (SELECT 1 FROM photos p WHERE p.checkin_id = c.id)`;
      const rs = await store.querySql(sql, []);
      const rows: LegacyPhoto[] = [];
      while (rs.goToNextRow()) {
        rows.push({
          checkinId: rs.getLong(rs.getColumnIndex('cid')),
          profileId: rs.getLong(rs.getColumnIndex('pid')),
          taskId: rs.getLong(rs.getColumnIndex('tid')),
          date: rs.getString(rs.getColumnIndex('dt')),
          photoPath: rs.getString(rs.getColumnIndex('pp')),
          createdAt: rs.getString(rs.getColumnIndex('ca'))
        });
      }
      rs.close();
      for (const r of rows) {
        await store.insert('photos', {
          checkin_id: r.checkinId,
          profile_id: r.profileId,
          task_id: r.taskId,
          date: r.date,
          photo_path: r.photoPath,
          created_at: r.createdAt
        } as relationalStore.ValuesBucket);
      }
      if (rows.length > 0) {
        hilog.info(DOMAIN, TAG, 'migrated legacy photos: %{public}d', rows.length);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'migrate legacy photos failed: %{public}s', String(err));
    }
  }

  static getStore(): relationalStore.RdbStore {
    if (!DatabaseHelper.store) {
      throw new Error('DatabaseHelper not initialized, call init() first');
    }
    return DatabaseHelper.store;
  }

  /** 当前本地日历日，格式 YYYY-MM-DD */
  static today(): string {
    const d = new Date();
    const m = `${d.getMonth() + 1}`.padStart(2, '0');
    const day = `${d.getDate()}`.padStart(2, '0');
    return `${d.getFullYear()}-${m}-${day}`;
  }

  static now(): string {
    return new Date().toISOString();
  }
}
