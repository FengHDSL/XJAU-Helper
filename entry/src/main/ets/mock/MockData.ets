/**
 * Demo 阶段的模拟数据。
 * 全部按"当前日期"动态生成，保证课表 / 考试倒计时始终是新鲜的。
 * 接入真实教务系统后，本文件可整体删除，只需保证 JwApi 返回同样的模型即可。
 */
import { DateUtil } from '../common/DateUtil';
import { MonthGroup } from '../model/TeachingCalendar';
import { AcademicReport, CourseItem, CreditCategory, ExamItem, NoticeItem, ScoreItem, TermGpa, TermInfo,
  TermScore, UserProfile } from '../model/Models';

function range(from: number, to: number, step: number): number[] {
  const list: number[] = [];
  for (let i = from; i <= to; i += step) {
    list.push(i);
  }
  return list;
}

export class MockData {
  static readonly PROFILE: UserProfile = {
    studentId: '0123456789',
    name: '张三',
    college: 'XXX学院',
    major: 'XXX',
    className: 'XXX2601班',
    grade: '2026 级',
    counselor: '李四',
    eduSystem: '四年制本科',
    status: '在读'
  };

  /** 当前学期课表 */
  static courses(): CourseItem[] {
    return [
      MockData.course('c01', '高等数学Ⅱ', '王五', '主楼 A203', 1, 1, 2, range(1, 16, 1), '1-16周', '必修', 4, 0),
      MockData.course('c02', '高等数学Ⅱ', '王五', '主楼 A203', 3, 3, 4, range(1, 16, 1), '1-16周', '必修', 4, 0),
      MockData.course('c03', '大学英语（三）', '赵六', '外语楼 302', 1, 3, 4, range(1, 16, 1), '1-16周', '必修', 3, 1),
      MockData.course('c04', '大学英语（三）', '赵六', '外语楼 302', 4, 1, 2, range(1, 16, 1), '1-16周', '必修', 3, 1),
      MockData.course('c05', '数据结构', '孙七', '信息楼 401', 2, 1, 2, range(1, 18, 1), '1-18周', '必修', 4, 2),
      MockData.course('c06', '数据结构', '孙七', '信息楼 401', 5, 3, 4, range(1, 18, 1), '1-18周', '必修', 4, 2),
      MockData.course('c07', '数据结构实验', '孙七', '信息楼机房 2', 5, 5, 6, range(2, 18, 2), '2-18周(双)', '实践', 1, 3),
      MockData.course('c08', '计算机组成原理', '周八', '信息楼 305', 2, 5, 6, range(1, 16, 1), '1-16周', '必修', 3.5, 4),
      MockData.course('c09', '计算机组成原理', '周八', '信息楼 305', 4, 5, 6, range(1, 16, 1), '1-16周', '必修', 3.5, 4),
      MockData.course('c10', '马克思主义基本原理', '吴九', '教学楼 B102', 3, 1, 2, range(1, 14, 1), '1-14周', '必修', 3, 5),
      MockData.course('c11', '大学体育（三）', '郑十', '西区田径场', 3, 5, 6, range(1, 16, 1), '1-16周', '必修', 1, 6),
      MockData.course('c12', '概率论与数理统计', '冯一', '主楼 A105', 4, 3, 4, range(1, 16, 1), '1-16周', '必修', 3, 7),
      MockData.course('c13', 'Java 程序设计', '陈二', '信息楼机房 1', 1, 5, 6, range(1, 16, 1), '1-16周', '必修', 3, 2),
      MockData.course('c14', '操作系统', '褚三', '信息楼 302', 2, 3, 4, range(1, 16, 1), '1-16周', '必修', 4, 5),
      MockData.course('c15', '操作系统', '褚三', '信息楼 302', 5, 1, 2, range(1, 16, 1), '1-16周', '必修', 4, 5),
      MockData.course('c16', '形势与政策', '卫四', '教学楼 B203', 4, 7, 8, range(5, 12, 1), '5-12周', '必修', 0.5, 3),
      MockData.course('c17', '大学生职业发展', '蒋五', '教学楼 C101', 2, 7, 8, range(1, 8, 1), '1-8周', '选修', 1, 6),
      MockData.course('c18', '农业信息化导论', '沈六', '信息楼 203', 5, 7, 8, range(1, 12, 1), '1-12周', '选修', 2, 7),
      MockData.course('c19', '人工智能导论', '韩七', '信息楼 406', 1, 7, 8, range(3, 16, 1), '3-16周', '选修', 2, 4),
      MockData.course('c20', '创新创业实践', '杨八', '大学生活动中心', 3, 9, 10, range(1, 10, 2), '1-10周(单)', '实践', 1, 1)
    ];
  }

  private static course(id: string, name: string, teacher: string, location: string, weekday: number,
    start: number, end: number, weeks: number[], weeksText: string, type: string, credit: number,
    color: number): CourseItem {
    return {
      id: id,
      name: name,
      teacher: teacher,
      location: location,
      weekday: weekday,
      startSection: start,
      endSection: end,
      weeks: weeks,
      weeksText: weeksText,
      courseType: type,
      credit: credit,
      colorIndex: color
    };
  }

  /** 考试安排：围绕今天动态生成 */
  static exams(): ExamItem[] {
    const today: Date = new Date();
    return [
      MockData.exam('e01', '大学生职业发展', DateUtil.addDays(today, -3), '10:00-11:30', '教学楼 C101', '023', '期中考试', '蒋五'),
      MockData.exam('e02', '数据结构', DateUtil.addDays(today, 2), '10:00-12:00', '信息楼 401', '015', '期末考试', '孙七'),
      MockData.exam('e03', '高等数学Ⅱ', DateUtil.addDays(today, 5), '16:00-18:00', '主楼 A203', '032', '期末考试', '王五'),
      MockData.exam('e04', '计算机组成原理', DateUtil.addDays(today, 9), '10:00-12:00', '信息楼 305', '008', '期末考试', '周八'),
      MockData.exam('e05', '大学英语（三）', DateUtil.addDays(today, 12), '16:00-18:00', '外语楼 302', '041', '期末考试', '赵六'),
      MockData.exam('e06', '操作系统', DateUtil.addDays(today, 15), '10:00-12:00', '信息楼 302', '019', '期末考试', '褚三'),
      MockData.exam('e07', '马克思主义基本原理', DateUtil.addDays(today, 18), '16:00-17:40', '教学楼 B102', '056', '期末考试', '吴九')
    ];
  }

  private static exam(id: string, name: string, date: Date, timeRange: string, location: string, seat: string,
    type: string, teacher: string): ExamItem {
    return {
      id: id,
      courseName: name,
      date: DateUtil.format(date),
      timeRange: timeRange,
      location: location,
      seat: seat,
      examType: type,
      teacher: teacher
    };
  }

  /** 历史学期列表（含当前学期） */
  static terms(current: TermInfo): TermInfo[] {
    const parts: string[] = current.id.split('-');
    const beginYear: number = Number.parseInt(parts[0], 10);
    const index: number = Number.parseInt(parts[2], 10);
    const list: TermInfo[] = [current];
    let y: number = beginYear;
    let i: number = index;
    for (let k = 0; k < 3; k++) {
      if (i === 1) {
        y = y - 1;
        i = 2;
      } else {
        i = 1;
      }
      const startDate: string = i === 1 ? `${y}-09-01` : `${y + 1}-03-01`;
      list.push({
        id: `${y}-${y + 1}-${i}`,
        label: `${y}-${y + 1}学年 ${i === 1 ? '第一学期' : '第二学期'}`,
        startDate: startDate,
        totalWeeks: 20
      });
    }
    return list;
  }

  /** 各学期成绩 */
  static termScores(terms: TermInfo[]): TermScore[] {
    const list: TermScore[] = [];
    // 当前学期：成绩未发布
    list.push({
      termId: terms[0].id,
      termLabel: terms[0].label,
      gpa: 0,
      avgScore: 0,
      totalCredit: 0,
      earnedCredit: 0,
      rank: 0,
      classSize: 42,
      items: []
    });
    list.push({
      termId: terms[1].id,
      termLabel: terms[1].label,
      gpa: 3.62,
      avgScore: 86.4,
      totalCredit: 25.5,
      earnedCredit: 25.5,
      rank: 6,
      classSize: 42,
      items: [
        MockData.score('s101', '离散数学', 3, 91, 4.1, '必修', terms[1].id),
        MockData.score('s102', '面向对象程序设计', 4, 88, 3.8, '必修', terms[1].id),
        MockData.score('s103', '数字逻辑电路', 3, 79, 2.9, '必修', terms[1].id),
        MockData.score('s104', '大学英语（二）', 3, 84, 3.4, '必修', terms[1].id),
        MockData.score('s105', '高等数学Ⅰ（下）', 4, 76, 2.6, '必修', terms[1].id),
        MockData.score('s106', '中国近现代史纲要', 2, 93, 4.3, '必修', terms[1].id),
        MockData.score('s107', '大学体育（二）', 1, -1, 4.0, '必修', terms[1].id),
        MockData.score('s108', '数据库原理', 3.5, 90, 4.0, '必修', terms[1].id),
        MockData.score('s109', '摄影基础', 2, 95, 4.5, '选修', terms[1].id)
      ]
    });
    list.push({
      termId: terms[2].id,
      termLabel: terms[2].label,
      gpa: 3.41,
      avgScore: 83.7,
      totalCredit: 24,
      earnedCredit: 24,
      rank: 9,
      classSize: 42,
      items: [
        MockData.score('s201', 'C 语言程序设计', 4, 89, 3.9, '必修', terms[2].id),
        MockData.score('s202', '高等数学Ⅰ（上）', 5, 72, 2.2, '必修', terms[2].id),
        MockData.score('s203', '线性代数', 3, 85, 3.5, '必修', terms[2].id),
        MockData.score('s204', '大学英语（一）', 3, 82, 3.2, '必修', terms[2].id),
        MockData.score('s205', '思想道德与法治', 3, 90, 4.0, '必修', terms[2].id),
        MockData.score('s206', '计算机导论', 2, 94, 4.4, '必修', terms[2].id),
        MockData.score('s207', '大学体育（一）', 1, -1, 3.7, '必修', terms[2].id),
        MockData.score('s208', '军事理论', 2, 87, 3.7, '必修', terms[2].id),
        MockData.score('s209', '园艺与生活', 1, 91, 4.1, '选修', terms[2].id)
      ]
    });
    list.push({
      termId: terms[3].id,
      termLabel: terms[3].label,
      gpa: 3.28,
      avgScore: 81.2,
      totalCredit: 18,
      earnedCredit: 16,
      rank: 14,
      classSize: 42,
      items: [
        MockData.score('s301', '大学物理', 4, 58, 0, '必修', terms[3].id),
        MockData.score('s302', '大学物理（补考）', 4, 62, 1.2, '必修', terms[3].id, '补考'),
        MockData.score('s303', '程序设计基础', 3, 86, 3.6, '必修', terms[3].id),
        MockData.score('s304', '大学语文', 2, 88, 3.8, '选修', terms[3].id),
        MockData.score('s305', '形势与政策（一）', 0.5, -1, 4.0, '必修', terms[3].id)
      ]
    });
    return list;
  }

  private static score(id: string, name: string, credit: number, score: number, gp: number, type: string,
    termId: string, examType: string = '正常考试'): ScoreItem {
    let text: string = score < 0 ? '优秀' : `${score}`;
    // 任课教师：按课程名取个 hash 映射，避免手填
    let hash: number = 0;
    for (let i = 0; i < name.length; i++) {
      hash = (hash * 31 + name.charCodeAt(i)) >>> 0;
    }
    const teachers: string[] = ['王五', '赵六', '孙七', '周八', '吴九', '郑十', '冯一', '陈二'];
    const teacher: string = teachers[hash % teachers.length];
    return {
      id: id,
      courseName: name,
      credit: credit,
      score: score,
      scoreText: text,
      gradePoint: gp,
      courseType: type,
      examType: examType,
      teacher: teacher,
      termId: termId,
      kclbmc: ''
    };
  }

  /** 通知公告 */
  static notices(): NoticeItem[] {
    const today: Date = new Date();
    return [
      {
        id: 'n01',
        title: '关于做好本学期期末考试安排工作的通知',
        source: '教务处',
        date: DateUtil.format(DateUtil.addDays(today, -1)),
        tag: '考试',
        isTop: true,
        read: false,
        summary: '各学院请于本周五前完成考场编排，学生可在教务系统查询个人考试安排。',
        content: '各学院、各位同学：\n\n本学期期末考试定于第 17-19 周进行，现将有关事项通知如下：\n\n一、考试安排\n1. 各学院须于本周五 18:00 前完成考场编排并提交教务处审核。\n2. 学生可通过教务系统或本客户端"考试安排"栏目查询个人考试时间、地点及座位号。\n\n二、考试纪律\n1. 考生须携带学生证、身份证参加考试，两证缺一不得入场。\n2. 开考 15 分钟后不得入场，开考 30 分钟后方可交卷离场。\n3. 严禁携带具有存储、通讯功能的电子设备进入考场。\n\n三、缓考与补考\n因病因事无法参加考试的同学，须提前 3 个工作日提交缓考申请并附证明材料。\n\n教务处\n',
        url: '',
      },
      {
        id: 'n02',
        title: '下学期选课系统开放时间及注意事项',
        source: '教务处',
        date: DateUtil.format(DateUtil.addDays(today, -2)),
        tag: '选课',
        isTop: true,
        read: false,
        summary: '选课分三轮进行，第一轮预选于下周一 12:00 开放，请提前查看培养方案。',
        content: '各位同学：\n\n下学期选课工作即将开始，具体安排如下：\n\n第一轮（预选）：下周一 12:00 - 下周五 18:00\n第二轮（正选）：第 16 周周一 12:00 - 周三 18:00\n第三轮（补退选）：开学第 1-2 周\n\n注意事项：\n1. 选课前请仔细阅读本专业培养方案，确认已修与待修课程。\n2. 每学期修读学分原则上不超过 30 学分。\n3. 体育、公共选修课名额有限，先到先得。\n4. 选课期间系统访问量大，建议错峰操作。\n\n教务处\n',
        url: '',
      },
      {
        id: 'n03',
        title: '计算机与信息工程学院关于开展学业预警工作的通知',
        source: '计算机与信息工程学院',
        date: DateUtil.format(DateUtil.addDays(today, -4)),
        tag: '教学',
        isTop: false,
        read: true,
        summary: '对累计不及格学分达到 10 学分的同学进行学业预警，请及时联系辅导员。',
        content: '各位同学：\n\n为帮助同学们顺利完成学业，学院将对以下情况开展学业预警：\n\n1. 一学期不及格课程累计达 8 学分；\n2. 累计不及格课程达 15 学分；\n3. 累计获得学分低于同年级培养方案要求的 60%。\n\n被预警同学请于本周内联系辅导员，制定个人学业改进计划。家长将同步收到告知函。\n\n计算机与信息工程学院\n',
        url: '',
      },
      {
        id: 'n04',
        title: '关于 2026 届毕业设计（论文）中期检查的通知',
        source: '教务处',
        date: DateUtil.format(DateUtil.addDays(today, -6)),
        tag: '教学',
        isTop: false,
        read: true,
        summary: '中期检查材料提交截止时间为本月底，请指导教师与学生共同完成。',
        content: '各学院：\n\n为保证毕业设计（论文）质量，现开展中期检查工作。\n\n检查内容包括：开题报告完成情况、外文翻译、阶段性成果、指导记录等。\n请各位同学于本月底前在系统提交中期检查表，并由指导教师签署意见。\n\n教务处\n',
        url: '',
      },
      {
        id: 'n05',
        title: '数据结构课程调停课通知',
        source: '计算机与信息工程学院',
        date: DateUtil.format(DateUtil.addDays(today, -7)),
        tag: '通知',
        isTop: false,
        read: true,
        summary: '因教师外出参加学术会议，本周五第 3-4 节数据结构课调至下周六同一时段。',
        content: '各位同学：\n\n因孙七老师外出参加学术会议，原定本周五第 3-4 节《数据结构》课程调整至下周六第 3-4 节，上课地点不变（信息楼 401）。\n\n请相互转告，按时上课。\n\n计算机与信息工程学院教务办\n',
        url: '',
      },
      {
        id: 'n06',
        title: '关于开展本学期教学质量评价的通知',
        source: '教务处',
        date: DateUtil.format(DateUtil.addDays(today, -9)),
        tag: '教学',
        isTop: false,
        read: true,
        summary: '未完成评教的同学将无法查询本学期成绩，请在规定时间内完成。',
        content: '各位同学：\n\n本学期教学质量评价工作现已开始，请在第 15-17 周内完成全部课程的评价。\n\n温馨提示：未完成评教的同学将无法查询本学期期末成绩。评教结果匿名处理，请客观公正评价。\n\n教务处\n',
        url: '',
      },
      {
        id: 'n07',
        title: '关于国家奖学金、励志奖学金评审工作的通知',
        source: '学生工作处',
        date: DateUtil.format(DateUtil.addDays(today, -12)),
        tag: '通知',
        isTop: false,
        read: true,
        summary: '申请材料请于下周三前提交至学院办公室，逾期不予受理。',
        content: '各位同学：\n\n本年度国家奖学金、国家励志奖学金评审工作现已启动。\n\n申请条件：\n1. 上一学年无不及格课程；\n2. 学业成绩排名与综合测评排名均位于专业前 30%；\n3. 家庭经济困难认定（励志奖学金）。\n\n请符合条件的同学下载申请表，填写后于下周三 18:00 前提交至学院办公室。\n\n学生工作处\n',
        url: '',
      }
    ];
  }

  /** 学业情况 */
  static academic(): AcademicReport {
    const categories: CreditCategory[] = [
      { name: '公共必修课', required: 42, earned: 34 },
      { name: '学科基础课', required: 38, earned: 27.5 },
      { name: '专业必修课', required: 32, earned: 12 },
      { name: '专业选修课', required: 16, earned: 6 },
      { name: '公共选修课', required: 8, earned: 5 },
      { name: '集中实践环节', required: 24, earned: 8 }
    ];
    const trend: TermGpa[] = [
      { termLabel: '大一上', gpa: 3.28 },
      { termLabel: '大一下', gpa: 3.41 },
      { termLabel: '大二上', gpa: 3.62 },
      { termLabel: '大二下', gpa: 3.55 }
    ];
    return {
      totalRequired: 160,
      totalEarned: 92.5,
      gpa: 3.47,
      rank: 8,
      classSize: 42,
      failedCount: 1,
      unearnedCount: 3,
      studyingCount: 12,
      outsideCount: 5,
      passRate: 96.8,
      categories: categories,
      warnings: [
        '《大学物理》首修不及格，已通过补考取得学分，绩点按补考成绩计入。',
        '专业选修课已修 6 学分，距毕业要求还差 10 学分，建议下学期至少选修 2 门。'
      ],
      gpaTrend: trend
    };
  }

  /** 教务处官网「学期校历」最新两条（通知功能数据源） */
  static jwcNotices(): NoticeItem[] {
    return [
      {
        id: 'jwc-1',
        title: '2026年秋季学期校历',
        source: '教务处官网',
        date: '2026-05-15',
        tag: '通知',
        isTop: true,
        read: false,
        summary: '2026-2027学年第一学期校历（2026年秋季学期）已发布。',
        content: '2026-2027学年第一学期校历（2026年秋季学期）：2026-08-31（周一）开学，第1~20周教学活动，第21周起放寒假。',
        url: 'https://jwc.xjau.edu.cn/2026/0515/c3318a115903/page.htm'
      },
      {
        id: 'jwc-2',
        title: '2026年春季学期校历',
        source: '教务处官网',
        date: '2025-12-31',
        tag: '通知',
        isTop: false,
        read: false,
        summary: '2025-2026学年第二学期校历。',
        content: '2026年春季学期校历（2025-2026学年第二学期）。',
        url: 'https://jwc.xjau.edu.cn/2025/1225/c3318a112583/page.htm'
      }
    ];
  }

  /** 校历转换结果（从最新校历 PDF 转换而来，作为 mock 默认缓存；真实模式下载 PDF 转换后覆盖） */
  static jwcCalendarJson(): string {
    return '{"semesterLabel":"2026-2027学年第一学期（2026年秋季学期）","startDate":"2026-08-31","endDate":"2027-02-21","monthGroups":[{"label":"8月","span":1},{"label":"9月","span":4},{"label":"10月","span":4},{"label":"11月","span":5},{"label":"12月","span":4},{"label":"1月","span":4},{"label":"2月","span":3}],"weekNumbers":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25],"rows":[{"weekday":"周一","dates":["2026-08-31","2026-09-07","2026-09-14","2026-09-21","2026-09-28","2026-10-05","2026-10-12","2026-10-19","2026-10-26","2026-11-02","2026-11-09","2026-11-16","2026-11-23","2026-11-30","2026-12-07","2026-12-14","2026-12-21","2026-12-28","2027-01-04","2027-01-11","2027-01-18","2027-01-25","2027-02-01","2027-02-08","2027-02-15"]},{"weekday":"周二","dates":["2026-09-01","2026-09-08","2026-09-15","2026-09-22","2026-09-29","2026-10-06","2026-10-13","2026-10-20","2026-10-27","2026-11-03","2026-11-10","2026-11-17","2026-11-24","2026-12-01","2026-12-08","2026-12-15","2026-12-22","2026-12-29","2027-01-05","2027-01-12","2027-01-19","2027-01-26","2027-02-02","2027-02-09","2027-02-16"]},{"weekday":"周三","dates":["2026-09-02","2026-09-09","2026-09-16","2026-09-23","2026-09-30","2026-10-07","2026-10-14","2026-10-21","2026-10-28","2026-11-04","2026-11-11","2026-11-18","2026-11-25","2026-12-02","2026-12-09","2026-12-16","2026-12-23","2026-12-30","2027-01-06","2027-01-13","2027-01-20","2027-01-27","2027-02-03","2027-02-10","2027-02-17"]},{"weekday":"周四","dates":["2026-09-03","2026-09-10","2026-09-17","2026-09-24","2026-10-01","2026-10-08","2026-10-15","2026-10-22","2026-10-29","2026-11-05","2026-11-12","2026-11-19","2026-11-26","2026-12-03","2026-12-10","2026-12-17","2026-12-24","2026-12-31","2027-01-07","2027-01-14","2027-01-21","2027-01-28","2027-02-04","2027-02-11","2027-02-18"]},{"weekday":"周五","dates":["2026-09-04","2026-09-11","2026-09-18","2026-09-25","2026-10-02","2026-10-09","2026-10-16","2026-10-23","2026-10-30","2026-11-06","2026-11-13","2026-11-20","2026-11-27","2026-12-04","2026-12-11","2026-12-18","2026-12-25","2027-01-01","2027-01-08","2027-01-15","2027-01-22","2027-01-29","2027-02-05","2027-02-12","2027-02-19"]},{"weekday":"周六","dates":["2026-09-05","2026-09-12","2026-09-19","2026-09-26","2026-10-03","2026-10-10","2026-10-17","2026-10-24","2026-10-31","2026-11-07","2026-11-14","2026-11-21","2026-11-28","2026-12-05","2026-12-12","2026-12-19","2026-12-26","2027-01-02","2027-01-09","2027-01-16","2027-01-23","2027-01-30","2027-02-06","2027-02-13","2027-02-20"]},{"weekday":"周日","dates":["2026-09-06","2026-09-13","2026-09-20","2026-09-27","2026-10-04","2026-10-11","2026-10-18","2026-10-25","2026-11-01","2026-11-08","2026-11-15","2026-11-22","2026-11-29","2026-12-06","2026-12-13","2026-12-20","2026-12-27","2027-01-03","2027-01-10","2027-01-17","2027-01-24","2027-01-31","2027-02-07","2027-02-14","2027-02-21"]}],"todayDate":"2026-08-06"}';
  }
  /**
   * 教学周历（校历）模拟 HTML：结构与正方 <table class="...tab-bor-col-1..."> 一致，
   * 供 parseTeachingCalendar 解析，使 mock 模式下也能展示真实的教学周历布局。
   * 数据按 2026-2027 学年 1 学期（2026-08-24 至 2027-01-10）生成。
   */
  static teachingCalendarHtml(): string {
    const weekdays: string[] = ['一', '二', '三', '四', '五', '六', '日'];
    // 7 行 × 25 列，单元格 id = yyyy-MM-dd，空串表示空白格
    const ids: string[][] = [
      ['2026-08-24', '', '2026-09-07', '2026-09-14', '2026-09-21', '2026-09-28', '', '2026-10-05', '2026-10-12', '2026-10-19', '2026-10-26', '', '2026-11-02', '2026-11-09', '2026-11-16', '2026-11-23', '2026-11-30', '', '2026-12-07', '2026-12-14', '2026-12-21', '2026-12-28', '', '2027-01-04', ''],
      ['2026-08-25', '', '2026-09-01', '2026-09-08', '2026-09-15', '2026-09-22', '2026-09-29', '', '2026-10-06', '2026-10-13', '2026-10-20', '2026-10-27', '', '2026-11-03', '2026-11-10', '2026-11-17', '2026-11-24', '', '2026-12-01', '2026-12-08', '2026-12-15', '2026-12-22', '2026-12-29', '', '2027-01-05', ''],
      ['2026-08-26', '', '2026-09-02', '2026-09-09', '2026-09-16', '2026-09-23', '2026-09-30', '', '2026-10-07', '2026-10-14', '2026-10-21', '2026-10-28', '', '2026-11-04', '2026-11-11', '2026-11-18', '2026-11-25', '', '2026-12-02', '2026-12-09', '2026-12-16', '2026-12-23', '2026-12-30', '', '2027-01-06', ''],
      ['2026-08-27', '', '2026-09-03', '2026-09-10', '2026-09-17', '2026-09-24', '', '2026-10-01', '2026-10-08', '2026-10-15', '2026-10-22', '2026-10-29', '', '2026-11-05', '2026-11-12', '2026-11-19', '2026-11-26', '', '2026-12-03', '2026-12-10', '2026-12-17', '2026-12-24', '2026-12-31', '', '2027-01-07', ''],
      ['2026-08-28', '', '2026-09-04', '2026-09-11', '2026-09-18', '2026-09-25', '', '2026-10-02', '2026-10-09', '2026-10-16', '2026-10-23', '2026-10-30', '', '2026-11-06', '2026-11-13', '2026-11-20', '2026-11-27', '', '2026-12-04', '2026-12-11', '2026-12-18', '2026-12-25', '', '2027-01-01', '2027-01-08', ''],
      ['2026-08-29', '', '2026-09-05', '2026-09-12', '2026-09-19', '2026-09-26', '', '2026-10-03', '2026-10-10', '2026-10-17', '2026-10-24', '2026-10-31', '', '2026-11-07', '2026-11-14', '2026-11-21', '2026-11-28', '', '2026-12-05', '2026-12-12', '2026-12-19', '2026-12-26', '', '2027-01-02', '2027-01-09', ''],
      ['2026-08-30', '', '2026-09-06', '2026-09-13', '2026-09-20', '2026-09-27', '', '2026-10-04', '2026-10-11', '2026-10-18', '2026-10-25', '', '2026-11-01', '2026-11-08', '2026-11-15', '2026-11-22', '2026-11-29', '', '2026-12-06', '2026-12-13', '2026-12-20', '2026-12-27', '', '2027-01-03', '2027-01-10', '']
    ];
    const semesterLabel: string = '2026-2027学年1学期(2026-08-24至2027-01-10)';
    const monthGroups: MonthGroup[] = [
      { label: '8月', span: 2 }, { label: '9月', span: 5 }, { label: '10月', span: 5 },
      { label: '11月', span: 6 }, { label: '12月', span: 5 }, { label: '1月', span: 2 }
    ];
    const weekNumbers: number[] = [0, 1, 1, 2, 3, 4, 5, 5, 6, 7, 8, 9, 9, 10, 11, 12, 13, 14, 14, 15, 16, 17, 18, 18, 19];
    const dqrq: string = '2026-08-06';

    let monthTh: string = '';
    for (let i = 0; i < monthGroups.length; i++) {
      monthTh += `<th colspan="${monthGroups[i].span}" style="text-align: center">${monthGroups[i].label}</th>`;
    }
    let weekTh: string = '';
    for (let i = 0; i < weekNumbers.length; i++) {
      weekTh += `<th style="text-align: center">${weekNumbers[i]}</th>`;
    }
    let body: string = '';
    for (let r = 0; r < weekdays.length; r++) {
      let cells: string = '';
      for (let c = 0; c < ids[r].length; c++) {
        const id: string = ids[r][c];
        const day: string = id.length > 0 ? id.slice(-2) : '';
        cells += `<td id="${id}" title="">${day}</td>`;
      }
      body += `<tr>\n   <th style="">${weekdays[r]}</th>\n   ${cells}\n  </tr>`;
    }

    return `<div class="table-responsive">\n` +
      ` <table class="table table-bordered tab-bor-col-1 tab-td-padding-2 tab-td-font-12 tab-td-center" style="min-width: 800px;">\n` +
      `\t<input type="hidden" name="rcStr" value="" id="rcStr">\n` +
      `\t<input type="hidden" name="dqrq" value="${dqrq}" id="dqrq">\n` +
      `  <thead>\n` +
      `  <tr class="tab-th-1">\n` +
      `   		<th rowspan="3" class="xl_jb">&nbsp;</th>\n` +
      `    	<th colspan="25" style="text-align: center">${semesterLabel}</th>\n` +
      `  </tr>\n` +
      `  <tr class="tab-th-1">\n` +
      `   		${monthTh}\n` +
      `  </tr>\n` +
      `  <tr class="tab-th-2">\n` +
      `   		${weekTh}\n` +
      `  </tr>\n` +
      `  </thead>\n` +
      `  <tbody>\n` +
      `${body}` +
      `  </tbody>\n` +
      `</table>\n` +
      `</div>`;
  }
}
