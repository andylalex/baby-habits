let storageCard = new LocalStorage();

/**
 * 桌面卡片「今日打卡」：星星余额 + 剩余任务数，点一下直达打卡页。
 * 数据由 CardUpdater.refresh 推送（balance / remaining）。
 */
@Entry(storageCard)
@Component
struct TodayCard {
  @LocalStorageProp('balance') balance: string = '0';
  @LocalStorageProp('remaining') remaining: string = '0';

  build() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text('🫙')
          .fontSize(18)
        Text(this.balance)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#4A3B2A')
      }
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor('#E3F0FF')
      .borderRadius(999)

      Text(this.remaining === '0' ? '🎉 全部完成！' : `还剩 ${this.remaining} 个任务`)
        .fontSize(14)
        .fontColor('#4A3B2A')

      Text('去打卡 →')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor('#E8641F')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#FFF8EC')
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { url: 'pages/Index' }
      });
    })
  }
}
