/**
 * 灰字高级调整共享元数据：可单独设置灰字颜色的页面清单 + 预置色。
 * 被「外观设置页」（入口摘要）与「灰字高级调整页」共用。
 * key 必须与 GlassMaterial.setPageActive(...) 的接线、MainView.tabPageKey(...) 的映射一致。
 */

export interface GrayAdvPage {
  key: string;
  name: string;
}

/** 可单独设色的页面清单（含灰字文本的页面） */
export const GRAY_ADV_PAGES: GrayAdvPage[] = [
  { key: 'home', name: '首页' },
  { key: 'schedule', name: '课程表' },
  { key: 'score', name: '成绩查询' },
  { key: 'exam', name: '考试安排' },
  { key: 'news', name: '校园资讯' },
  { key: 'notice', name: '通知公告' },
  { key: 'kxjs', name: '空教室' },
  { key: 'mine', name: '我的' }
];

/** 预置颜色（rrggbb；与全局灰字胶囊风格互补的常用色） */
export const GRAY_ADV_COLORS: string[] = ['9AA0A6', 'FFFFFF', '000000', 'FFE082', '90CAF9', 'A5D6A7', 'EF9A9A', 'CE93D8'];
