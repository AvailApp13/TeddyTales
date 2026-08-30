// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String ageDays(int count) {
    return '$count天';
  }

  @override
  String ageMonths(int count) {
    return '$count个月';
  }

  @override
  String ageMonthsDays(int months, int days) {
    return '$months个月$days天';
  }

  @override
  String ageYears(int count) {
    return '$count岁';
  }

  @override
  String get appTitle => 'TeddyTales';

  @override
  String bearRigMissingHint(String path) {
    return '请将 $path 放入应用';
  }

  @override
  String get bearRigMissingTitle => '骨骼动画还没接入';

  @override
  String get birthCueAwakening => '小家伙睁开眼睛，四处张望。';

  @override
  String get birthCueCradle => '温暖的小床。被子下有人在轻轻呼吸……';

  @override
  String get birthCueFinale => '他安静下来了。你好呀，小家伙。';

  @override
  String get birthCueFirstBreath => '第一次呼吸……';

  @override
  String get birthCueFirstCry => '第一声啼哭——他在呼唤你。';

  @override
  String get birthCueStars => '小星星在柔和的光里飘着。';

  @override
  String get birthSceneNotReady => '出生场景尚未完成';

  @override
  String get birthSkip => '跳过';

  @override
  String get careFeedSubtitle => '给小家伙的美味';

  @override
  String get careFeedTitle => '喂饭';

  @override
  String get careFootnote => '列表里没有抚摸：按技术规范 8.1，它是触屏动作——在主界面轻点小熊即可。';

  @override
  String careLockedUntilStage(int stage) {
    return '将在第 $stage 阶段解锁';
  }

  @override
  String get carePlaySubtitle => '一起开心玩游戏';

  @override
  String get carePlayTitle => '玩耍';

  @override
  String get careSleepSubtitle => '晚安，小家伙';

  @override
  String get careSleepTitle => '哄睡';

  @override
  String get careTitle => '我们做点什么？';

  @override
  String get careWashSubtitle => '该进浴缸啦！';

  @override
  String get careWashTitle => '洗澡';

  @override
  String get catalogCheckoutTitle => '填写订单';

  @override
  String get catalogCountryChina => '中国';

  @override
  String get catalogCountryGermany => '德国';

  @override
  String get catalogCountryKazakhstan => '哈萨克斯坦';

  @override
  String get catalogCountryRussia => '俄罗斯';

  @override
  String get catalogCountryUsa => '美国';

  @override
  String get catalogDeliveryNote =>
      '按商店数据配送：美国 7–9 个工作日，加拿大 8–10，欧洲 9–11，亚洲 5–7。订单将进入客户现有的销售系统（需求 12.5）——此表单暂不提交。';

  @override
  String get catalogFieldAddress => '地址';

  @override
  String get catalogFieldAddressHint => '街道、门牌、房号';

  @override
  String get catalogFieldCountry => '国家/地区';

  @override
  String get catalogFieldName => '姓名';

  @override
  String get catalogFieldNameHint => '与证件一致';

  @override
  String get catalogFieldPhone => '电话';

  @override
  String get catalogFieldPostcode => '邮政编码';

  @override
  String catalogFootnote(String shoes, String price) {
    return '商品、价格与尺寸均来自 TeddyTales® 官方商店（需求 12.1）。图片暂为同一张占位图：正式照片将来自客户的商品目录。鞋子在商店单独出售——$shoes，$price。';
  }

  @override
  String get catalogGrownSubtitle => '准备好去你家啦';

  @override
  String get catalogGrownTitle => '你的小家伙长大了';

  @override
  String get catalogItemFortune => '口袋幸运小熊';

  @override
  String get catalogItemHug => '蜜桃抱抱熊';

  @override
  String get catalogItemShortFur => '短绒小熊';

  @override
  String get catalogItemSpaceSet => '宇航员与新娘套装';

  @override
  String get catalogOrderButton => '立即下单';

  @override
  String get catalogPayPalNote => '——也可免账户用银行卡支付';

  @override
  String get catalogPaySection => '支付 · 需求 12.4';

  @override
  String get catalogPayStub => '支付将在系统对接阶段开通';

  @override
  String catalogSizeCm(int size) {
    return '$size 厘米';
  }

  @override
  String get catalogSummaryItem => '商品';

  @override
  String get catalogSummaryPrice => '价格';

  @override
  String get catalogSummarySize => '尺寸';

  @override
  String get catalogTitle => '订购小熊';

  @override
  String get categoryAccessory => '配饰';

  @override
  String get categoryBottom => '下装';

  @override
  String get categoryDecor => '装饰';

  @override
  String get categoryFloor => '地板';

  @override
  String get categoryFurniture => '家具';

  @override
  String get categoryHeadwear => '帽饰';

  @override
  String get categoryOutfit => '套装';

  @override
  String get categoryShoes => '鞋子';

  @override
  String get categoryTop => '上装';

  @override
  String get categoryToy => '玩具';

  @override
  String get categoryWallpaper => '壁纸';

  @override
  String get commonBack => '返回';

  @override
  String commonCoins(int count) {
    return '$count 金币';
  }

  @override
  String get diaryEventFavoriteToy => '心爱的玩具';

  @override
  String get diaryEventFirstBath => '第一次洗澡';

  @override
  String get diaryEventFirstCrawl => '学会了爬';

  @override
  String get diaryEventFirstTooth => '第一颗小牙';

  @override
  String get diaryFootnote =>
      '日记不在 КП 中，源自设计稿，归入第二版，目前只是雏形。相册和分享功能需要相机及拍摄权限。事件缩略图为占位：真正的照片将随相册一起上线。';

  @override
  String get diaryTitle => '日记';

  @override
  String get dishCookie => '饼干';

  @override
  String get dishFruit => '水果';

  @override
  String get dishOmelette => '煎蛋卷';

  @override
  String get dishPasta => '意面';

  @override
  String get dishPie => '派';

  @override
  String get dishPorridge => '麦片粥';

  @override
  String get dishSalad => '沙拉';

  @override
  String get dishSandwich => '三明治';

  @override
  String get dishSoup => '汤';

  @override
  String get dishYogurt => '酸奶';

  @override
  String get feedCookHint => '按顺序加入食材。放错了也没关系，再试一次就好。';

  @override
  String feedCookResult(String recipe, int reward, int gain) {
    return '做好啦！$recipe · +$reward 金币，食物 +$gain';
  }

  @override
  String get feedDishesNote =>
      '按需求 8.2 共 10 道菜。价格与数值为占位值，按需求 10.9 另行确定并由服务器配置。';

  @override
  String feedEatResult(String dish, int gain, int price) {
    return '$dish · 食物 +$gain，−$price 金币';
  }

  @override
  String get feedFavourite => '最爱';

  @override
  String feedFoodGain(int gain) {
    return '食物 +$gain';
  }

  @override
  String get feedHintActive => '我今天跑了一整天，来点顶饱的吧！';

  @override
  String get feedHintAffectionate => '想吃点甜的……还要你陪着我。';

  @override
  String get feedHintCalm => '来点温暖简单的就好。';

  @override
  String get feedHintCurious => '我们做点新花样好不好？';

  @override
  String get feedHintIndependent => '我自己也行的。嗯……差不多行。';

  @override
  String get feedHintReserved => '就吃点水果，可以吗？';

  @override
  String get feedNotEnoughCoins => '金币不够';

  @override
  String feedRecipeSteps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 步',
    );
    return '$_temp0';
  }

  @override
  String get feedRecipesNote => '按需求 8.5 共 5 个食谱：饼干和三明治各 3 步，其余 4 到 6 步。';

  @override
  String feedStepProgress(int step, int total, int reward, int gain) {
    return '第 $step 步，共 $total 步。奖励：$reward 金币，食物 +$gain。';
  }

  @override
  String get feedTabCook => '动手做';

  @override
  String get feedTabReady => '现成美食';

  @override
  String get feedTitle => '吃点什么好呢？';

  @override
  String feedWrongStep(String ingredient) {
    return '不对哦。现在需要：$ingredient。再试一次，没有惩罚。';
  }

  @override
  String game2048Hint(int target, int score) {
    return '滑动屏幕，相同的方块会合并。目标：$target。得分：$score';
  }

  @override
  String get game2048StuckHint => '没有可走的步了——点下方按钮重新开始。';

  @override
  String game2048Title(int level) {
    return '2048 · 第$level关';
  }

  @override
  String game2048WonHint(int target) {
    return '达到$target了！领取奖励吧 🎉';
  }

  @override
  String gamePairsHint(int moves) {
    return '翻开两张相同的卡片。步数：$moves';
  }

  @override
  String gamePairsSolvedHint(int moves) {
    String _temp0 = intl.Intl.pluralLogic(
      moves,
      locale: localeName,
      other: '用$moves步找齐所有配对 🎉',
    );
    return '$_temp0';
  }

  @override
  String gamePairsTitle(int level) {
    return '记忆翻牌 · 第$level关';
  }

  @override
  String get gamePuzzleHint => '点按滑动拼块，拼出完整照片。';

  @override
  String get gamePuzzleSolvedHint => '拼好了！领取奖励吧 🎉';

  @override
  String gamePuzzleTitle(int level) {
    return '拼图 · 第$level关';
  }

  @override
  String get gameRestart => '重新开始';

  @override
  String get growthAlreadyAdult => '小熊已经长大了';

  @override
  String get growthDurationAdult => '之后不再受限';

  @override
  String get growthDurationCrawling => '约 2 天';

  @override
  String get growthDurationFirstSteps => '1–2 天';

  @override
  String get growthDurationGrowing => '到第 14 天左右';

  @override
  String get growthDurationNewborn => '1 天';

  @override
  String get growthFootnote =>
      '名称与时长取自 КП 5。设计稿里的写法不同（宝宝、幼崽，以月而非天计）——这一差异仍是待定问题。';

  @override
  String get growthGrowUp => '长大一步';

  @override
  String get growthMarkNow => '当前';

  @override
  String get growthMarkPassed => '已完成';

  @override
  String growthNewStage(String stage) {
    return '新阶段：$stage';
  }

  @override
  String get growthTitle => '成长与发育';

  @override
  String get homeCareButton => '我们做点什么呢？';

  @override
  String get homeDevPanelTooltip => '骨骼调试面板';

  @override
  String homeScreenNotReady(String name) {
    return '“$name”页面还没准备好';
  }

  @override
  String get ingredientApple => '苹果';

  @override
  String get ingredientBanana => '香蕉';

  @override
  String get ingredientBread => '面包';

  @override
  String get ingredientButter => '黄油';

  @override
  String get ingredientCabbage => '卷心菜';

  @override
  String get ingredientCandy => '糖果';

  @override
  String get ingredientCarrot => '胡萝卜';

  @override
  String get ingredientCheese => '奶酪';

  @override
  String get ingredientChocolate => '巧克力';

  @override
  String get ingredientFish => '鱼';

  @override
  String get ingredientFlour => '面粉';

  @override
  String get ingredientGreens => '香草';

  @override
  String get ingredientHoney => '蜂蜜';

  @override
  String get ingredientMeat => '肉';

  @override
  String get ingredientOnion => '洋葱';

  @override
  String get ingredientOrange => '橙子';

  @override
  String get ingredientPepper => '辣椒';

  @override
  String get ingredientPotato => '土豆';

  @override
  String get ingredientSalt => '盐';

  @override
  String get ingredientSpices => '香料';

  @override
  String get ingredientSugar => '糖';

  @override
  String get ingredientTomato => '番茄';

  @override
  String get ingredientYogurt => '酸奶';

  @override
  String get itemAccBow => '蝴蝶结';

  @override
  String get itemArmchair => '扶手椅';

  @override
  String get itemBall => '小皮球';

  @override
  String get itemBasket => '篮子';

  @override
  String get itemBed => '小床';

  @override
  String get itemBotBlue => '蓝色长裤';

  @override
  String get itemBotSkirt => '粉色短裙';

  @override
  String get itemBotYellow => '黄色短裤';

  @override
  String get itemCactus => '仙人掌';

  @override
  String get itemCar => '小汽车';

  @override
  String get itemChair => '椅子';

  @override
  String get itemClock => '挂钟';

  @override
  String get itemCubes => '积木';

  @override
  String get itemDresser => '斗柜';

  @override
  String get itemDrum => '小鼓';

  @override
  String get itemDuck => '小鸭子';

  @override
  String get itemFloorCarpet => '地毯地板';

  @override
  String get itemFloorLight => '浅色地板';

  @override
  String get itemFloorWood => '木地板';

  @override
  String get itemGarland => '彩灯串';

  @override
  String get itemHatCap => '帽子';

  @override
  String get itemKite => '风筝';

  @override
  String get itemLamp => '台灯';

  @override
  String get itemOutBear => '小熊装';

  @override
  String get itemOutBee => '蜜蜂装';

  @override
  String get itemOutBerry => '草莓装';

  @override
  String get itemOutGlasses => '眼镜套装';

  @override
  String get itemOutSailor => '水手套装';

  @override
  String get itemOutSport => '运动套装';

  @override
  String get itemOutWinter => '冬日套装';

  @override
  String get itemOutYellow => '黄色套装';

  @override
  String get itemPicBear => '小熊挂画';

  @override
  String get itemPicForest => '森林挂画';

  @override
  String get itemPicMoon => '月亮挂画';

  @override
  String get itemPillowHeart => '爱心抱枕';

  @override
  String get itemPillowStar => '星星抱枕';

  @override
  String get itemPlant => '绿植';

  @override
  String get itemPoster => '海报';

  @override
  String get itemPuzzle => '拼图';

  @override
  String get itemRocket => '火箭';

  @override
  String get itemRug => '地毯';

  @override
  String get itemShelf => '书架';

  @override
  String get itemTable => '桌子';

  @override
  String get itemTeddy => '泰迪熊';

  @override
  String get itemTopBlue => '蓝色连帽衫';

  @override
  String get itemTopRose => '粉色毛衣';

  @override
  String get itemTopSage => '绿色开衫';

  @override
  String get itemTrain => '小火车';

  @override
  String get itemWallRose => '粉色壁纸';

  @override
  String get itemWallSage => '绿色壁纸';

  @override
  String get itemWallSky => '天空壁纸';

  @override
  String get itemWardrobe => '衣柜';

  @override
  String get learnAdultLevelsNote => '通关即得金币，并解锁下一关。关卡越高，难度越大。';

  @override
  String get learnAdultLogicSubtitle => '品牌配色的2048';

  @override
  String get learnAdultLogicTitle => '益智游戏';

  @override
  String get learnAdultMemorySubtitle => '找出相同的一对';

  @override
  String get learnAdultMemoryTitle => '记忆翻牌';

  @override
  String get learnAdultPuzzleSubtitle => '拼出小熊的照片';

  @override
  String get learnAdultPuzzleTitle => '拼图';

  @override
  String get learnAgeAdultSubtitle => '小熊拼图、2048、记忆翻牌';

  @override
  String get learnAgeAdultTitle => '成人';

  @override
  String get learnAgeChildSubtitle => '颜色与形状、数数、认识世界';

  @override
  String learnAgeChildTitle(int age) {
    return '$age岁以下儿童';
  }

  @override
  String get learnAgeGateSubtitle => '游戏内容因年龄而异，随时可以更改。';

  @override
  String get learnAgeGateTitle => '谁来玩？';

  @override
  String get learnCatColorsTitle => '颜色与形状';

  @override
  String get learnCatCountTitle => '数数与简单逻辑';

  @override
  String get learnCatWorldTitle => '认识世界';

  @override
  String learnCorrectToast(int coins) {
    String _temp0 = intl.Intl.pluralLogic(
      coins,
      locale: localeName,
      other: '答对了！+$coins金币',
    );
    return '$_temp0';
  }

  @override
  String get learnGamesTitle => '游戏';

  @override
  String learnLevelDoneToast(int coins) {
    String _temp0 = intl.Intl.pluralLogic(
      coins,
      locale: localeName,
      other: '通关啦！+$coins金币',
    );
    return '$_temp0';
  }

  @override
  String learnLevelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个关卡',
    );
    return '$_temp0';
  }

  @override
  String get learnLevelsNote =>
      '每个类别10关(规格9.2)。引擎可容纳300道题，内容由客户通过管理面板提供(规格9.4)——目前每个类别有三道示例题。';

  @override
  String get learnQuizHintNote => '答对了会有开心动画和奖励。';

  @override
  String learnQuizTitle(String category, int level) {
    return '$category · 第$level关';
  }

  @override
  String get learnQuizWrongNote => '没答对。再试一次吧——不扣分(规格9.3)。';

  @override
  String get learnTaskColorsCircle => '圆形在哪里？';

  @override
  String get learnTaskColorsGreen => '绿色在哪里？';

  @override
  String get learnTaskColorsRed => '红色在哪里？';

  @override
  String get learnTaskCountApples => '有几个苹果？🍎🍎🍎';

  @override
  String get learnTaskCountBigger => '哪个更大？';

  @override
  String get learnTaskCountNext => '接下来是什么？1、2、3……';

  @override
  String get learnTaskWorldApples => '苹果长在哪里？';

  @override
  String get learnTaskWorldDay => '白天什么在发光？';

  @override
  String get learnTaskWorldWater => '谁住在水里？';

  @override
  String get learnTitle => '学习';

  @override
  String get moodDirty => '脏兮兮';

  @override
  String get moodHappy => '开心';

  @override
  String get moodHungry => '饿了';

  @override
  String get moodNormal => '平静';

  @override
  String get moodSad => '难过';

  @override
  String get moodSleepy => '困了';

  @override
  String navLockReason(String stage) {
    return '到“$stage”阶段解锁';
  }

  @override
  String get navSectionCatalog => '小熊';

  @override
  String get navSectionHome => '首页';

  @override
  String get navSectionLearning => '学习';

  @override
  String get navSectionProfile => '我的';

  @override
  String get navSectionRoom => '房间';

  @override
  String get navSectionShop => '商店';

  @override
  String get petDefaultName => '我的宝贝';

  @override
  String get profileAgeLabel => '年龄';

  @override
  String profileBirthFur(String hero, String fur) {
    return '$hero · 毛色 $fur';
  }

  @override
  String get profileFootnote =>
      '身高、体重和星座目前是占位数据：出生时由服务器生成（КП 2.2、2.5），星座性格对照表由客户方提供。';

  @override
  String get profileHeightLabel => '身高';

  @override
  String get profileHeightStub => '15 厘米';

  @override
  String get profileLinkDiary => '日记';

  @override
  String get profileLinkDiarySubtitle => '大事记与相册';

  @override
  String get profileLinkGrowth => '成长与发育';

  @override
  String get profileLinkGrowthSubtitle => '五个阶段及其变化';

  @override
  String get profileLinkSettings => '设置';

  @override
  String get profileLinkSettingsSubtitle => '语言与通知';

  @override
  String get profileSectionBirth => '出生卡 · КП 2.2';

  @override
  String get profileSectionHistory => '成长阶段记录 · КП 14.1';

  @override
  String get profileSectionLinks => '更多';

  @override
  String get profileSectionTrait => '性格 · КП 7';

  @override
  String get profileSexBoy => '男孩';

  @override
  String get profileSexGirl => '女孩';

  @override
  String get profileSexLabel => '性别';

  @override
  String get profileStageNow => '当前';

  @override
  String get profileStagePassed => '已完成';

  @override
  String get profileStubBadge => '占位';

  @override
  String get profileTitle => '档案';

  @override
  String get profileTraitHowLabel => '计算方式';

  @override
  String get profileTraitHowValue => '根据最近 3 天的互动';

  @override
  String get profileTraitNowLabel => '当前';

  @override
  String get profileWeightLabel => '体重';

  @override
  String get profileWeightStub => '180 克';

  @override
  String get profileZodiacLabel => '星座';

  @override
  String get recipeCookie => '饼干';

  @override
  String get recipeFruitSalad => '水果沙拉';

  @override
  String get recipeMeat => '肉食料理';

  @override
  String get recipeSandwich => '三明治';

  @override
  String get recipeVeggie => '蔬菜料理';

  @override
  String get roomFooterNote =>
      '需求第 10 节共 52 件物品：家具 10、装饰 16、玩具 10、服装 16。摆放网格和房间预览是下一步，目前物品只是简单地摆放或收起。';

  @override
  String roomItemBought(String name) {
    return '已购买「$name」';
  }

  @override
  String roomItemPlaced(String name) {
    return '已摆放「$name」';
  }

  @override
  String roomItemRemoved(String name) {
    return '已收起「$name」';
  }

  @override
  String get roomNotEnoughCoins => '金币不够';

  @override
  String get roomOwnedLabel => '已拥有';

  @override
  String get roomSelectedLabel => '已选择';

  @override
  String get roomTitle => '我的房间';

  @override
  String get settingsFootnote =>
      '八种通知类型依据 КП 13.1，免打扰时段与频率限制依据 13.2。账号绑定和法律文件（КП 14.2）将随后端一起推出。';

  @override
  String get settingsNotifEvent => '活动';

  @override
  String get settingsNotifGift => '礼物';

  @override
  String get settingsNotifHungry => '饿了';

  @override
  String get settingsNotifPlay => '想玩耍';

  @override
  String get settingsNotifShopNews => '商店上新';

  @override
  String get settingsNotifSleep => '该睡觉了';

  @override
  String get settingsNotifStage => '新阶段';

  @override
  String get settingsNotifTask => '任务';

  @override
  String get settingsQuietHours => '免打扰时段 22:00 — 8:00';

  @override
  String get settingsSectionLanguage => '语言 · КП 16.1';

  @override
  String get settingsSectionNotifications => '通知 · КП 13.1、13.2';

  @override
  String get settingsTitle => '设置';

  @override
  String shopBuyFor(int total) {
    return '花 $total 购买';
  }

  @override
  String get shopCartDisclaimer =>
      '购物车不在需求文档里——它来自设计稿，属于第二版内容，这里先做出来是为了展示购买流程。价格为占位数据（需求 10.9）。';

  @override
  String get shopCartEmpty => '购物车是空的';

  @override
  String shopCheckoutDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已购买$count件物品',
    );
    return '$_temp0';
  }

  @override
  String get shopNotEnoughCoins => '金币不够';

  @override
  String get shopOwnedLabel => '已拥有';

  @override
  String get shopTabClothes => '服装';

  @override
  String get shopTabDecor => '装饰';

  @override
  String get shopTabFurniture => '家具';

  @override
  String get shopTabToys => '玩具';

  @override
  String get shopTitle => '商店';

  @override
  String get skinJoy => 'JOY';

  @override
  String get skinSlow => 'SLOW';

  @override
  String get stageAdult => '成年';

  @override
  String get stageCrawling => '爬行宝宝';

  @override
  String get stageFirstSteps => '蹒跚学步';

  @override
  String get stageGrowing => '成长期';

  @override
  String get stageNewborn => '新生';

  @override
  String get statsFood => '食物';

  @override
  String get statsHygiene => '卫生';

  @override
  String get statsLove => '关爱';

  @override
  String get statsPlay => '玩耍';

  @override
  String get statsSleep => '睡眠';

  @override
  String get traitActive => '活泼';

  @override
  String get traitAffectionate => '亲昵';

  @override
  String get traitCalm => '文静';

  @override
  String get traitCurious => '好奇';

  @override
  String get traitIndependent => '独立';

  @override
  String get traitReserved => '内敛';

  @override
  String get zodiacAquarius => '水瓶座';

  @override
  String get zodiacAries => '白羊座';

  @override
  String get zodiacCancer => '巨蟹座';

  @override
  String get zodiacCapricorn => '摩羯座';

  @override
  String get zodiacGemini => '双子座';

  @override
  String get zodiacInfluenceAquarius => '爱奇思妙想的小自由派：总能带来惊喜，走自己的路。';

  @override
  String get zodiacInfluenceAries => '勇敢又急性子：从第一天起就什么都想自己试试。';

  @override
  String get zodiacInfluenceCancer => '温柔的小宅熊：在关爱和长长的拥抱里最快乐。';

  @override
  String get zodiacInfluenceCapricorn => '耐心又执着：一小步一小步走向大目标。';

  @override
  String get zodiacInfluenceGemini => '好奇又爱交流：对新鲜事物两只爪子一起扑上去。';

  @override
  String get zodiacInfluenceLeo => '热情又有表演欲：喜欢被关注，也会加倍撒娇回应你。';

  @override
  String get zodiacInfluenceLibra => '友善的小和事佬：喜欢美好的事物、陪伴和温柔的语气。';

  @override
  String get zodiacInfluencePisces => '爱做梦又敏感：能悄悄读懂你的心情。';

  @override
  String get zodiacInfluenceSagittarius => '快乐的小冒险家：游戏和出门撒欢是他的最爱。';

  @override
  String get zodiacInfluenceScorpio => '深情又专一：一旦认定你，就是认真而长久的感情。';

  @override
  String get zodiacInfluenceTaurus => '沉稳踏实：喜欢舒适、美食和自己的小节奏。';

  @override
  String get zodiacInfluenceVirgo => '细心又爱整洁：留意小细节，喜欢一切井井有条。';

  @override
  String get zodiacLeo => '狮子座';

  @override
  String get zodiacLibra => '天秤座';

  @override
  String get zodiacPisces => '双鱼座';

  @override
  String get zodiacSagittarius => '射手座';

  @override
  String get zodiacScorpio => '天蝎座';

  @override
  String get zodiacTaurus => '金牛座';

  @override
  String get zodiacVirgo => '处女座';
}
