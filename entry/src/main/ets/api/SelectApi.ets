/**
 * 快捷选课 / 抢课 API —— 对齐参考项目 **新正方（ZfAcademicAdapter）** 的真实流程：
 *  ① GET  `xsxk/zzxkyzb_cxZzxkYzbIndex.html?gnmkdm=N253512`   入口页（隐藏域 + queryCourse 分类）
 *  ② POST `xsxk/zzxkyzb_cxZzxkYzbDisplay.html`                每个分类取该轮次的完整参数（隐藏域合并）
 *  ③ POST `xsxk/zzxkyzb_cxZzxkYzbPartDisplay.html`            课程列表（白名单参数 + filter_list[0] 关键字 + kspage/jspage 分页）
 *  ④ POST `xsxk/zzxkyzbjk_cxJxbWithKchZzxkYzb.html`           教学班列表（含 do_jxb_id）
 *  ⑤ POST `xsxk/zzxkyzbjk_xkBcZyZzxkYzb.html`                 选课（课程行参数 + 教学班行参数合并后提交）
 *  ⑥ POST `xsxk/zzxkyzb_cxZzxkYzbChoosedDisplay.html`         已选课程
 *  ⑦ POST `xsxk/zzxkyzb_tuikBcZzxkYzb.html`                   退选
 *
 * 抢课：目标队列（持久化）+ 定时策略（重试间隔/最大重试次数/并行/延时启动/捡漏）+ 开始/停止。
 * 注意：抢课需学校开放选课轮次，本模块按参考项目移植，未经真机验证。
 */
import { HttpClient, HttpResult } from './HttpClient';
import { DataStore } from '../common/DataStore';
import { LogStore } from '../common/LogStore';
import { ClassFilter, GrabPolicy, GrabTarget, SelectableClass, SelectedCourseItem, SelectContext, SelectScope } from '../model/Models';

/** 选课/退课结果 */
export interface SelectResult {
  ok: boolean;
  message: string;
}

const GNMKDM: string = 'N253512';
const INDEX_URL: string = `/jwglxt/xsxk/zzxkyzb_cxZzxkYzbIndex.html?gnmkdm=${GNMKDM}&layout=default`;
const DISPLAY_URL: string = `/jwglxt/xsxk/zzxkyzb_cxZzxkYzbDisplay.html?gnmkdm=${GNMKDM}`;
const PART_DISPLAY_URL: string = `/jwglxt/xsxk/zzxkyzb_cxZzxkYzbPartDisplay.html?gnmkdm=${GNMKDM}`;
const SECTION_URL: string = `/jwglxt/xsxk/zzxkyzbjk_cxJxbWithKchZzxkYzb.html?gnmkdm=${GNMKDM}`;
const CHOOSE_URL: string = `/jwglxt/xsxk/zzxkyzbjk_xkBcZyZzxkYzb.html?gnmkdm=${GNMKDM}`;
const DROP_URL: string = `/jwglxt/xsxk/zzxkyzb_tuikBcZzxkYzb.html?gnmkdm=${GNMKDM}`;
const CHOOSED_URL: string = `/jwglxt/xsxk/zzxkyzb_cxZzxkYzbChoosedDisplay.html?gnmkdm=${GNMKDM}`;
/** 上下文缓存键 */
const KEY_SELECT_CTX: string = 'select_context';

/** 分类（入口页 queryCourse 或 first* 变体） */
interface SelectCategory {
  kklxdm: string;
  xkkz: string;
  njdm: string;
  zyh: string;
}

export class SelectApi {
  private static ctx: SelectContext | null = null;
  /** 轮次/分类（新正方：入口页每个 queryCourse 分类一个 scope） */
  private static scopes: SelectScope[] = [];
  /** 每轮"已选人数"记录（捡漏判定：本轮少于上轮 = 有人退课） */
  private static lastSelected: Record<string, number> = {};

  /** 新正方请求字段白名单（对齐 zzxkYzb.js requestMap；多提交字段会被判异常请求） */
  private static readonly REQUEST_FIELDS: string[] = [
    'rwlx', 'xklc', 'xkly', 'bklx_id', 'sfkkjyxdxnxq', 'kzkcgs',
    'xqh_id', 'njdm_id_1', 'zyh_id_1', 'gnjkxdnj', 'zyh_id', 'zyfx_id', 'njdm_id', 'bh_id',
    'bjgkczxbbjwcx', 'xbm', 'xslbdm', 'mzm', 'xz', 'ccdm', 'xsbj', 'sfkknj', 'sfkkzy', 'kzybkxy',
    'sfznkx', 'zdkxms', 'sfkxq', 'bhbcyxkjxb', 'sfkcfx', 'kkbk', 'kkbkdj', 'bklbkcj', 'sfkgbcx',
    'sfrxtgkcxd', 'xkkz_xh', 'tykczgxdcs', 'xkxnm', 'xkxqm', 'kklxdm', 'bbhzxjxb', 'zxgbxkkg',
    'xkkz_id', 'rlkz', 'xkzgbj'
  ];

  static cachedContext(): SelectContext | null {
    return SelectApi.ctx;
  }

  /** 轮次/分类列表（页面标签用） */
  static scopeList(): SelectScope[] {
    return SelectApi.scopes;
  }

  /** 切换轮次（页面切换标签后调用；ctx 关键字段同步） */
  static applyScope(index: number): void {
    if (index < 0 || index >= SelectApi.scopes.length || SelectApi.ctx === null) {
      return;
    }
    const p: Record<string, string> = SelectApi.scopes[index].params;
    const xh: string = p['xkkz_xh'] !== undefined ? p['xkkz_xh'] : '';
    const kid: string = p['xkkz_id'] !== undefined ? p['xkkz_id'] : '';
    SelectApi.ctx.kklxdm = p['kklxdm'] !== undefined ? p['kklxdm'] : SelectApi.ctx.kklxdm;
    SelectApi.ctx.xkkzKey = xh.length > 0 ? 'xkkz_xh' : 'xkkz_id';
    SelectApi.ctx.xkkzId = xh.length > 0 ? xh : kid;
    if (p['njdm_id'] !== undefined && p['njdm_id'].length > 0) {
      SelectApi.ctx.njdmId = p['njdm_id'];
    }
    if (p['zyh_id'] !== undefined && p['zyh_id'].length > 0) {
      SelectApi.ctx.zyhId = p['zyh_id'];
    }
  }

  // ───────────────────────── 工具 ─────────────────────────

  /** 正则第一个捕获组 */
  private static textOf(text: string, pattern: string): string {
    const re: RegExp = new RegExp(pattern, 'i');
    const m: RegExpExecArray | null = re.exec(text);
    return m !== null && m[1] !== undefined ? m[1] : '';
  }

  /** 是否为登录页（会话过期） */
  private static isLoginPage(html: string): boolean {
    return html.indexOf('slogin.html') >= 0 || html.indexOf('notLogin') >= 0
      || html.indexOf('用户登录') >= 0;
  }

  /** 解析页面所有隐藏域（<input type="hidden" name=... value=...>） */
  private static hiddenFields(html: string): Record<string, string> {
    const out: Record<string, string> = {};
    const tagRe: RegExp = new RegExp('<input[^>]*type=["\']hidden["\'][^>]*>', 'gi');
    const nameRe: RegExp = new RegExp('name=["\']([^"\']+)["\']', 'i');
    const valueRe: RegExp = new RegExp('value=["\']([^"\']*)["\']', 'i');
    let m: RegExpExecArray | null = tagRe.exec(html);
    while (m !== null) {
      const tag: string = m[0];
      const nm: RegExpExecArray | null = nameRe.exec(tag);
      if (nm !== null && nm[1] !== undefined && nm[1].length > 0) {
        const vm: RegExpExecArray | null = valueRe.exec(tag);
        out[nm[1]] = vm !== null && vm[1] !== undefined ? vm[1] : '';
      }
      m = tagRe.exec(html);
    }
    return out;
  }

  /** 解析入口页分类：queryCourse(this,'kklxdm','xkkz','njdm','zyh') 或 first* 隐藏域变体 */
  private static parseCategories(html: string, fields: Record<string, string>): SelectCategory[] {
    const out: SelectCategory[] = [];
    const pat: string = "queryCourse\\(this,\\s*'([^']*)'\\s*,\\s*'([^']*)'\\s*,\\s*'([^']*)'\\s*,\\s*'([^']*)'";
    const re: RegExp = new RegExp(pat, 'g');
    let m: RegExpExecArray | null = re.exec(html);
    while (m !== null) {
      const c: SelectCategory = {
        kklxdm: m[1],
        xkkz: m[2],
        njdm: m[3],
        zyh: m[4]
      };
      out.push(c);
      m = re.exec(html);
    }
    if (out.length === 0) {
      const firstKklxdm: string = fields['firstKklxdm'] !== undefined ? fields['firstKklxdm'] : '';
      const firstXkkz: string = fields['firstXkkzId'] !== undefined ? fields['firstXkkzId'] : '';
      if (firstKklxdm.length > 0 && firstXkkz.length > 0) {
        const c: SelectCategory = {
          kklxdm: firstKklxdm,
          xkkz: firstXkkz,
          njdm: fields['firstNjdmId'] !== undefined ? fields['firstNjdmId'] : (fields['njdm_id'] ?? ''),
          zyh: fields['firstZyhId'] !== undefined ? fields['firstZyhId'] : (fields['zyh_id'] ?? '')
        };
        out.push(c);
      }
    }
    return out;
  }

  /** 按白名单构造请求参数（对齐 zzxkYzb.js requestMap） */
  private static zzxkParams(source: Record<string, string>, keyword: string,
    kspage: string, jspage: string, extra?: Record<string, string>): Record<string, string> {
    const out: Record<string, string> = {};
    for (let i: number = 0; i < SelectApi.REQUEST_FIELDS.length; i++) {
      const k: string = SelectApi.REQUEST_FIELDS[i];
      const v: string = source[k];
      if (v !== undefined) {
        out[k] = v;
      }
    }
    const jg1: string = source['jg_id_1'];
    if (jg1 !== undefined) {
      out['jg_id'] = jg1;
    }
    if (source['jxbzbkg'] === '1') {
      out['jxbzb'] = source['jxbzb'] !== undefined ? source['jxbzb'] : '';
    }
    if (source['jxbzhkg'] === '1') {
      out['zh'] = source['zh'] !== undefined ? source['zh'] : '';
    }
    if (keyword.length > 0) {
      out['filter_list[0]'] = keyword;
    }
    out['kspage'] = kspage;
    out['jspage'] = jspage;
    if (extra !== undefined) {
      const keys: string[] = Object.keys(extra);
      for (let i: number = 0; i < keys.length; i++) {
        out[keys[i]] = extra[keys[i]];
      }
    }
    return out;
  }

  /** 从 JSON 文本取数组（兼容 tmpList / courses / items / data / jxbList / 纯数组） */
  private static arrayOf(body: string): ESObject[] {
    let root: ESObject;
    try {
      root = JSON.parse(body);
    } catch (e) {
      return [];
    }
    if (root === null || root === undefined) {
      return [];
    }
    if (Array.isArray(root)) {
      return root as ESObject[];
    }
    const keys: string[] = ['tmpList', 'courses', 'items', 'data', 'jxbList', 'rows'];
    for (let i: number = 0; i < keys.length; i++) {
      const v: ESObject = root[keys[i]] as ESObject;
      if (v !== undefined && v !== null && Array.isArray(v)) {
        return v as ESObject[];
      }
    }
    return [];
  }

  /** 行对象 → Record<string,string>（非空值） */
  private static rowToRecord(row: ESObject): Record<string, string> {
    const out: Record<string, string> = {};
    const keys: string[] = Object.keys(row as Object);
    for (let i: number = 0; i < keys.length; i++) {
      const k: string = keys[i];
      const v: ESObject = row[k] as ESObject;
      if (v === undefined || v === null) {
        continue;
      }
      const s: string = `${v}`;
      if (s.length > 0 && s !== 'undefined' && s !== 'null') {
        out[k] = s;
      }
    }
    return out;
  }

  /** 去掉字段中的 HTML 标签（<br> → 空格） */
  private static clean(text: string): string {
    let t: string = text;
    t = t.replace(/<br\s*\/?>/gi, ' ');
    t = t.replace(/<[^>]+>/g, ' ');
    t = t.replace(/&nbsp;/g, ' ');
    return t.trim();
  }

  /** 行 + 基础参数 → 教学班/课程项（raw 保存合并参数，供选课提交时使用） */
  private static mapClass(row: ESObject, base: Record<string, string>): SelectableClass {
    const raw: Record<string, string> = {};
    const baseKeys: string[] = Object.keys(base);
    for (let i: number = 0; i < baseKeys.length; i++) {
      raw[baseKeys[i]] = base[baseKeys[i]];
    }
    const rowRec: Record<string, string> = SelectApi.rowToRecord(row);
    const rowKeys: string[] = Object.keys(rowRec);
    for (let i: number = 0; i < rowKeys.length; i++) {
      raw[rowKeys[i]] = rowRec[rowKeys[i]];
    }
    const capacityNum: number = Number(rowRec['jxbrl'] !== undefined ? rowRec['jxbrl'] : 0);
    const selectedNum: number = Number(rowRec['yxzrs'] !== undefined ? rowRec['yxzrs'] : 0);
    const item: SelectableClass = {
      kchId: rowRec['kch_id'] !== undefined ? rowRec['kch_id'] : (rowRec['kch'] ?? ''),
      jxbId: rowRec['jxb_id'] !== undefined ? rowRec['jxb_id'] : '',
      doJxbId: rowRec['do_jxb_id'] !== undefined ? rowRec['do_jxb_id'] : '',
      courseName: rowRec['kcmc'] !== undefined ? rowRec['kcmc'] : '',
      className: rowRec['jxbmc'] !== undefined ? rowRec['jxbmc'] : '',
      teacher: rowRec['jsxm'] !== undefined ? rowRec['jsxm'] : '',
      time: SelectApi.clean(rowRec['sksj'] !== undefined ? rowRec['sksj'] : ''),
      location: SelectApi.clean(rowRec['jxdd'] !== undefined ? rowRec['jxdd'] : ''),
      credit: rowRec['xf'] !== undefined ? rowRec['xf'] : (rowRec['jxbxf'] ?? ''),
      capacity: isNaN(capacityNum) ? 0 : capacityNum,
      selected: isNaN(selectedNum) ? 0 : selectedNum,
      chosen: (rowRec['sfxkbj'] !== undefined ? rowRec['sfxkbj'] : '') === '1',
      raw: raw
    };
    return item;
  }

  // ───────────────────────── 上下文（新正方两步） ─────────────────────────

  /**
   * 加载选课上下文：入口页 → 每个分类 POST Display 合并隐藏域 → scopes（含完整轮次参数）。
   */
  static async loadContext(force: boolean): Promise<SelectContext> {
    if (!force && SelectApi.ctx !== null && SelectApi.scopes.length > 0) {
      return SelectApi.ctx;
    }
    const res: HttpResult = await HttpClient.get(INDEX_URL);
    const html: string = res.body;
    if (SelectApi.isLoginPage(html)) {
      throw new Error('登录状态已过期，请重新登录后再试');
    }
    const indexFields: Record<string, string> = SelectApi.hiddenFields(html);
    const cats: SelectCategory[] = SelectApi.parseCategories(html, indexFields);
    const scopes: SelectScope[] = [];
    for (let i: number = 0; i < cats.length; i++) {
      const c: SelectCategory = cats[i];
      const fields: Record<string, string> = {};
      const fk: string[] = Object.keys(indexFields);
      for (let j: number = 0; j < fk.length; j++) {
        fields[fk[j]] = indexFields[fk[j]];
      }
      fields['kklxdm'] = c.kklxdm;
      fields['xkkz_id'] = c.xkkz;
      fields['njdm_id'] = c.njdm;
      fields['zyh_id'] = c.zyh;
      // ② Display：取该轮次的完整参数
      try {
        const form: Record<string, string> = {};
        form['xkkz_id'] = c.xkkz;
        form['kklxdm'] = c.kklxdm;
        form['xszxzt'] = '1';
        form['njdm_id'] = c.njdm;
        form['zyh_id'] = c.zyh;
        form['kspage'] = '0';
        form['jspage'] = '0';
        const dres: HttpResult = await HttpClient.postForm(DISPLAY_URL, form);
        const df: Record<string, string> = SelectApi.hiddenFields(dres.body);
        const dk: string[] = Object.keys(df);
        for (let j: number = 0; j < dk.length; j++) {
          fields[dk[j]] = df[dk[j]];
        }
      } catch (e) {
        LogStore.log('选课', '轮次参数', '失败', `kklxdm=${c.kklxdm} ${LogStore.errorOf(e as Object)}`);
      }
      // V9：first* 变体补 xkkz_xh / kklxmc
      const firstXh: string = indexFields['firstXkkzXh'] !== undefined ? indexFields['firstXkkzXh'] : '';
      if (firstXh.length > 0 && (fields['xkkz_xh'] === undefined || fields['xkkz_xh'].length === 0)) {
        fields['xkkz_xh'] = firstXh;
      }
      const firstMc: string = indexFields['firstKklxmc'] !== undefined ? indexFields['firstKklxmc'] : '';
      if (firstMc.length > 0 && (fields['kklxmc'] === undefined || fields['kklxmc'].length === 0)) {
        fields['kklxmc'] = firstMc;
      }
      const label: string = fields['kklxmc'] !== undefined && fields['kklxmc'].length > 0
        ? fields['kklxmc'] : SelectApi.roundLabel(c.kklxdm);
      const scope: SelectScope = {
        id: `zf-${i}-${c.kklxdm}`,
        label: label,
        term: `${fields['xkxnm'] !== undefined ? fields['xkxnm'] : ''}-${fields['xkxqm'] !== undefined ? fields['xkxqm'] : ''}`,
        params: fields
      };
      scopes.push(scope);
    }
    if (scopes.length === 0) {
      const fallback: SelectScope = { id: 'zf-default', label: '选课', term: '', params: indexFields };
      scopes.push(fallback);
    }
    SelectApi.scopes = scopes;
    // ctx：取第一个 scope 的关键字段
    const p0: Record<string, string> = scopes[0].params;
    const xh: string = p0['xkkz_xh'] !== undefined ? p0['xkkz_xh'] : '';
    const kid: string = p0['xkkz_id'] !== undefined ? p0['xkkz_id'] : '';
    const useV9: boolean = xh.length > 0;
    const ctx: SelectContext = {
      xkkzId: useV9 ? xh : kid,
      xkkzKey: useV9 ? 'xkkz_xh' : 'xkkz_id',
      kklxdm: p0['kklxdm'] !== undefined ? p0['kklxdm'] : '01',
      njdmId: p0['njdm_id'] !== undefined ? p0['njdm_id'] : '',
      zyhId: p0['zyh_id'] !== undefined ? p0['zyh_id'] : '',
      jgId: p0['jg_id'] !== undefined ? p0['jg_id'] : '',
      xqhId: p0['xqh_id'] !== undefined ? p0['xqh_id'] : '1',
      xkxnm: p0['xkxnm'] !== undefined ? p0['xkxnm'] : '',
      xkxqm: p0['xkxqm'] !== undefined ? p0['xkxqm'] : '',
      xklc: p0['xklc'] !== undefined ? p0['xklc'] : '1',
      rwlx: p0['rwlx'] !== undefined ? p0['rwlx'] : '1'
    };
    SelectApi.ctx = ctx;
    DataStore.put(KEY_SELECT_CTX, JSON.stringify(ctx));
    LogStore.log('选课', '上下文', '完成',
      `轮次${scopes.length}个 xkkz(${ctx.xkkzKey})=${ctx.xkkzId} kklxdm=${ctx.kklxdm} 学期${ctx.xkxnm}-${ctx.xkxqm}`);
    return ctx;
  }

  /** 课程类别代码 → 中文名 */
  private static roundLabel(kklxdm: string): string {
    if (kklxdm === '01') {
      return '必修课';
    }
    if (kklxdm === '02') {
      return '限选课';
    }
    if (kklxdm === '03') {
      return '任选课';
    }
    if (kklxdm === '04') {
      return '公选课';
    }
    if (kklxdm === '10') {
      return '体育课';
    }
    return `类别${kklxdm}`;
  }

  // ───────────────────────── 课程 / 教学班 ─────────────────────────

  /**
   * 课程列表（新正方：PartDisplay + 白名单参数 + filter_list[0] 关键字 + kspage/jspage）。
   */
  static async queryClasses(scope: SelectScope, keyword: string, kspage: string,
    jspage: string): Promise<SelectableClass[]> {
    const form: Record<string, string> = SelectApi.zzxkParams(scope.params, keyword, kspage, jspage);
    const res: HttpResult = await HttpClient.postForm(PART_DISPLAY_URL, form);
    const rows: ESObject[] = SelectApi.arrayOf(res.body);
    const out: SelectableClass[] = [];
    for (let i: number = 0; i < rows.length; i++) {
      const c: SelectableClass = SelectApi.mapClass(rows[i], scope.params);
      if (c.courseName.length === 0 && c.kchId.length === 0) {
        continue;
      }
      out.push(c);
    }
    LogStore.log('选课', '课程列表', out.length > 0 ? '成功' : '空',
      `轮次"${scope.label}" 关键字"${keyword}" → ${out.length} 门（${kspage}-${jspage}）`);
    return out;
  }

  /**
   * 教学班列表（新正方：cxJxbWithKch + 白名单参数 + kch_id）。
   * 返回的每项 raw = 课程行参数 + 教学班行参数（选课提交直接合并使用）。
   */
  static async loadSections(scope: SelectScope, cls: SelectableClass): Promise<SelectableClass[]> {
    const extra: Record<string, string> = {};
    extra['kch_id'] = cls.kchId;
    const form: Record<string, string> = SelectApi.zzxkParams(cls.raw, '', '1', '200', extra);
    const res: HttpResult = await HttpClient.postForm(SECTION_URL, form);
    const rows: ESObject[] = SelectApi.arrayOf(res.body);
    const out: SelectableClass[] = [];
    for (let i: number = 0; i < rows.length; i++) {
      const s: SelectableClass = SelectApi.mapClass(rows[i], cls.raw);
      if (s.kchId.length === 0) {
        s.kchId = cls.kchId;
      }
      if (s.courseName.length === 0) {
        s.courseName = cls.courseName;
      }
      out.push(s);
    }
    return out;
  }

  // ───────────────────────── 选课 / 退选 / 已选 ─────────────────────────

  /** 成功判定（"1" / {"flag":"1"} / 含"成功"） */
  private static isOk(body: string): boolean {
    const t: string = body.trim();
    if (t === '"1"' || t === '1') {
      return true;
    }
    if (t.indexOf('"flag":"1"') >= 0 || t.indexOf('"flag": "1"') >= 0) {
      return true;
    }
    if (t.indexOf('"success":true') >= 0 || t.indexOf('选课成功') >= 0) {
      return true;
    }
    return false;
  }

  /** 失败原因（msg / message 字段，否则截断原文） */
  private static failMessage(body: string, fallback: string): string {
    const t: string = body.trim();
    if (t.length === 0) {
      return fallback;
    }
    try {
      const obj: ESObject = JSON.parse(t);
      const msg: string = `${obj['msg'] !== undefined ? obj['msg'] : (obj['message'] !== undefined ? obj['message'] : '')}`;
      if (msg.length > 0 && msg !== 'undefined') {
        return msg;
      }
    } catch (e) {
      // 非 JSON
    }
    return t.length > 60 ? `${t.substring(0, 60)}…` : t;
  }

  /**
   * 选课（新正方）：values = **课程行参数 + 教学班行参数** 合并后，覆盖关键字段再提交。
   */
  static async chooseClass(scope: SelectScope, kchId: string, courseName: string,
    section: SelectableClass): Promise<SelectResult> {
    const jxbIds: string = section.doJxbId.length > 0 ? section.doJxbId : section.jxbId;
    if (kchId.length === 0 || jxbIds.length === 0) {
      const bad: SelectResult = { ok: false, message: '缺少课程/教学班参数，请重新查询课程列表' };
      return bad;
    }
    const values: Record<string, string> = {};
    const rk: string[] = Object.keys(section.raw);
    for (let i: number = 0; i < rk.length; i++) {
      values[rk[i]] = section.raw[rk[i]];
    }
    values['jxb_ids'] = jxbIds;
    values['kch_id'] = kchId;
    values['kcmc'] = courseName;
    values['kklxdm'] = scope.params['kklxdm'] !== undefined ? scope.params['kklxdm'] : '';
    const xh: string = scope.params['xkkz_xh'] !== undefined ? scope.params['xkkz_xh'] : '';
    if (xh.length > 0) {
      values['xkkz_xh'] = xh;
    }
    const kid: string = scope.params['xkkz_id'] !== undefined ? scope.params['xkkz_id'] : '';
    if (kid.length > 0) {
      values['xkkz_id'] = kid;
    }
    const res: HttpResult = await HttpClient.postForm(CHOOSE_URL, values);
    const ok: boolean = SelectApi.isOk(res.body);
    LogStore.log('选课', '提交选课', ok ? '成功' : '失败',
      `${courseName} http=${res.code} 参数${Object.keys(values).length}项`);
    const result: SelectResult = {
      ok: ok,
      message: ok ? `已选上「${courseName}」`
        : SelectApi.failMessage(res.body, '选课失败（可能时间冲突、容量已满或不在选课时间内）')
    };
    return result;
  }

  /** 退选（新正方：kch_id + jxb_ids + xkxnm + xkxqm + txbsfrl=0） */
  static async dropClass(item: SelectedCourseItem): Promise<SelectResult> {
    const jxbIds: string = item.doJxbId.length > 0 ? item.doJxbId : item.jxbId;
    if (item.kchId.length === 0 || jxbIds.length === 0) {
      const bad: SelectResult = { ok: false, message: '缺少课程/教学班参数' };
      return bad;
    }
    const form: Record<string, string> = {};
    form['kch_id'] = item.kchId;
    form['jxb_ids'] = jxbIds;
    form['xkxnm'] = item.xkxnm;
    form['xkxqm'] = item.xkxqm;
    form['txbsfrl'] = '0';
    const res: HttpResult = await HttpClient.postForm(DROP_URL, form);
    const ok: boolean = SelectApi.isOk(res.body);
    const result: SelectResult = {
      ok: ok,
      message: ok ? `已退选「${item.courseName}」`
        : SelectApi.failMessage(res.body, '退选失败（可能不在退课时间范围内）')
    };
    return result;
  }

  /** 已选课程（白名单参数） */
  static async selectedCourses(scope: SelectScope): Promise<SelectedCourseItem[]> {
    const form: Record<string, string> = SelectApi.zzxkParams(scope.params, '', '1', '200');
    const res: HttpResult = await HttpClient.postForm(CHOOSED_URL, form);
    const rows: ESObject[] = SelectApi.arrayOf(res.body);
    const out: SelectedCourseItem[] = [];
    for (let i: number = 0; i < rows.length; i++) {
      const rec: Record<string, string> = SelectApi.rowToRecord(rows[i]);
      const item: SelectedCourseItem = {
        kchId: rec['kch_id'] !== undefined ? rec['kch_id'] : (rec['kch'] ?? ''),
        jxbId: rec['jxb_id'] !== undefined ? rec['jxb_id'] : '',
        doJxbId: rec['do_jxb_id'] !== undefined ? rec['do_jxb_id'] : '',
        courseName: rec['kcmc'] !== undefined ? rec['kcmc'] : '',
        className: rec['jxbmc'] !== undefined ? rec['jxbmc'] : '',
        teacher: rec['jsxm'] !== undefined ? rec['jsxm'] : '',
        time: SelectApi.clean(rec['sksj'] !== undefined ? rec['sksj'] : ''),
        location: SelectApi.clean(rec['jxdd'] !== undefined ? rec['jxdd'] : ''),
        credit: rec['xf'] !== undefined ? rec['xf'] : (rec['jxbxf'] ?? ''),
        xkxnm: scope.params['xkxnm'] !== undefined ? scope.params['xkxnm'] : '',
        xkxqm: scope.params['xkxqm'] !== undefined ? scope.params['xkxqm'] : ''
      };
      if (item.courseName.length > 0) {
        out.push(item);
      }
    }
    return out;
  }

  // ───────────────────────── 队列 / 策略 / 抢课 ─────────────────────────

  /** 队列深拷贝（ArkTS 禁用对象展开，用于 UI 刷新时替换 @State 引用） */
  static copyQueue(list: GrabTarget[]): GrabTarget[] {
    const out: GrabTarget[] = [];
    for (let i: number = 0; i < list.length; i++) {
      const t: GrabTarget = list[i];
      const c: GrabTarget = {
        kchId: t.kchId,
        courseName: t.courseName,
        teacher: t.teacher,
        time: t.time,
        jxbId: t.jxbId,
        doJxbId: t.doJxbId,
        enabled: t.enabled,
        status: t.status,
        attempts: t.attempts,
        matchMode: t.matchMode === 'fuzzy' ? 'fuzzy' : 'exact'
      };
      out.push(c);
    }
    return out;
  }

  static loadQueue(): GrabTarget[] {
    const raw: string = DataStore.get(DataStore.KEY_GRAB_QUEUE);
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsed: GrabTarget[] = JSON.parse(raw) as GrabTarget[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
      return [];
    }
  }

  static saveQueue(list: GrabTarget[]): void {
    DataStore.put(DataStore.KEY_GRAB_QUEUE, JSON.stringify(list));
  }

  /** 读取策略（含重试间隔/最大重试/并行/延时/捡漏；缺失字段归一默认值） */
  static loadPolicy(): GrabPolicy {
    const raw: string = DataStore.get(DataStore.KEY_GRAB_POLICY);
    if (raw.length > 0) {
      try {
        const p: GrabPolicy = JSON.parse(raw) as GrabPolicy;
        const out: GrabPolicy = {
          intervalSec: p.intervalSec > 0 ? p.intervalSec : 3,
          maxRounds: p.maxRounds >= 0 && p.maxRounds !== undefined ? p.maxRounds : 200,
          continueAfterSuccess: p.continueAfterSuccess === true,
          parallelWorkers: p.parallelWorkers > 0 ? p.parallelWorkers : 1,
          delaySec: p.delaySec > 0 ? p.delaySec : 0,
          leakMode: p.leakMode === true
        };
        return out;
      } catch (e) {
        // 回落默认
      }
    }
    const def: GrabPolicy = {
      intervalSec: 3,
      maxRounds: 200,
      continueAfterSuccess: true,
      parallelWorkers: 1,
      delaySec: 0,
      leakMode: false
    };
    return def;
  }

  static savePolicy(policy: GrabPolicy): void {
    DataStore.put(DataStore.KEY_GRAB_POLICY, JSON.stringify(policy));
  }

  private static targetKey(t: GrabTarget): string {
    const jxb: string = t.doJxbId.length > 0 ? t.doJxbId : t.jxbId;
    return `${t.kchId}|${jxb}`;
  }

  /** 入队（已存在返回 false） */
  static enqueue(list: GrabTarget[], target: GrabTarget): boolean {
    const key: string = SelectApi.targetKey(target);
    for (let i: number = 0; i < list.length; i++) {
      if (SelectApi.targetKey(list[i]) === key) {
        return false;
      }
    }
    list.push(target);
    SelectApi.saveQueue(list);
    return true;
  }

  /** 出队 */
  static dequeue(list: GrabTarget[], target: GrabTarget): void {
    const key: string = SelectApi.targetKey(target);
    const kept: GrabTarget[] = [];
    for (let i: number = 0; i < list.length; i++) {
      if (SelectApi.targetKey(list[i]) !== key) {
        kept.push(list[i]);
      }
    }
    list.length = 0;
    for (let i: number = 0; i < kept.length; i++) {
      list.push(kept[i]);
    }
    SelectApi.saveQueue(list);
  }

  /** 教学班筛选（对应参考项目 AcademicCourseFilter） */
  static filterClasses(list: SelectableClass[], filter: ClassFilter): SelectableClass[] {
    const out: SelectableClass[] = [];
    const teacher: string = filter.teacher.trim();
    const time: string = filter.time.trim();
    const location: string = filter.location.trim();
    const credit: string = filter.credit.trim();
    for (let i: number = 0; i < list.length; i++) {
      const c: SelectableClass = list[i];
      if (teacher.length > 0 && c.teacher.indexOf(teacher) < 0) {
        continue;
      }
      if (time.length > 0 && c.time.indexOf(time) < 0) {
        continue;
      }
      if (location.length > 0 && c.location.indexOf(location) < 0) {
        continue;
      }
      if (credit.length > 0 && c.credit !== credit) {
        continue;
      }
      if (filter.onlyAvailable && !(c.capacity > 0 && c.selected < c.capacity)) {
        continue;
      }
      out.push(c);
    }
    return out;
  }

  /**
   * 尝试抢一个目标：取教学班 → 精确/模糊匹配 → 有空位即提交；顺带捡漏判定。
   * @returns 本轮日志文本
   */
  private static async attemptTarget(scope: SelectScope, t: GrabTarget,
    policy: GrabPolicy): Promise<string> {
    t.attempts = t.attempts + 1;
    t.status = 'waiting';
    try {
      const probe: SelectableClass = {
        kchId: t.kchId, jxbId: t.jxbId, doJxbId: t.doJxbId,
        courseName: t.courseName, className: '', teacher: t.teacher, time: t.time,
        location: '', credit: '', capacity: 0, selected: 0, chosen: false,
        raw: scope.params
      };
      const list: SelectableClass[] = await SelectApi.loadSections(scope, probe);
      if (list.length === 0) {
        return `${t.courseName}：未取到教学班（可能不在本轮选课范围）`;
      }
      let candidate: SelectableClass | null = null;
      let leakHit: boolean = false;
      let cap: string = '--';
      let sel: string = '--';
      for (let i: number = 0; i < list.length; i++) {
        const c: SelectableClass = list[i];
        const hit: boolean = t.matchMode === 'fuzzy'
          ? true
          : (t.doJxbId.length > 0 ? (c.doJxbId === t.doJxbId || c.jxbId === t.jxbId) : true);
        if (!hit) {
          continue;
        }
        const key: string = `${t.kchId}|${c.jxbId}|${c.doJxbId}`;
        const last: number = SelectApi.lastSelected[key];
        if (last !== undefined && c.selected < last) {
          leakHit = true;
        }
        SelectApi.lastSelected[key] = c.selected;
        if (cap === '--') {
          cap = `${c.capacity}`;
          sel = `${c.selected}`;
        }
        if (c.capacity > 0 && c.selected < c.capacity) {
          candidate = c;
          break;
        }
      }
      if (candidate === null) {
        if (leakHit) {
          return `${t.courseName}：有人退课但暂无空位（${sel}/${cap}）`;
        }
        return `${t.courseName}：满员（${sel}/${cap}）`;
      }
      const reason: string = (leakHit && policy.leakMode) ? '捡漏命中（有人退课）' : '发现空位';
      const r: SelectResult = await SelectApi.chooseClass(scope, t.kchId, t.courseName, candidate);
      if (r.ok) {
        t.status = 'success';
        return `${t.courseName}：已抢到 ✓ ${reason}（${candidate.selected}/${candidate.capacity}）`;
      }
      t.status = 'failed';
      return `${t.courseName}：提交失败（${r.message}）`;
    } catch (e) {
      t.status = 'failed';
      return `${t.courseName}：请求异常（${LogStore.errorOf(e as Object)}）`;
    }
  }

  /**
   * 队列抢课：① 延时启动 → ② 每 `intervalSec` 秒一轮 → ③ 串行/并行尝试队列目标
   * → ④ 有空位立即提交（支持捡漏判定）→ 状态/尝试次数实时回写。
   */
  static async runQueue(scope: SelectScope, targets: GrabTarget[], policy: GrabPolicy,
    isCancelled: () => boolean, onTick: (text: string) => void,
    onProgress: (list: GrabTarget[]) => void): Promise<SelectResult> {
    if (policy.delaySec > 0) {
      onTick(`已设定延时启动：${policy.delaySec} 秒后开始（可点「停止抢课」取消）`);
      let waitedDelay: number = 0;
      let nextNotice: number = 5;
      while (waitedDelay < policy.delaySec * 1000 && !isCancelled()) {
        await SelectApi.sleep(500);
        waitedDelay += 500;
        const leftSec: number = Math.ceil((policy.delaySec * 1000 - waitedDelay) / 1000);
        if (leftSec <= nextNotice) {
          onTick(`延时启动倒计时：${leftSec} 秒`);
          nextNotice = nextNotice - 5;
        }
      }
      if (isCancelled()) {
        const cancelDelay: SelectResult = { ok: false, message: '已取消（延时阶段）' };
        return cancelDelay;
      }
      onTick('延时结束，开始抢课');
    }

    const workers: number = policy.parallelWorkers > 0 ? policy.parallelWorkers : 1;
    const intervalMs: number = (policy.intervalSec > 0 ? policy.intervalSec : 3) * 1000;
    let round: number = 0;
    let successCount: number = 0;
    while (!isCancelled()) {
      const pending: GrabTarget[] = [];
      for (let i: number = 0; i < targets.length; i++) {
        const t: GrabTarget = targets[i];
        if (t.enabled && t.status !== 'success') {
          pending.push(t);
        }
      }
      if (pending.length === 0) {
        const done: SelectResult = {
          ok: successCount > 0,
          message: successCount > 0 ? `队列已全部完成（成功 ${successCount} 门）` : '队列为空或已全部完成'
        };
        return done;
      }
      round++;
      if (policy.maxRounds > 0 && round > policy.maxRounds) {
        const over: SelectResult = {
          ok: successCount > 0,
          message: `已达最大重试次数 ${policy.maxRounds}（成功 ${successCount} 门）`
        };
        return over;
      }
      const mode: string = workers > 1 ? `并行 ${workers} 路` : '顺序';
      onTick(`第 ${round} 轮：待抢 ${pending.length} 门 · ${mode} · 重试间隔 ${policy.intervalSec}s`
        + (policy.leakMode ? ' · 捡漏开启' : ''));

      let index: number = 0;
      while (index < pending.length && !isCancelled()) {
        const batch: GrabTarget[] = [];
        for (let k: number = 0; k < workers && index < pending.length; k++) {
          batch.push(pending[index]);
          index++;
        }
        const tasks: Promise<string>[] = [];
        for (let b: number = 0; b < batch.length; b++) {
          tasks.push(SelectApi.attemptTarget(scope, batch[b], policy));
        }
        try {
          const logs: string[] = await Promise.all(tasks);
          for (let l: number = 0; l < logs.length; l++) {
            onTick(logs[l]);
          }
        } catch (e) {
          onTick(`本轮请求异常：${LogStore.errorOf(e as Object)}`);
        }
        for (let b: number = 0; b < batch.length; b++) {
          if (batch[b].status === 'success') {
            successCount++;
          }
        }
        onProgress(SelectApi.copyQueue(targets));
        SelectApi.saveQueue(targets);
        if (!policy.continueAfterSuccess) {
          for (let b: number = 0; b < batch.length; b++) {
            if (batch[b].status === 'success') {
              const one: SelectResult = { ok: true, message: `已抢到「${batch[b].courseName}」` };
              return one;
            }
          }
        }
      }

      let waited: number = 0;
      while (waited < intervalMs && !isCancelled()) {
        await SelectApi.sleep(500);
        waited += 500;
      }
    }
    const stopped: SelectResult = { ok: false, message: `已停止抢课（成功 ${successCount} 门）` };
    return stopped;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
