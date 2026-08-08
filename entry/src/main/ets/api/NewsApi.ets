/**
 * 农大新闻 API — 解析 news.xjau.edu.cn
 */
import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';

export class NewsItem {
  title: string = '';
  url: string = '';
  date: string = '';
  thumb: string = '';
}

export class ContentBlock {
  type: string = 'text'; // 'text' | 'image'
  value: string = '';
}

export class NewsDetail {
  title: string = '';
  date: string = '';
  source: string = '';
  author: string = '';
  views: string = '';
  editor: string = '';
  blocks: ContentBlock[] = [];
}

/** 搜索结果项 */
export class SearchItem {
  title: string = '';
  url: string = '';
  date: string = '';
  category: string = '';
  source: string = '';
  thumb: string = '';
}

export class NewsApi {
  static readonly BASE: string = 'https://news.xjau.edu.cn';
  /** 板块 → 列表页 URL */
  static readonly SECTION_URLS: Record<string, string> = {
    '农大要闻': 'https://news.xjau.edu.cn/ndyw/list.htm',
    '综合新闻': 'https://news.xjau.edu.cn/xydt/list.htm',
    '教学科研': 'https://news.xjau.edu.cn/kxyj/list.htm',
    '媒体农大': 'https://news.xjau.edu.cn/mtnd/list.htm'
  };
  /** 已下载的图片（避免重复请求），退出时清空 */
  private static imgCache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();

  /** 抓指定板块列表页（pageIndex 从 1 开始，>1 请求 listN.htm）→ 并行抓每篇详情取第一张图做缩略图 */
  static async fetchPage(section: string, pageIndex: number): Promise<NewsItem[]> {
    const base: string = NewsApi.SECTION_URLS[section] ?? NewsApi.SECTION_URLS['农大要闻'];
    let url: string = base;
    if (pageIndex > 1) {
      url = base.replace(/list\.htm$/i, `list${pageIndex}.htm`);
    }
    const resp = await http.createHttp().request(url, { expectDataType: http.HttpDataType.STRING });
    const items: NewsItem[] = NewsApi.parseList(resp.result as string);
    const jobs: Promise<void>[] = [];
    for (let i = 0; i < items.length; i++) {
      jobs.push(NewsApi.fillThumb(items[i]));
    }
    await Promise.all(jobs);
    return items;
  }

  private static async fillThumb(item: NewsItem): Promise<void> {
    // 外链（非本站）不抓缩略图/详情（媒体农大等外部转载）
    if (!item.url.startsWith(NewsApi.BASE)) { return; }
    try {
      const d: NewsDetail = await NewsApi.fetchDetailByUrl(item.url);
      for (const b of d.blocks) {
        if (b.type === 'image') { item.thumb = b.value; return; }
      }
    } catch (e) {
      // 单篇失败不影响列表
    }
  }

  private static parseList(html: string): NewsItem[] {
    const items: NewsItem[] = [];
    const itemRegex = /<a[^>]*class="[^"]*column-news-item[^"]*"[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi;
    let itMatch: RegExpExecArray | null;
    while ((itMatch = itemRegex.exec(html)) !== null) {
      const href: string = itMatch[1];
      const body: string = itMatch[2];
      const tMatch = /<span[^>]*class="[^"]*column-news-title[^"]*"[^>]*>([\s\S]*?)<\/span>/i.exec(body);
      const dMatch = /<span[^>]*class="[^"]*column-news-date[^"]*"[^>]*>([\s\S]*?)<\/span>/i.exec(body);
      // 媒体农大等板块的 href 可能是完整绝对 URL，不能盲目拼接 BASE
      const url: string = href.startsWith('http') ? href : NewsApi.BASE + href;
      items.push({
        title: tMatch !== null ? tMatch[1].replace(/<[^>]+>/g, '').trim() : '',
        url: url,
        date: dMatch !== null ? dMatch[1].replace(/<[^>]+>/g, '').trim() : '',
        thumb: ''
      });
    }
    return items;
  }

  static async fetchDetailByUrl(url: string): Promise<NewsDetail> {
    const resp = await http.createHttp().request(url, { expectDataType: http.HttpDataType.STRING });
    return NewsApi.parseDetail(resp.result as string);
  }

  /** 下载图片（带防盗链请求头）→ PixelMap，带内存缓存 */
  static async fetchImage(url: string): Promise<image.PixelMap> {
    const cached = NewsApi.imgCache.get(url);
    if (cached !== undefined) {
      return cached;
    }
    const resp = await http.createHttp().request(url, {
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      header: {
        'Referer': NewsApi.BASE + '/',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
        'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9'
      }
    });
    const buffer: ArrayBuffer = resp.result as ArrayBuffer;
    const src: image.ImageSource = image.createImageSource(buffer);
    const pm: image.PixelMap = await src.createPixelMap();
    src.release();
    NewsApi.imgCache.set(url, pm);
    return pm;
  }

  /** 是否本站链接（http/https 都算） */
  static isLocalUrl(url: string): boolean {
    return url.startsWith('https://news.xjau.edu.cn') || url.startsWith('http://news.xjau.edu.cn');
  }

  /** 退出应用时清理图片缓存 */
  static clearCache(): void {
    NewsApi.imgCache.clear();
  }

  /** 站内搜索：POST 官方搜索接口，按页返回（每页 10 条左右） */
  static async search(keyword: string, pageIndex: number): Promise<SearchItem[]> {
    const jsonStr: string = JSON.stringify([
      { 'field': 'pageIndex', 'value': pageIndex },
      { 'field': 'group', 'value': 0 },
      { 'field': 'searchType', 'value': 1 },
      { 'field': 'keyword', 'value': keyword },
      { 'field': 'recommend', 'value': '' },
      { 'field': 4, 'value': '' },
      { 'field': 5, 'value': '' },
      { 'field': 6, 'value': '' },
      { 'field': 7, 'value': '' }
    ]);
    const encoder: util.TextEncoder = new util.TextEncoder();
    const bytes: Uint8Array = encoder.encodeInto(jsonStr);
    const b64: util.Base64Helper = new util.Base64Helper();
    const searchInfo: string = b64.encodeToStringSync(bytes);

    const resp = await http.createHttp().request(
      'https://news.xjau.edu.cn/_web/_search/api/searchCon/create.rst?_p=YXM9NjEmdD04NjcmZD0yNzI1JnA9MSZtPVNOJg__&tt=' + Math.random(),
      {
        method: http.RequestMethod.POST,
        header: {
          'Referer': 'https://news.xjau.edu.cn/main.htm',
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36'
        },
        extraData: `searchInfo=${searchInfo}`,
        expectDataType: http.HttpDataType.STRING
      });
    const json: Record<string, Object> = JSON.parse(resp.result as string) as Record<string, Object>;
    const html: string = typeof json['data'] === 'string' ? json['data'] as string : '';
    return NewsApi.parseSearch(html);
  }

  /** 解析搜索结果 data HTML → SearchItem[] */
  private static parseSearch(html: string): SearchItem[] {
    const items: SearchItem[] = [];
    const itemRegex = /<div class="result_item[\s\S]*?(?=<div class="result_item|$)/gi;
    let itMatch: RegExpExecArray | null;
    while ((itMatch = itemRegex.exec(html)) !== null) {
      const block: string = itMatch[0];
      const aMatch = /<a href='([^']*)'[^>]*>([\s\S]*?)<\/a>/i.exec(block);
      if (aMatch === null) { continue; }
      const item: SearchItem = new SearchItem();
      item.url = aMatch[1];
      item.title = aMatch[2].replace(/<[^>]+>/g, '').trim();
      const dm = /发布时间:([\d-]+)/.exec(block);
      item.date = dm !== null ? dm[1] : '';
      const cm = /目录:([^<]*(?:<[^>]+>[^<]*)*)<\/span>/i.exec(block);
      item.category = cm !== null ? cm[1].replace(/<[^>]+>/g, '').trim() : '';
      const sm = /出处:([^<]*(?:<[^>]+>[^<]*)*)<\/span>/i.exec(block);
      item.source = sm !== null ? sm[1].replace(/<[^>]+>/g, '').trim() : '';
      const im = /<img[^>]*class="item_image"[^>]*src="([^"]*)"/i.exec(block);
      if (im !== null) {
        let src: string = im[1];
        if (src.startsWith('/')) { src = NewsApi.BASE + src; }
        item.thumb = src;
      }
      items.push(item);
    }
    return items;
  }

  private static parseDetail(html: string): NewsDetail {
    const d: NewsDetail = new NewsDetail();
    // 标题（双引号或单引号都兼容）
    const tMatch = /<h1[^>]*class=['"][^'"]*arti-title[^'"]*['"][^>]*>([\s\S]*?)<\/h1>/i.exec(html);
    d.title = tMatch !== null ? tMatch[1].replace(/<[^>]+>/g, '').trim() : '';
    // 元信息
    const mMatch = /<p[^>]*class=['"][^'"]*arti-metas[^'"]*['"][^>]*>([\s\S]*?)<\/p>/i.exec(html);
    if (mMatch !== null) {
      const meta: string = mMatch[1];
      const dm = /发布时间[：:]\s*(\d{4}-\d{2}-\d{2})/.exec(meta);
      d.date = dm !== null ? dm[1] : '';
      const sm = /来源[：:]\s*(.+?)(?:<\/span>|$)/i.exec(meta);
      d.source = sm !== null ? sm[1].replace(/<[^>]+>/g, '').trim() : '';
      const am = /作者[：:]\s*(.+?)(?:摄影|<\/span>|$)/i.exec(meta);
      d.author = am !== null ? am[1].replace(/<[^>]+>/g, '').trim() : '';
      // 浏览量：浏览次数:<span class="WP_VisitCount">1513</span>
      const vm = /浏览次数[：:]\s*(?:<[^>]+>)*\s*([\d,]+)/i.exec(meta);
      d.views = vm !== null ? vm[1].trim() : '';
    }
    // 编辑 / 审核人：<div class="read" style="float:right">编辑:xxx 审核人:yyy</div>
    const readRegex = /<div[^>]*class="[^"]*read[^"]*"[^>]*>([\s\S]*?)<\/div>/gi;
    let readMatch: RegExpExecArray | null;
    while ((readMatch = readRegex.exec(html)) !== null) {
      const txt: string = readMatch[1].replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').trim();
      if (txt.indexOf('编辑') >= 0 || txt.indexOf('审核') >= 0) {
        d.editor = txt;
        break;
      }
    }
    // 正文区：wp_articlecontent（注意该站用单引号 class！）
    const bodyMatch = /<div[^>]*class=['"][^'"]*wp_articlecontent[^'"]*['"][^>]*>([\s\S]*?)<\/div>/i.exec(html);
    const bodyHtml: string = bodyMatch !== null ? bodyMatch[1] : '';
    // 按 <p> 顺序解析
    const pRegex = /<p[^>]*>([\s\S]*?)<\/p>/gi;
    let pMatch: RegExpExecArray | null;
    while ((pMatch = pRegex.exec(bodyHtml)) !== null) {
      const inner: string = pMatch[1];
      const imgRegex = /<img[^>]*src=['"]([^'"]*)['"][^>]*>/gi;
      let hasImg = false;
      let imgMatch: RegExpExecArray | null;
      while ((imgMatch = imgRegex.exec(inner)) !== null) {
        hasImg = true;
        let src: string = imgMatch[1];
        if (src.startsWith('/')) { src = NewsApi.BASE + src; }
        const block: ContentBlock = new ContentBlock();
        block.type = 'image';
        block.value = src;
        d.blocks.push(block);
      }
      if (!hasImg) {
        const text: string = inner.replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').trim();
        if (text.length > 0) {
          const block: ContentBlock = new ContentBlock();
          block.type = 'text';
          block.value = text;
          d.blocks.push(block);
        }
      }
    }
    return d;
  }
}
