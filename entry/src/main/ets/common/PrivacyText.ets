/**
 * 隐私协议/开发者声明文本。
 * 协议正文单一事实源：resources/rawfile/privacy.html（首次引导弹窗与「我的 → 隐私协议」页共用 Web 加载，
 * 参考本地项目 xndcourse 的 privacy.html 写法）。修改协议内容只需改该 HTML。
 *
 * 本文件仅保留「开发者声明」（DEVELOPER_DECLARATION，首次引导同意后的独立弹窗）。
 */

/** 首次同意后的开发者声明（独立弹窗展示，参考 DailyNic_HMOS 免责声明）。
 *  采用分段结构（title + 正文），便于弹窗内加粗重点文字。 */
export interface DeclarationSection {
  title: string;
  content: string;
}

/** 开发者声明正文（title 加粗展示，content 普通文本） */
export const DEVELOPER_DECLARATION: DeclarationSection[] = [
  {
    title: '独立开发声明',
    content: '本应用由新疆农业大学学生独立开发，非学校官方应用。'
  },
  {
    title: '素材版权',
    content: '应用内涉及到的新疆农业大学相关网站资源、视觉素材、标识等内容，其著作权、所有权均归属新疆农业大学。' +
      '本应用未在任何界面中以任何方式宣称、暗示自身为"官方应用"或与校方存在合作关系。'
  },
  {
    title: '开源说明',
    content: '本应用为非商业性开源学习项目，欢迎通过 GitHub（FengHDSL/XJAU-Helper）参与改进与反馈。'
  }
];
