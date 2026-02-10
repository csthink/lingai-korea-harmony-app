/**
 * 学习地图内容组件
 * 包含: 分段选择器(TOPIK I/II/必备单词), 关卡地图路径
 * 适配 ArkTS 严格模式
 */
import router from '@ohos.router';
import { COLORS, TOPIK_LEVELS, WORDS_PER_LESSON } from '../utils/Constants';
import preferences from '@ohos.data.preferences';
import { themeManager } from '../utils/ThemeManager';

// 关卡状态枚举
export enum LevelStatus {
  LOCKED,
  CURRENT,
  COMPLETED
}

// 关卡节点数据
export class LevelNodeData {
  id: number = 0;
  status: LevelStatus = LevelStatus.LOCKED;
  stars: number = 0;  // 0-3 颗星
  posX: number = 0;   // 节点X位置百分比
  posY: number = 0;   // 节点Y位置

  constructor(id: number, status: LevelStatus, stars: number = 0) {
    this.id = id;
    this.status = status;
    this.stars = stars;
  }
}

@Component
export struct StudyContent {
  @State selectedTabIndex: number = 0;  // 0: TOPIK I, 1: TOPIK II, 2: 必备单词
  @State currentLevel: number = 1;
  @State levels: LevelNodeData[] = [];
  @State wordsPerLesson: number = WORDS_PER_LESSON;
  @State breathScale: number = 1.0;  // 第1层波纹缩放
  @State breathOpacity: number = 0.6;  // 第1层波纹透明度
  @State ripple2Scale: number = 1.0;  // 第2层波纹缩放
  @State ripple2Opacity: number = 0.4;  // 第2层波纹透明度
  @State ripple3Scale: number = 1.0;  // 第3层波纹缩放
  @State ripple3Opacity: number = 0.2;  // 第3层波纹透明度
  @State themeVersion: number = 0;

  private readonly WORD_COUNTS: Map<number, number> = new Map([
    [1, 1559],  // TOPIK I
    [2, 3764],  // TOPIK II
    [0, 1203],  // 常考单词
  ]);
  private breathTimer: number = -1;
  private ripplePhase: number = 0;  // 波纹相位
  private unsubscribeTheme: (() => void) | null = null;

  async aboutToAppear() {
    if (this.unsubscribeTheme === null) {
      this.unsubscribeTheme = themeManager.subscribe(() => {
        this.themeVersion++;
      });
    }

    try {
      const context = getContext(this);
      const pref = await preferences.getPreferences(context, 'user_settings');
      this.wordsPerLesson = await pref.get('wordsPerLesson', WORDS_PER_LESSON) as number;
    } catch (e) {
      this.wordsPerLesson = WORDS_PER_LESSON;
    }
    this.loadLevels();
    this.startRippleAnimation();
  }

  aboutToDisappear() {
    if (this.breathTimer !== -1) {
      clearInterval(this.breathTimer);
    }
    if (this.unsubscribeTheme !== null) {
      this.unsubscribeTheme();
      this.unsubscribeTheme = null;
    }
  }

  startRippleAnimation() {
    // 水波纹向外扩散动画：3层波纹循环扩散
    this.breathTimer = setInterval(() => {
      this.ripplePhase += 0.025;  // 降低速度，更柔和的扩散节奏

      // 第1层波纹 - 最内层，先扩散
      const phase1 = this.ripplePhase % 1;
      this.breathScale = 1.0 + phase1 * 0.25;  // 1.0 -> 1.25
      this.breathOpacity = 0.6 * (1 - phase1);  // 0.6 -> 0

      // 第2层波纹 - 中层，延迟0.33个周期
      const phase2 = (this.ripplePhase + 0.67) % 1;
      this.ripple2Scale = 1.0 + phase2 * 0.25;
      this.ripple2Opacity = 0.4 * (1 - phase2);

      // 第3层波纹 - 外层，延迟0.67个周期
      const phase3 = (this.ripplePhase + 0.33) % 1;
      this.ripple3Scale = 1.0 + phase3 * 0.25;
      this.ripple3Opacity = 0.3 * (1 - phase3);
    }, 60);  // 增加间隔时间
  }

  loadLevels() {
    // 根据当前选择的Tab获取level值
    const levelValues = [1, 2, 0];  // TOPIK I, TOPIK II, 常考单词
    this.currentLevel = levelValues[this.selectedTabIndex];

    const wordCount = this.WORD_COUNTS.get(this.currentLevel) || 1559;
    const lessonCount = Math.ceil(wordCount / this.wordsPerLesson);

    // 生成关卡节点，模拟蛇形路径
    const newLevels: LevelNodeData[] = [];
    for (let i = 1; i <= Math.min(lessonCount, 10); i++) {  // 显示前10关
      const node = new LevelNodeData(i, LevelStatus.LOCKED, 0);

      // 模拟进度：前3关已完成，第4关当前，其他锁定
      if (i < 4) {
        node.status = LevelStatus.COMPLETED;
        node.stars = 3;
      } else if (i === 4) {
        node.status = LevelStatus.CURRENT;
        node.stars = 2;
      }

      newLevels.push(node);
    }
    this.levels = newLevels;
  }

  build() {
    Column() {
      // 分段选择器
      this.TabSelector()

      // 关卡地图
      this.LevelMap()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BACKGROUND)
  }

  @Builder
  TabSelector() {
    Stack() {
      // 滑块指示器（底层）
      Row()
        .width('33%')
        .height('100%')
        .backgroundColor(COLORS.PRIMARY)
        .borderRadius(16)
        .shadow({ radius: 15, color: 'rgba(99, 102, 241, 0.3)', offsetY: 4 })
        .margin({ left: this.getSliderMargin() })
        .animation({ duration: 300, curve: Curve.EaseOut })

      // Tab文字（上层）
      Row() {
        ForEach(['TOPIK I', 'TOPIK II', '必备单词'], (tab: string, index: number) => {
          Text(tab)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.selectedTabIndex === index ? '#ffffff' : COLORS.TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              this.selectedTabIndex = index;
              this.loadLevels();
            })
        })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height(44)
    .padding(4)
    .margin({ left: 20, right: 20, top: 44, bottom: 30 })
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(20)
    .border({ width: 1, color: 'rgba(0,0,0,0.06)' })
    .shadow({ radius: 12, color: 'rgba(148,163,184,0.15)', offsetY: 4 })
    .alignContent(Alignment.Start)
  }

  // 计算滑块左边距
  getSliderMargin(): Length {
    // 每个Tab占33%，根据选中的index计算margin
    const margins: Length[] = [0, '33%', '66%'];
    return margins[this.selectedTabIndex];
  }

  // 预定义的蜿蜒X位置百分比（增大差异以增加蜿蜒弧度）
  private readonly NODE_POSITIONS: number[] = [0.12, 0.85, 0.3, 0.7, 0.15, 0.8, 0.25, 0.75, 0.2, 0.85];

  getNodeXPosition(index: number): number {
    return this.NODE_POSITIONS[index % this.NODE_POSITIONS.length];
  }

  @Builder
  LevelMap() {
    Scroll() {
      Column({ space: 0 }) {
        // 反转顺序：从上往下显示锁定→当前→完成
        // 使用索引直接计算而不是const
        ForEach(this.levels.slice().reverse(), (level: LevelNodeData, reverseIndex: number) => {
          Column() {
            // 连接线（第一个节点上方不需要）
            if (reverseIndex > 0) {
              this.ConnectionLine(this.levels.length - 1 - reverseIndex)
            }

            // 节点 - 使用计算的原始索引
            Row() {
              Blank().layoutWeight(this.getNodeXPosition(this.levels.length - 1 - reverseIndex))
              this.LevelNode(level)
              Blank().layoutWeight(1 - this.getNodeXPosition(this.levels.length - 1 - reverseIndex))
            }
            .width('100%')
          }
        })
      }
      .width('100%')
      .padding({ left: 30, right: 30, top: 30, bottom: 120 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  // 辅助方法：计算插值位置（让路径端点恰好接触节点边缘，不进入内部）
  getInterpolatedX(index: number, step: number): number {
    const currentX = this.getNodeXPosition(index);
    const prevX = this.getNodeXPosition(index + 1);
    // 路径从15%到85%之间插值，让端点恰好接触节点边缘
    const tMin = 0.12;   // 起始偏移
    const tMax = 0.88;   // 结束偏移
    const t = tMin + (tMax - tMin) * (step / 6);
    return prevX + (currentX - prevX) * t;
  }

  @Builder
  ConnectionLine(index: number) {
    // 曲线虚线连接节点，使用椭圆形脚印（7个点延伸到节点中心）
    Column({ space: 5 }) {
      Row() {
        Blank().layoutWeight(this.getInterpolatedX(index, 0))
        Ellipse().width(12).height(7).fill('#94a3b8')
        Blank().layoutWeight(1 - this.getInterpolatedX(index, 0))
      }.width('100%')

      Row() {
        Blank().layoutWeight(this.getInterpolatedX(index, 1))
        Ellipse().width(12).height(7).fill('#94a3b8')
        Blank().layoutWeight(1 - this.getInterpolatedX(index, 1))
      }.width('100%')

      Row() {
        Blank().layoutWeight(this.getInterpolatedX(index, 2))
        Ellipse().width(11).height(6).fill('#94a3b8')
        Blank().layoutWeight(1 - this.getInterpolatedX(index, 2))
      }.width('100%')

      Row() {
        Blank().layoutWeight(this.getInterpolatedX(index, 3))
        Ellipse().width(11).height(6).fill('#94a3b8')
        Blank().layoutWeight(1 - this.getInterpolatedX(index, 3))
      }.width('100%')

      Row() {
        Blank().layoutWeight(this.getInterpolatedX(index, 4))
        Ellipse().width(10).height(6).fill('#94a3b8')
        Blank().layoutWeight(1 - this.getInterpolatedX(index, 4))
      }.width('100%')

      Row() {
        Blank().layoutWeight(this.getInterpolatedX(index, 5))
        Ellipse().width(10).height(5).fill('#94a3b8')
        Blank().layoutWeight(1 - this.getInterpolatedX(index, 5))
      }.width('100%')

      Row() {
        Blank().layoutWeight(this.getInterpolatedX(index, 6))
        Ellipse().width(10).height(5).fill('#94a3b8')
        Blank().layoutWeight(1 - this.getInterpolatedX(index, 6))
      }.width('100%')
    }
    .width('100%')
    .height(50)
  }

  @Builder
  LevelNode(level: LevelNodeData) {
    Stack() {
      // 水波纹扩散动画（仅当前关卡）
      if (level.status === LevelStatus.CURRENT) {
        // 第3层波纹 - 最外层
        Circle()
          .width(84)
          .height(84)
          .fill(Color.Transparent)
          .stroke('rgba(99, 102, 241, ' + this.ripple3Opacity.toFixed(2) + ')')
          .strokeWidth(2)
          .scale({ x: this.ripple3Scale, y: this.ripple3Scale })

        // 第2层波纹 - 中层
        Circle()
          .width(84)
          .height(84)
          .fill(Color.Transparent)
          .stroke('rgba(99, 102, 241, ' + this.ripple2Opacity.toFixed(2) + ')')
          .strokeWidth(2)
          .scale({ x: this.ripple2Scale, y: this.ripple2Scale })

        // 第1层波纹 - 内层
        Circle()
          .width(84)
          .height(84)
          .fill(Color.Transparent)
          .stroke('rgba(99, 102, 241, ' + this.breathOpacity.toFixed(2) + ')')
          .strokeWidth(2)
          .scale({ x: this.breathScale, y: this.breathScale })

        // 固定内层光环
        Circle()
          .width(88)
          .height(88)
          .fill(Color.Transparent)
          .stroke('rgba(255, 255, 255, 0.5)')
          .strokeWidth(3)
      }

      // 主圆形节点
      Circle()
        .width(80)
        .height(80)
        .fill(this.getNodeColor(level.status))

      // 节点内容
      if (level.status === LevelStatus.LOCKED) {
        // 锁定：显示锁图标
        Image($r('app.media.ic_lock'))
          .width(32)
          .height(32)
          .fillColor('#94a3b8')
      } else if (level.status === LevelStatus.COMPLETED) {
        // 已完成：显示白色对勾
        Image($r('app.media.ic_check'))
          .width(36)
          .height(36)
          .fillColor('#ffffff')
      } else {
        // 当前关卡：显示关卡号和星星
        Column() {
          Text(level.id.toString())
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')

          Row({ space: 3 }) {
            Text('⭐')
              .fontSize(12)
            Text('⭐')
              .fontSize(12)
          }
          .margin({ top: 4 })
        }
      }
    }
    .width(100)
    .height(100)
    .onClick(() => {
      if (level.status !== LevelStatus.LOCKED) {
        this.goToLesson(level.id);
      }
    })
  }

  getNodeColor(status: LevelStatus): ResourceColor {
    switch (status) {
      case LevelStatus.COMPLETED:
        return '#10b981';  // 绿色
      case LevelStatus.CURRENT:
        return '#6366f1';  // 紫色
      default:
        return '#cbd5e1';  // 灰色（锁定）
    }
  }

  goToLesson(lessonId: number) {
    router.pushUrl({
      url: 'pages/LessonPage',
      params: {
        lessonId: lessonId,
        level: this.currentLevel,
        title: '关卡 ' + lessonId.toString()
      }
    });
  }
}
