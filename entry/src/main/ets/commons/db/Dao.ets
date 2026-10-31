import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TaskItem, RewardItem, RedemptionCard, CheckinStatus, PhotoEntry, LedgerEntry, MilestoneItem, PendingCheckin, KidProfile } from '../models/Models';
import { DatabaseHelper } from './DatabaseHelper';
import { SeedData } from './SeedData';
import { BADGES, BadgeStats } from '../utils/Badges';
import { AgeUtil } from '../utils/AgeUtil';

/**
 * DAO 层：所有方法返回 Promise，多步写必须走事务。
 */

export class ProfileDao {
  /**
   * 读宝宝档案（name + birthday）。查不到返回 null。
   * age 由生日推导，生日为空时为 0。
   */
  static async get(profileId: number): Promise<KidProfile | null> {
    const predicates = new relationalStore.RdbPredicates('profiles');
    predicates.equalTo('id', profileId);
    const rs = await DatabaseHelper.getStore().query(predicates, ['id', 'name', 'birthday']);
    let profile: KidProfile | null = null;
    if (rs.goToNextRow()) {
      const id = rs.getLong(rs.getColumnIndex('id'));
      const name = rs.getString(rs.getColumnIndex('name'));
      const birthday = rs.getString(rs.getColumnIndex('birthday'));
      profile = new KidProfile(id, name, birthday, AgeUtil.ageOf(birthday));
    }
    rs.close();
    return profile;
  }

  /**
   * 更新宝宝档案（名字 + 生日）。家长模式里改这两项走这里。
   * name 为空串表示不改名字；birthday 为 null 表示不改生日。
   */
  static async update(profileId: number, name: string, birthday: string | null): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('profiles');
    predicates.equalTo('id', profileId);
    if (name !== '' && birthday !== null) {
      await DatabaseHelper.getStore().update({
        name: name,
        birthday: birthday
      } as relationalStore.ValuesBucket, predicates);
      return;
    }
    if (name !== '') {
      await DatabaseHelper.getStore().update({ name: name } as relationalStore.ValuesBucket, predicates);
      return;
    }
    if (birthday !== null) {
      await DatabaseHelper.getStore().update({ birthday: birthday } as relationalStore.ValuesBucket, predicates);
    }
  }

  /** 档案是否已完善（有名字且有生日）——用于判断要不要走首次引导 */
  static async isComplete(profileId: number): Promise<boolean> {
    const profile = await ProfileDao.get(profileId);
    if (profile === null) {
      return false;
    }
    return profile.name !== '' && profile.birthday !== '';
  }
}

export class TaskDao {
  /** 宝宝启用中的任务（按 sort 排序，即今日时间轴） */
  static async listActive(profileId: number): Promise<TaskItem[]> {
    const predicates = new relationalStore.RdbPredicates('tasks');
    predicates.equalTo('profile_id', profileId).equalTo('active', 1).orderByAsc('sort');
    const rs = await DatabaseHelper.getStore().query(predicates,
      ['id', 'title', 'icon', 'card_color', 'star_value', 'need_review', 'category', 'time_slots']);
    const list: TaskItem[] = [];
    while (rs.goToNextRow()) {
      const item = new TaskItem(
        rs.getLong(rs.getColumnIndex('id')),
        rs.getString(rs.getColumnIndex('title')),
        rs.getString(rs.getColumnIndex('icon')),
        rs.getString(rs.getColumnIndex('card_color')),
        rs.getLong(rs.getColumnIndex('star_value')),
        rs.getLong(rs.getColumnIndex('need_review')) === 1,
        rs.getString(rs.getColumnIndex('category')),
        rs.getString(rs.getColumnIndex('time_slots'))
      );
      list.push(item);
    }
    rs.close();
    return list;
  }

  static async insert(profileId: number, t: TaskItem, sort: number): Promise<number> {
    const bucket: relationalStore.ValuesBucket = {
      profile_id: profileId,
      title: t.title,
      icon: t.icon,
      card_color: t.cardColor,
      star_value: t.starValue,
      category: t.category,
      time_slots: t.timeSlots,
      repeat_rule: 'daily',
      need_review: t.needReview ? 1 : 0,
      active: 1,
      sort: sort
    };
    return DatabaseHelper.getStore().insert('tasks', bucket);
  }

  /** 软删除：active=0，儿童端不再显示 */
  static async deactivate(taskId: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('tasks');
    predicates.equalTo('id', taskId);
    await DatabaseHelper.getStore().update({ active: 0 } as relationalStore.ValuesBucket, predicates);
  }

  /**
   * 软删除该档案的全部启用任务（切换年龄档位重新套用模板时用）。
   * 只停用任务，不动打卡记录与星星流水 —— 宝宝已有的成就不能因为换模板而消失。
   */
  static async deactivateAll(profileId: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('tasks');
    predicates.equalTo('profile_id', profileId).equalTo('active', 1);
    await DatabaseHelper.getStore().update({ active: 0 } as relationalStore.ValuesBucket, predicates);
  }

  static async setNeedReview(taskId: number, needReview: boolean): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('tasks');
    predicates.equalTo('id', taskId);
    await DatabaseHelper.getStore().update({ need_review: needReview ? 1 : 0 } as relationalStore.ValuesBucket,
      predicates);
  }

  /** 拖拽换分类：只改分类，打卡记录与星星不受影响 */
  static async setCategory(taskId: number, category: string): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('tasks');
    predicates.equalTo('id', taskId);
    await DatabaseHelper.getStore().update({ category: category } as relationalStore.ValuesBucket, predicates);
  }

  /** 改适合时段：逗号分隔（如 '早晨,上午'） */
  static async setTimeSlots(taskId: number, timeSlots: string): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('tasks');
    predicates.equalTo('id', taskId);
    await DatabaseHelper.getStore().update({ time_slots: timeSlots } as relationalStore.ValuesBucket, predicates);
  }

  /**
   * 用一批任务替换该档案的启用任务（事务：全部软删除 + 批量插入）。
   * 用途：家长改生日导致年龄档位变化时，按新档位的分龄模板重建任务列表。
   * 只动任务表，不碰打卡记录与星星流水 —— 宝宝已有的成就不因换模板而消失。
   */
  static async replaceAll(profileId: number, tasks: TaskItem[]): Promise<void> {
    const store = DatabaseHelper.getStore();
    const tx = await store.createTransaction({});
    try {
      const old = new relationalStore.RdbPredicates('tasks');
      old.equalTo('profile_id', profileId).equalTo('active', 1);
      await tx.update({ active: 0 } as relationalStore.ValuesBucket, old);
      for (let i = 0; i < tasks.length; i++) {
        const t = tasks[i];
        await tx.insert('tasks', {
          profile_id: profileId,
          title: t.title,
          icon: t.icon,
          card_color: t.cardColor,
          star_value: t.starValue,
          category: t.category,
          time_slots: t.timeSlots,
          repeat_rule: 'daily',
          need_review: t.needReview ? 1 : 0,
          active: 1,
          sort: i
        } as relationalStore.ValuesBucket);
      }
      await tx.commit();
    } catch (err) {
      await tx.rollback();
      throw new Error(`replaceAll failed: ${String(err)}`);
    }
  }

  /**
   * 就地更新任务（家长在模板上自定义后保存走这条）。
   * 包含标题：家长基于已有任务改名时应当改原任务，而不是多出一条同名/近名任务。
   */
  static async updateTask(taskId: number, title: string, icon: string, starValue: number,
    needReview: boolean, category: string, timeSlots: string, cardColor: string): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('tasks');
    predicates.equalTo('id', taskId);
    await DatabaseHelper.getStore().update({
      title: title,
      icon: icon,
      card_color: cardColor,
      star_value: starValue,
      need_review: needReview ? 1 : 0,
      category: category,
      time_slots: timeSlots
    } as relationalStore.ValuesBucket, predicates);
  }
}

export class CheckinDao {
  /** 今日已完成（或待审核）的任务 ID 集合 */
  static async todayDoneTaskIds(profileId: number, date: string): Promise<Set<number>> {
    const predicates = new relationalStore.RdbPredicates('checkins');
    predicates.equalTo('profile_id', profileId).equalTo('date', date);
    const rs = await DatabaseHelper.getStore().query(predicates, ['task_id']);
    const ids: Set<number> = new Set();
    while (rs.goToNextRow()) {
      ids.add(rs.getLong(rs.getColumnIndex('task_id')));
    }
    rs.close();
    return ids;
  }

  /**
   * 今日【已确认完成】的任务 ID 集合（status = DONE）。
   * 与 todayDoneTaskIds 的区别：待家长审核的记录（status = PENDING_REVIEW）
   * 不算真正完成 —— 宝宝端据此把卡片显示成「等家长确认」而不是「已完成」，
   * 避免家长还没点头就显示完成。
   */
  static async todayConfirmedTaskIds(profileId: number, date: string): Promise<Set<number>> {
    const predicates = new relationalStore.RdbPredicates('checkins');
    predicates.equalTo('profile_id', profileId).equalTo('date', date)
      .equalTo('status', CheckinStatus.DONE);
    const rs = await DatabaseHelper.getStore().query(predicates, ['task_id']);
    const ids: Set<number> = new Set();
    while (rs.goToNextRow()) {
      ids.add(rs.getLong(rs.getColumnIndex('task_id')));
    }
    rs.close();
    return ids;
  }

  /** 今日【待家长审核】的任务 ID 集合（status = PENDING_REVIEW） */
  static async todayPendingTaskIds(profileId: number, date: string): Promise<Set<number>> {
    const predicates = new relationalStore.RdbPredicates('checkins');
    predicates.equalTo('profile_id', profileId).equalTo('date', date)
      .equalTo('status', CheckinStatus.PENDING_REVIEW);
    const rs = await DatabaseHelper.getStore().query(predicates, ['task_id']);
    const ids: Set<number> = new Set();
    while (rs.goToNextRow()) {
      ids.add(rs.getLong(rs.getColumnIndex('task_id')));
    }
    rs.close();
    return ids;
  }

  /** 某任务今日是否已有打卡记录（任何状态，含待审核） */
  static async hasCheckin(profileId: number, taskId: number, date: string): Promise<boolean> {
    const predicates = new relationalStore.RdbPredicates('checkins');
    predicates.equalTo('profile_id', profileId).equalTo('task_id', taskId).equalTo('date', date);
    const rs = await DatabaseHelper.getStore().query(predicates, ['id']);
    const has = rs.goToNextRow();
    rs.close();
    return has;
  }

  /** 待家长审核的打卡记录（status = PENDING_REVIEW），按时间倒序 */
  static async pendingReviews(profileId: number, date: string): Promise<PendingCheckin[]> {
    const sql = `SELECT c.id AS cid, c.task_id AS tid, c.date AS dt, c.photo_path AS pp,
        t.title AS title, t.icon AS icon, t.star_value AS sv
      FROM checkins c INNER JOIN tasks t ON t.id = c.task_id
      WHERE c.profile_id = ? AND c.date = ? AND c.status = ?
      ORDER BY c.created_at DESC`;
    const rs = await DatabaseHelper.getStore().querySql(sql,
      [profileId, date, CheckinStatus.PENDING_REVIEW]);
    const list: PendingCheckin[] = [];
    while (rs.goToNextRow()) {
      list.push({
        id: rs.getLong(rs.getColumnIndex('cid')),
        taskId: rs.getLong(rs.getColumnIndex('tid')),
        title: rs.getString(rs.getColumnIndex('title')),
        icon: rs.getString(rs.getColumnIndex('icon')),
        starValue: rs.getLong(rs.getColumnIndex('sv')),
        date: rs.getString(rs.getColumnIndex('dt')),
        photoPath: rs.getString(rs.getColumnIndex('pp'))
      });
    }
    rs.close();
    return list;
  }

  /**
   * 家长审核通过：待审核 → 已完成，并把星星补记上。
   * 打卡时 needReview 的任务不发星星（怕宝宝自己刷），这里通过后才入账。
   */
  static async approveReview(checkinId: number, profileId: number, starValue: number): Promise<void> {
    const store = DatabaseHelper.getStore();
    const tx = await store.createTransaction({});
    try {
      const p = new relationalStore.RdbPredicates('checkins');
      p.equalTo('id', checkinId);
      await tx.update({ status: CheckinStatus.DONE } as relationalStore.ValuesBucket, p);
      await tx.insert('stars_ledger', {
        profile_id: profileId,
        delta: starValue,
        reason_type: 'task',
        ref_id: checkinId,
        created_at: DatabaseHelper.now()
      } as relationalStore.ValuesBucket);
      await tx.commit();
    } catch (err) {
      await tx.rollback();
      throw new Error(`approveReview failed: ${String(err)}`);
    }
  }

  /** 家长审核驳回：删除该条打卡记录（不发星星） */
  static async rejectReview(checkinId: number): Promise<void> {
    const store = DatabaseHelper.getStore();
    const p = new relationalStore.RdbPredicates('checkins');
    p.equalTo('id', checkinId);
    await store.delete(p);
  }

  /** 事务：写入打卡记录（可带多张照片沙盒路径）+ 星星流水；连续打卡当天首卡 +1 星加成。
   *  返回 true 表示本次打卡获得了连续打卡奖励。
   *  photoPaths：同一任务可拍多张照片，全部写入 photos 表；checkins.photo_path 存首图（兼容旧查询）。
   *  幂等：同一任务同一天已有打卡记录时直接返回（不重复插入、不重复发星星）——
   *  checkins 表没有 (task_id, date) 唯一约束，不做这层保护会因重复点击而重复计星。 */
  static async checkin(task: TaskItem, profileId: number, date: string,
    photoPaths: string[] = []): Promise<boolean> {
    // 已打卡过就不再重复写（防止重复点击导致重复发星）
    if (await CheckinDao.hasCheckin(profileId, task.id, date)) {
      return false;
    }
    const status = task.needReview ? CheckinStatus.PENDING_REVIEW : CheckinStatus.DONE;
    // 过滤空路径
    const photos: string[] = [];
    for (const p of photoPaths) {
      if (p !== '') {
        photos.push(p);
      }
    }
    const firstPhoto = photos.length > 0 ? photos[0] : '';
    // 事务外预查：昨天有完成打卡 → 今天首卡 +1（体验版容忍轻微竞态）
    const dates = await CheckinDao.doneDates(profileId);
    const streakBonus = !task.needReview && dates.indexOf(CheckinDao.prevDay(date)) >= 0;
    const tx = await DatabaseHelper.getStore().createTransaction({});
    try {
      const checkinId = await tx.insert('checkins', {
        task_id: task.id,
        profile_id: profileId,
        date: date,
        photo_path: firstPhoto,
        status: status,
        created_at: DatabaseHelper.now()
      } as relationalStore.ValuesBucket);
      // 多张照片逐张入库
      for (const p of photos) {
        await tx.insert('photos', {
          checkin_id: checkinId,
          profile_id: profileId,
          task_id: task.id,
          date: date,
          photo_path: p,
          created_at: DatabaseHelper.now()
        } as relationalStore.ValuesBucket);
      }
      if (!task.needReview) {
        await tx.insert('stars_ledger', {
          profile_id: profileId,
          delta: task.starValue,
          reason_type: 'task',
          ref_id: task.id,
          created_at: DatabaseHelper.now()
        } as relationalStore.ValuesBucket);
        if (streakBonus) {
          await tx.insert('stars_ledger', {
            profile_id: profileId,
            delta: 1,
            reason_type: 'bonus',
            ref_id: task.id,
            created_at: DatabaseHelper.now()
          } as relationalStore.ValuesBucket);
        }
      }
      await tx.commit();
    } catch (err) {
      await tx.rollback();
      throw new Error(`checkin failed: ${String(err)}`);
    }
    return streakBonus;
  }

  /** 今日 taskId -> 照片沙盒路径列表（一个任务可有多张），供任务卡缩略角标 */
  static async todayPhotos(profileId: number, date: string): Promise<Map<number, string[]>> {
    const predicates = new relationalStore.RdbPredicates('photos');
    predicates.equalTo('profile_id', profileId).equalTo('date', date);
    const rs = await DatabaseHelper.getStore().query(predicates, ['task_id', 'photo_path']);
    const map: Map<number, string[]> = new Map();
    while (rs.goToNextRow()) {
      const taskId = rs.getLong(rs.getColumnIndex('task_id'));
      const path = rs.getString(rs.getColumnIndex('photo_path'));
      const list = map.get(taskId);
      if (list === undefined) {
        map.set(taskId, [path]);
      } else {
        list.push(path);
      }
    }
    rs.close();
    return map;
  }

  /** 某任务今日已拍的照片路径列表 */
  static async taskPhotos(profileId: number, taskId: number, date: string): Promise<string[]> {
    const predicates = new relationalStore.RdbPredicates('photos');
    predicates.equalTo('profile_id', profileId).equalTo('task_id', taskId).equalTo('date', date);
    const rs = await DatabaseHelper.getStore().query(predicates, ['photo_path']);
    const list: string[] = [];
    while (rs.goToNextRow()) {
      list.push(rs.getString(rs.getColumnIndex('photo_path')));
    }
    rs.close();
    return list;
  }

  /**
   * 给【已完成】的任务补拍照片：只往 photos 表追加，
   * **不改打卡状态、不重复记星星**（打卡与星星在 checkin 时已记过）。
   * 返回追加后的照片总数，失败返回 -1。
   */
  static async appendPhoto(profileId: number, taskId: number, date: string,
    photoPath: string): Promise<number> {
    if (photoPath === '') {
      return -1;
    }
    try {
      // 找到该任务今天的打卡记录，关联进去（照片挂到打卡下，逻辑与首次打卡一致）
      const cp = new relationalStore.RdbPredicates('checkins');
      cp.equalTo('profile_id', profileId).equalTo('task_id', taskId).equalTo('date', date)
        .orderByDesc('created_at').limitAs(1);
      const crs = await DatabaseHelper.getStore().query(cp, ['id']);
      let checkinId = -1;
      if (crs.goToNextRow()) {
        checkinId = crs.getLong(crs.getColumnIndex('id'));
      }
      crs.close();
      if (checkinId < 0) {
        return -1;
      }
      await DatabaseHelper.getStore().insert('photos', {
        checkin_id: checkinId,
        profile_id: profileId,
        task_id: taskId,
        date: date,
        photo_path: photoPath,
        created_at: DatabaseHelper.now()
      } as relationalStore.ValuesBucket);
      // 同步 checkins.photo_path：为空则补为首图
      const up = new relationalStore.RdbPredicates('checkins');
      up.equalTo('id', checkinId);
      const urs = await DatabaseHelper.getStore().query(up, ['photo_path']);
      let first = '';
      if (urs.goToNextRow()) {
        first = urs.getString(urs.getColumnIndex('photo_path'));
      }
      urs.close();
      if (first === '') {
        await DatabaseHelper.getStore().update({ photo_path: photoPath } as relationalStore.ValuesBucket, up);
      }
      return CheckinDao.taskPhotos(profileId, taskId, date).then((list: string[]) => list.length);
    } catch (err) {
      hilog.error(0x0001, 'CheckinDao', 'appendPhoto failed: %{public}s', String(err));
      return -1;
    }
  }

  /** 最近 N 张带照片的打卡（成长相册），按时间倒序；一张照片一条记录。
   *  title 由调用方用任务表回填。 */
  static async recentPhotos(profileId: number, limit: number = 50): Promise<PhotoEntry[]> {
    const predicates = new relationalStore.RdbPredicates('photos');
    predicates.equalTo('profile_id', profileId).orderByDesc('created_at').limitAs(limit);
    const rs = await DatabaseHelper.getStore().query(predicates, ['id', 'task_id', 'date', 'photo_path']);
    const list: PhotoEntry[] = [];
    while (rs.goToNextRow()) {
      list.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        taskId: rs.getLong(rs.getColumnIndex('task_id')),
        title: '',
        date: rs.getString(rs.getColumnIndex('date')),
        photoPath: rs.getString(rs.getColumnIndex('photo_path'))
      });
    }
    rs.close();
    return list;
  }

  /** 删除一张照片：按 photos 行 id 删除该行（不动打卡记录和星星流水），返回沙盒路径供删文件。
   *  同时把 checkins.photo_path 同步为首图（若删的是首图则换成下一张）。 */
  static async clearPhoto(photoId: number): Promise<string> {
    const store = DatabaseHelper.getStore();
    const q = new relationalStore.RdbPredicates('photos');
    q.equalTo('id', photoId);
    const rs = await store.query(q, ['photo_path', 'checkin_id', 'task_id', 'date']);
    let path = '';
    let checkinId = -1;
    let taskId = -1;
    let date = '';
    if (rs.goToNextRow()) {
      path = rs.getString(rs.getColumnIndex('photo_path'));
      checkinId = rs.getLong(rs.getColumnIndex('checkin_id'));
      taskId = rs.getLong(rs.getColumnIndex('task_id'));
      date = rs.getString(rs.getColumnIndex('date'));
    }
    rs.close();
    if (path === '') {
      return '';
    }
    await store.delete(q);
    // 同步 checkins.photo_path：若它指向被删的这张，改成同任务同日期的下一张
    const cq = new relationalStore.RdbPredicates('checkins');
    cq.equalTo('id', checkinId);
    const crs = await store.query(cq, ['photo_path']);
    let current = '';
    if (crs.goToNextRow()) {
      current = crs.getString(crs.getColumnIndex('photo_path'));
    }
    crs.close();
    if (current === path) {
      // 该照片是首图：从 photos 表找同任务同日期的下一张作为新首图
      const pq = new relationalStore.RdbPredicates('photos');
      pq.equalTo('task_id', taskId).equalTo('date', date);
      const prs = await store.query(pq, ['photo_path']);
      let next = '';
      while (prs.goToNextRow()) {
        const p = prs.getString(prs.getColumnIndex('photo_path'));
        if (p !== path) {
          next = p;
          break;
        }
      }
      prs.close();
      await store.update({ photo_path: next } as relationalStore.ValuesBucket, cq);
    }
    return path;
  }

  /** 有完成打卡的日期列表（倒序，YYYY-MM-DD） */
  static async doneDates(profileId: number): Promise<string[]> {
    const sql = `SELECT DISTINCT date FROM checkins WHERE profile_id = ? AND status = 1 ORDER BY date DESC`;
    const rs = await DatabaseHelper.getStore().querySql(sql, [profileId]);
    const dates: string[] = [];
    while (rs.goToNextRow()) {
      dates.push(rs.getString(rs.getColumnIndex('date')));
    }
    rs.close();
    return dates;
  }

  /** 前一天 YYYY-MM-DD */
  private static prevDay(date: string): string {
    const d = new Date(`${date}T00:00:00`);
    d.setDate(d.getDate() - 1);
    const m = `${d.getMonth() + 1}`.padStart(2, '0');
    const day = `${d.getDate()}`.padStart(2, '0');
    return `${d.getFullYear()}-${m}-${day}`;
  }

  /** 当前连续打卡天数：从今天（或昨天，今天还没打）往前逐日连续 */
  static async currentStreak(profileId: number, today: string): Promise<number> {
    const dates = await CheckinDao.doneDates(profileId);
    if (dates.length === 0) {
      return 0;
    }
    const set: Set<string> = new Set(dates);
    let anchor = today;
    if (!set.has(today)) {
      anchor = CheckinDao.prevDay(today); // 今天还没打卡，从昨天算起
    }
    let streak = 0;
    let cur = anchor;
    while (set.has(cur)) {
      streak++;
      cur = CheckinDao.prevDay(cur);
    }
    return streak;
  }

  /** 历史最长连续天数 */
  static async longestStreak(profileId: number): Promise<number> {
    const dates = await CheckinDao.doneDates(profileId);
    if (dates.length === 0) {
      return 0;
    }
    const set: Set<string> = new Set(dates);
    let best = 1;
    let run = 1;
    for (let i = 0; i < dates.length - 1; i++) {
      if (CheckinDao.prevDay(dates[i]) === dates[i + 1]) {
        run++;
        if (run > best) {
          best = run;
        }
      } else {
        run = 1;
      }
    }
    return best;
  }

  /** 每日完成次数（近 N 天，返回 date -> 次数，热力图用） */
  static async dailyCounts(profileId: number, since: string): Promise<Map<string, number>> {
    const sql = `SELECT date, COUNT(*) AS cnt FROM checkins
      WHERE profile_id = ? AND status = 1 AND date >= ? GROUP BY date ORDER BY date`;
    const rs = await DatabaseHelper.getStore().querySql(sql, [profileId, since]);
    const map: Map<string, number> = new Map();
    while (rs.goToNextRow()) {
      map.set(rs.getString(rs.getColumnIndex('date')), rs.getLong(rs.getColumnIndex('cnt')));
    }
    rs.close();
    return map;
  }
}

export class StarDao {
  /** 余额只允许由流水 SUM 得出，禁止直改 */
  static async balance(profileId: number): Promise<number> {
    const predicates = new relationalStore.RdbPredicates('stars_ledger');
    predicates.equalTo('profile_id', profileId);
    const rs = await DatabaseHelper.getStore().query(predicates, ['delta']);
    let sum = 0;
    while (rs.goToNextRow()) {
      sum += rs.getLong(rs.getColumnIndex('delta'));
    }
    rs.close();
    return sum;
  }

  /** 今日已入账星星（任务类流水） */
  static async todayEarned(profileId: number, date: string): Promise<number> {
    const dayStart = `${date}T00:00:00`;
    const predicates = new relationalStore.RdbPredicates('stars_ledger');
    predicates.equalTo('profile_id', profileId).greaterThan('created_at', dayStart);
    const rs = await DatabaseHelper.getStore().query(predicates, ['delta']);
    let sum = 0;
    while (rs.goToNextRow()) {
      sum += rs.getLong(rs.getColumnIndex('delta'));
    }
    rs.close();
    return sum;
  }

  static async addRaw(profileId: number, delta: number, reason: string, refId: number): Promise<number> {
    return DatabaseHelper.getStore().insert('stars_ledger', {
      profile_id: profileId,
      delta: delta,
      reason_type: reason,
      ref_id: refId,
      created_at: DatabaseHelper.now()
    } as relationalStore.ValuesBucket);
  }

  /** 星星账本：流水倒序 + 关联任务/心愿名（本地联查，task 可能已停用仍能查到名） */
  static async listLedger(profileId: number, limit: number = 200): Promise<LedgerEntry[]> {
    const sql = `SELECT l.id, l.delta, l.reason_type, l.ref_id, l.created_at,
      CASE l.reason_type
        WHEN 'task' THEN (SELECT title FROM tasks t WHERE t.id = l.ref_id)
        WHEN 'redeem' THEN (SELECT title FROM rewards r WHERE r.id = l.ref_id)
        ELSE '' END AS ref_title
      FROM stars_ledger l WHERE l.profile_id = ?
      ORDER BY l.created_at DESC LIMIT ?`;
    const rs = await DatabaseHelper.getStore().querySql(sql, [profileId, limit]);
    const list: LedgerEntry[] = [];
    while (rs.goToNextRow()) {
      const reason = rs.getString(rs.getColumnIndex('reason_type'));
      let title = rs.getString(rs.getColumnIndex('ref_title'));
      if (title === '') {
        title = reason === 'redeem' ? '心愿兑换' : (reason === 'bonus' ? '额外奖励' : '打卡奖励');
      }
      list.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        delta: rs.getLong(rs.getColumnIndex('delta')),
        reason: reason,
        title: title,
        createdAt: rs.getString(rs.getColumnIndex('created_at'))
      } as LedgerEntry);
    }
    rs.close();
    return list;
  }
}

export class RewardDao {
  static async listActive(profileId: number): Promise<RewardItem[]> {
    const predicates = new relationalStore.RdbPredicates('rewards');
    predicates.equalTo('profile_id', profileId).equalTo('active', 1).orderByAsc('star_cost');
    const rs = await DatabaseHelper.getStore().query(predicates,
      ['id', 'title', 'icon', 'star_cost', 'tier']);
    const list: RewardItem[] = [];
    while (rs.goToNextRow()) {
      list.push(new RewardItem(
        rs.getLong(rs.getColumnIndex('id')),
        rs.getString(rs.getColumnIndex('title')),
        rs.getString(rs.getColumnIndex('icon')),
        rs.getLong(rs.getColumnIndex('star_cost')),
        rs.getLong(rs.getColumnIndex('tier'))
      ));
    }
    rs.close();
    return list;
  }

  static async insert(profileId: number, r: RewardItem): Promise<number> {
    return DatabaseHelper.getStore().insert('rewards', {
      profile_id: profileId,
      title: r.title,
      icon: r.icon,
      star_cost: r.starCost,
      tier: r.tier,
      stock: -1,
      active: 1
    } as relationalStore.ValuesBucket);
  }

  /** 软删除：下架心愿 */
  static async deactivate(rewardId: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('rewards');
    predicates.equalTo('id', rewardId);
    await DatabaseHelper.getStore().update({ active: 0 } as relationalStore.ValuesBucket, predicates);
  }
}

export class RedemptionDao {
  /** 事务：扣星 + 生成已兑现兑换单（MVP 由家长长按现场确认，直接兑现） */
  static async redeem(profileId: number, reward: RewardItem): Promise<void> {
    const tx = await DatabaseHelper.getStore().createTransaction({});
    try {
      await tx.insert('redemptions', {
        reward_id: reward.id,
        profile_id: profileId,
        star_cost: reward.starCost,
        status: 3, // 已兑现
        created_at: DatabaseHelper.now()
      } as relationalStore.ValuesBucket);
      await tx.insert('stars_ledger', {
        profile_id: profileId,
        delta: -reward.starCost,
        reason_type: 'redeem',
        ref_id: reward.id,
        created_at: DatabaseHelper.now()
      } as relationalStore.ValuesBucket);
      await tx.commit();
    } catch (err) {
      await tx.rollback();
      throw new Error(`redeem failed: ${String(err)}`);
    }
  }

  /** 收集卡册：已兑换的心愿卡，按时间倒序 */
  static async listCards(profileId: number): Promise<RedemptionCard[]> {
    const sql = `SELECT r.id AS rid, rw.title, rw.icon, r.created_at
                 FROM redemptions r JOIN rewards rw ON r.reward_id = rw.id
                 WHERE r.profile_id = ? AND r.status = 3
                 ORDER BY r.created_at DESC`;
    const rs = await DatabaseHelper.getStore().querySql(sql, [profileId]);
    const cards: RedemptionCard[] = [];
    while (rs.goToNextRow()) {
      const raw = rs.getString(rs.getColumnIndex('created_at'));
      const date = raw.length >= 10 ? raw.substring(0, 10) : raw;
      cards.push(new RedemptionCard(
        rs.getLong(rs.getColumnIndex('rid')),
        rs.getString(rs.getColumnIndex('title')),
        rs.getString(rs.getColumnIndex('icon')),
        date
      ));
    }
    rs.close();
    return cards;
  }
}

export class StatsDao {
  /** 近 7 天完成率：实际打卡次数 / (启用任务数 × 7)。返回 -1 表示无启用任务。 */
  static async weeklyRate(profileId: number): Promise<number> {
    const since = new Date(Date.now() - 6 * 86400000);
    const m = `${since.getMonth() + 1}`.padStart(2, '0');
    const d = `${since.getDate()}`.padStart(2, '0');
    const sinceStr = `${since.getFullYear()}-${m}-${d}`;

    const store = DatabaseHelper.getStore();
    const tasks = new relationalStore.RdbPredicates('tasks');
    tasks.equalTo('profile_id', profileId).equalTo('active', 1);
    const taskRs = await store.query(tasks, ['id']);
    let taskCount = 0;
    while (taskRs.goToNextRow()) {
      taskCount++;
    }
    taskRs.close();
    if (taskCount === 0) {
      return -1;
    }

    const checkins = new relationalStore.RdbPredicates('checkins');
    checkins.equalTo('profile_id', profileId)
      .greaterThanOrEqualTo('date', sinceStr)
      .equalTo('status', CheckinStatus.DONE);
    const rs = await store.query(checkins, ['id']);
    let done = 0;
    while (rs.goToNextRow()) {
      done++;
    }
    rs.close();
    return done / (taskCount * 7);
  }
}

export class ResetDao {
  /**
   * 重置今日：删除今日打卡记录 + 今日任务类星星流水 + 今日照片（事务，可反复使用）。
   *
   * 注意与「成长时光永久保存」的边界：
   *  · 重置只影响【今天】——历史日期的 photos 行一律不动，成长时光永久保留。
   *  · 今天拍的照片要一并清掉：否则打卡已重置但任务卡仍显示照片角标，状态自相矛盾。
   */
  static async resetToday(profileId: number, date: string): Promise<void> {
    const store = DatabaseHelper.getStore();
    const dayStart = `${date}T00:00:00`;
    const tx = await store.createTransaction({});
    try {
      const checkins = new relationalStore.RdbPredicates('checkins');
      checkins.equalTo('profile_id', profileId).equalTo('date', date);
      await tx.delete(checkins);

      // 今日照片同步清理（历史日期不受影响）
      const photos = new relationalStore.RdbPredicates('photos');
      photos.equalTo('profile_id', profileId).equalTo('date', date);
      await tx.delete(photos);

      const ledger = new relationalStore.RdbPredicates('stars_ledger');
      ledger.equalTo('profile_id', profileId)
        .equalTo('reason_type', 'task')
        .greaterThan('created_at', dayStart);
      await tx.delete(ledger);
      await tx.commit();
    } catch (err) {
      await tx.rollback();
      throw new Error(`resetToday failed: ${String(err)}`);
    }
  }
}

export class BadgeDao {
  /** 已解锁勋章 ID 集合 */
  static async unlockedIds(profileId: number): Promise<Set<string>> {
    const predicates = new relationalStore.RdbPredicates('badges');
    predicates.equalTo('profile_id', profileId);
    const rs = await DatabaseHelper.getStore().query(predicates, ['badge_id']);
    const ids: Set<string> = new Set();
    while (rs.goToNextRow()) {
      ids.add(rs.getString(rs.getColumnIndex('badge_id')));
    }
    rs.close();
    return ids;
  }

  /** 汇总判定所需统计（单次查询各指标） */
  static async stats(profileId: number): Promise<BadgeStats> {
    const store = DatabaseHelper.getStore();
    const today = DatabaseHelper.today();

    const countSql = async (sql: string, args: number[]): Promise<number> => {
      const rs = await store.querySql(sql, args);
      let n = 0;
      if (rs.goToNextRow()) {
        n = rs.getLong(0);
      }
      rs.close();
      return n;
    };

    const totalDone = await countSql('SELECT COUNT(*) FROM checkins WHERE profile_id = ? AND status = 1', [profileId]);
    const streak = await CheckinDao.currentStreak(profileId, today);
    const longest = await CheckinDao.longestStreak(profileId);
    const totalEarned = await countSql(
      'SELECT COALESCE(SUM(delta),0) FROM stars_ledger WHERE profile_id = ? AND delta > 0', [profileId]);
    const balance = await StarDao.balance(profileId);
    const photoCount = await countSql(
      'SELECT COUNT(*) FROM photos WHERE profile_id = ?', [profileId]);
    const redeemCount = await countSql('SELECT COUNT(*) FROM redemptions WHERE profile_id = ?', [profileId]);
    const activeTasks = await countSql('SELECT COUNT(*) FROM tasks WHERE profile_id = ? AND active = 1', [profileId]);
    const daily = await CheckinDao.dailyCounts(profileId, '2000-01-01');
    let bestDayCount = 0;
    daily.forEach((cnt: number) => {
      if (cnt > bestDayCount) {
        bestDayCount = cnt;
      }
    });
    return {
      totalDone: totalDone, streak: streak, longest: longest, totalEarned: totalEarned,
      balance: balance, photoCount: photoCount, redeemCount: redeemCount,
      bestDayCount: bestDayCount, activeTasks: activeTasks
    } as BadgeStats;
  }

  /** 评估并落库新解锁勋章，返回本次新解锁的勋章 ID（成就墙弹出庆祝用） */
  static async evaluate(profileId: number): Promise<string[]> {
    const stats = await BadgeDao.stats(profileId);
    const unlocked = await BadgeDao.unlockedIds(profileId);
    const fresh: string[] = [];
    for (const badge of BADGES) {
      if (!unlocked.has(badge.id) && badge.hit(stats)) {
        await DatabaseHelper.getStore().insert('badges', {
          profile_id: profileId,
          badge_id: badge.id,
          unlocked_at: DatabaseHelper.now()
        } as relationalStore.ValuesBucket);
        fresh.push(badge.id);
      }
    }
    return fresh;
  }
}

export class MilestoneDao {
  /** 当前进度值：streak=当前连续天数，stars=累计获得星星，checkins=累计完成打卡 */
  static async progressOf(kind: string, profileId: number): Promise<number> {
    const store = DatabaseHelper.getStore();
    if (kind === 'streak') {
      return CheckinDao.currentStreak(profileId, DatabaseHelper.today());
    }
    const sql = kind === 'stars'
      ? 'SELECT COALESCE(SUM(delta),0) FROM stars_ledger WHERE profile_id = ? AND delta > 0'
      : 'SELECT COUNT(*) FROM checkins WHERE profile_id = ? AND status = 1';
    const rs = await store.querySql(sql, [profileId]);
    let n = 0;
    if (rs.goToNextRow()) {
      n = rs.getLong(0);
    }
    rs.close();
    return n;
  }

  static async list(profileId: number): Promise<MilestoneItem[]> {
    const predicates = new relationalStore.RdbPredicates('milestones');
    predicates.equalTo('profile_id', profileId).orderByAsc('target').orderByAsc('id');
    const rs = await DatabaseHelper.getStore().query(predicates,
      ['id', 'title', 'icon', 'kind', 'target', 'reward', 'status', 'achieved_at', 'confirmed_at']);
    const list: MilestoneItem[] = [];
    while (rs.goToNextRow()) {
      list.push(new MilestoneItem(
        rs.getLong(rs.getColumnIndex('id')),
        rs.getString(rs.getColumnIndex('title')),
        rs.getString(rs.getColumnIndex('icon')),
        rs.getString(rs.getColumnIndex('kind')),
        rs.getLong(rs.getColumnIndex('target')),
        rs.getString(rs.getColumnIndex('reward')),
        rs.getLong(rs.getColumnIndex('status')),
        rs.getString(rs.getColumnIndex('achieved_at')),
        rs.getString(rs.getColumnIndex('confirmed_at'))
      ));
    }
    rs.close();
    return list;
  }

  static async insert(profileId: number, m: MilestoneItem): Promise<number> {
    return DatabaseHelper.getStore().insert('milestones', {
      profile_id: profileId,
      title: m.title,
      icon: m.icon,
      kind: m.kind,
      target: m.target,
      reward: m.reward,
      status: 0,
      created_at: DatabaseHelper.now()
    } as relationalStore.ValuesBucket);
  }

  /** 评估进行中里程碑：进度达标 → 置为待兑现，返回本次新达成的条目 */
  static async evaluate(profileId: number): Promise<MilestoneItem[]> {
    const all = await MilestoneDao.list(profileId);
    const fresh: MilestoneItem[] = [];
    for (const m of all) {
      if (m.status !== 0) {
        continue;
      }
      const progress = await MilestoneDao.progressOf(m.kind, profileId);
      if (progress >= m.target) {
        const predicates = new relationalStore.RdbPredicates('milestones');
        predicates.equalTo('id', m.id);
        await DatabaseHelper.getStore().update({
          status: 1,
          achieved_at: DatabaseHelper.now()
        } as relationalStore.ValuesBucket, predicates);
        m.status = 1;
        fresh.push(m);
      }
    }
    return fresh;
  }

  /** 家长确认兑现：待兑现 → 已兑现（进纪念墙） */
  static async confirm(profileId: number, id: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('milestones');
    predicates.equalTo('id', id).equalTo('profile_id', profileId);
    await DatabaseHelper.getStore().update({
      status: 2,
      confirmed_at: DatabaseHelper.now()
    } as relationalStore.ValuesBucket, predicates);
  }
}

export class SettingsDao {
  static async get(key: string): Promise<string | null> {
    const predicates = new relationalStore.RdbPredicates('settings');
    predicates.equalTo('key', key);
    const rs = await DatabaseHelper.getStore().query(predicates, ['value']);
    const has = rs.goToNextRow();
    const value = has ? rs.getString(rs.getColumnIndex('value')) : '';
    rs.close();
    return has ? value : null;
  }

  static async set(key: string, value: string): Promise<void> {
    const store = DatabaseHelper.getStore();
    const old = await SettingsDao.get(key);
    if (old === null) {
      await store.insert('settings', { key: key, value: value } as relationalStore.ValuesBucket);
    } else {
      const predicates = new relationalStore.RdbPredicates('settings');
      predicates.equalTo('key', key);
      await store.update({ value: value } as relationalStore.ValuesBucket, predicates);
    }
  }
}

/** icon 刷新迁移用的行结构 */
interface IconUpdate {
  id: number;
  icon: string;
}

/** 时段回填迁移用的行结构 */
interface SlotsUpdate {
  id: number;
  timeSlots: string;
}

export class SeedDao {
  /** 首次启动写入演示数据；已初始化则跳过 */
  static async ensureSeeded(): Promise<void> {
    const store = DatabaseHelper.getStore();
    const predicates = new relationalStore.RdbPredicates('settings');
    predicates.equalTo('key', 'seeded');
    const rs = await store.query(predicates, ['value']);
    const seeded = rs.goToNextRow() && rs.getString(rs.getColumnIndex('value')) === '1';
    rs.close();
    if (seeded) {
      await SeedDao.refreshIcons(); // 已种子的老库：把 emoji 占位刷新为插画路径
      await SeedDao.refreshTimeSlots(); // 已种子的老库：按标题回填适合时段
      return;
    }

    const kidId = SeedData.DEMO_KID_ID;
    const now = DatabaseHelper.now();
    await store.insert('profiles', {
      id: kidId, name: SeedData.DEMO_KID_NAME, role: 0, created_at: now
    } as relationalStore.ValuesBucket);
    await store.insert('settings', { key: 'active_kid', value: `${kidId}` } as relationalStore.ValuesBucket);

    // 演示任务
    let sort = 0;
    for (const t of SeedData.DEMO_TASKS) {
      await TaskDao.insert(kidId, t, sort++);
    }
    // 演示心愿（三档）
    for (const r of SeedData.DEMO_REWARDS) {
      await RewardDao.insert(kidId, r);
    }
    // 演示里程碑（旅行路线三站）
    for (const m of SeedData.DEMO_MILESTONES) {
      await MilestoneDao.insert(kidId, m);
    }
    // 演示星星：昨天赚的 5 颗（让钱包非零，今日从 0 开始）
    const yesterday = new Date(Date.now() - 86400000).toISOString();
    for (const delta of [2, 3]) {
      await store.insert('stars_ledger', {
        profile_id: kidId, delta: delta, reason_type: 'task', ref_id: 0, created_at: yesterday
      } as relationalStore.ValuesBucket);
    }

    await store.insert('settings', { key: 'seeded', value: '1' } as relationalStore.ValuesBucket);
  }

  /** 把库中 emoji 占位 icon 按标题刷新为 rawfile 插画路径（幂等，仅当存在占位时执行一次） */
  private static async refreshIcons(): Promise<void> {
    const store = DatabaseHelper.getStore();
    const kv = new relationalStore.RdbPredicates('settings');
    kv.equalTo('key', 'icon_version');
    const rs = await store.query(kv, ['value']);
    const done = rs.goToNextRow() && rs.getString(rs.getColumnIndex('value')) === '2';
    rs.close();
    if (done) {
      return;
    }
    const mapping: Map<string, string> = new Map();
    for (const t of SeedData.TEMPLATES) {
      mapping.set(t.title, t.icon);
    }
    for (const r of SeedData.DEMO_REWARDS) {
      mapping.set(r.title, r.icon);
    }
    const tasks = new relationalStore.RdbPredicates('tasks');
    const trs = await store.query(tasks, ['id', 'title']);
    const updates: IconUpdate[] = [];
    while (trs.goToNextRow()) {
      const title = trs.getString(trs.getColumnIndex('title'));
      const icon = mapping.get(title);
      if (icon !== undefined && icon.startsWith('raw:')) {
        updates.push({ id: trs.getLong(trs.getColumnIndex('id')), icon: icon } as IconUpdate);
      }
    }
    trs.close();
    for (const u of updates) {
      const p = new relationalStore.RdbPredicates('tasks');
      p.equalTo('id', u.id);
      await store.update({ icon: u.icon } as relationalStore.ValuesBucket, p);
    }
    const rewards = new relationalStore.RdbPredicates('rewards');
    const rrs = await store.query(rewards, ['id', 'title']);
    const rupdates: IconUpdate[] = [];
    while (rrs.goToNextRow()) {
      const title = rrs.getString(rrs.getColumnIndex('title'));
      const icon = mapping.get(title);
      if (icon !== undefined && icon.startsWith('raw:')) {
        rupdates.push({ id: rrs.getLong(rrs.getColumnIndex('id')), icon: icon } as IconUpdate);
      }
    }
    rrs.close();
    for (const u of rupdates) {
      const p = new relationalStore.RdbPredicates('rewards');
      p.equalTo('id', u.id);
      await store.update({ icon: u.icon } as relationalStore.ValuesBucket, p);
    }
    await store.insert('settings', { key: 'icon_version', value: '2' } as relationalStore.ValuesBucket);
  }

  /** 老库回填适合时段：按标题从模板库/演示任务取对应时段（幂等，仅执行一次）。
   *  新增的 time_slots 列默认 '不限'，回填后才有真正的时段推荐效果。 */
  private static async refreshTimeSlots(): Promise<void> {
    const store = DatabaseHelper.getStore();
    const kv = new relationalStore.RdbPredicates('settings');
    kv.equalTo('key', 'slots_version');
    const rs = await store.query(kv, ['value']);
    const done = rs.goToNextRow() && rs.getString(rs.getColumnIndex('value')) === '1';
    rs.close();
    if (done) {
      return;
    }
    // 标题 → 时段映射：模板库优先，演示任务补齐
    const mapping: Map<string, string> = new Map<string, string>();
    for (const t of SeedData.TEMPLATES) {
      mapping.set(t.title, t.timeSlots);
    }
    for (const t of SeedData.DEMO_TASKS) {
      if (!mapping.has(t.title)) {
        mapping.set(t.title, t.timeSlots);
      }
    }
    const tasks = new relationalStore.RdbPredicates('tasks');
    const trs = await store.query(tasks, ['id', 'title', 'time_slots']);
    const updates: SlotsUpdate[] = [];
    while (trs.goToNextRow()) {
      const title = trs.getString(trs.getColumnIndex('title'));
      const slots = mapping.get(title);
      // 仅回填仍为默认值 '不限' 的行，避免覆盖家长改过的设置
      if (slots !== undefined && trs.getString(trs.getColumnIndex('time_slots')) === '不限') {
        updates.push({ id: trs.getLong(trs.getColumnIndex('id')), timeSlots: slots } as SlotsUpdate);
      }
    }
    trs.close();
    for (const u of updates) {
      const p = new relationalStore.RdbPredicates('tasks');
      p.equalTo('id', u.id);
      await store.update({ time_slots: u.timeSlots } as relationalStore.ValuesBucket, p);
    }
    await store.insert('settings', { key: 'slots_version', value: '1' } as relationalStore.ValuesBucket);
  }
}
