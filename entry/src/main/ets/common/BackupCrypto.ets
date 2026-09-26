/**
 * 备份文件加密工具（BackupCrypto）—— 专属加密格式 v2（扩展名 .xnd）
 *
 * 设计目标：不依赖任何平台加密 API（cryptoFramework 对大数据单次 doFinal 存在限制，
 * 曾致导出失败），全部为纯 ArkTS 算术实现，行为完全确定、跨设备一致。
 *
 * 算法（标准构造，非自创）：
 *   key  = SHA-256(盐 + '|' + 密码)                      —— 32 字节
 *   ks_i = SHA-256(key || u32be(i))                       —— 计数器模式密钥流（i = 0,1,2…）
 *   ct   = 明文 XOR ks                                    —— 流加密
 *   tag  = SHA-256(key || 明文) 前 16 字节                 —— 完整性/密码校验
 *
 * 容器布局（.xnd）：
 *   [8B magic "XNDBKP01"][4B 明文长度 小端][16B tag][密文]
 *
 * - 其他软件无法打开（专属格式），必须在本 App 内输入密码解密导入
 * - 密码错误：tag 校验必然失败 → 抛「wrong password or corrupted file」，提示「密码错误」
 * - SHA-256 为 FIPS 180-4 标准实现（纯 JS 位运算，步骤均 >>>0 保持无符号）
 * - UTF-8 编解码亦为纯 JS 实现（不依赖 @ohos.buffer，规避真机与 Node 的行为差异）
 */
const BACKUP_MAGIC_TEXT: string = 'XNDBKP01';
const KEY_SALT: string = 'xjau-helper-backup-xnd-v1';
const MAGIC_LEN: number = 8;
const LEN_LEN: number = 4;
const TAG_LEN: number = 16;
const HEADER_LEN: number = MAGIC_LEN + LEN_LEN + TAG_LEN;

/** SHA-256 轮常量 */
const SHA_K: number[] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

/** 32 位循环右移（无符号） */
function rotr(x: number, n: number): number {
  return ((x >>> n) | (x << (32 - n))) >>> 0;
}

/** SHA-256（FIPS 180-4），返回 32 字节摘要 */
export function sha256(msg: Uint8Array): Uint8Array {
  const h: number[] = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  ];
  const bitLen: number = msg.length * 8;
  // 填充：0x80 + 0x00… + 8 字节大端位长，总长对齐 64
  const total: number = (((msg.length + 9) + 63) >> 6) << 6;
  const m: Uint8Array = new Uint8Array(total);
  m.set(msg, 0);
  m[msg.length] = 0x80;
  // 末尾 8 字节大端位长：高 4 字节恒 0（备份数据远小于 512MB），低 4 字节为 bitLen
  m[total - 8] = 0;
  m[total - 7] = 0;
  m[total - 6] = 0;
  m[total - 5] = 0;
  m[total - 4] = (bitLen >>> 24) & 0xff;
  m[total - 3] = (bitLen >>> 16) & 0xff;
  m[total - 2] = (bitLen >>> 8) & 0xff;
  m[total - 1] = bitLen & 0xff;

  const w: Uint32Array = new Uint32Array(64);
  for (let off: number = 0; off < total; off += 64) {
    for (let i: number = 0; i < 16; i++) {
      const j: number = off + i * 4;
      w[i] = (((m[j] << 24) >>> 0) | (m[j + 1] << 16) | (m[j + 2] << 8) | m[j + 3]) >>> 0;
    }
    for (let i: number = 16; i < 64; i++) {
      const x: number = w[i - 15];
      const y: number = w[i - 2];
      const s0: number = (rotr(x, 7) ^ rotr(x, 18) ^ (x >>> 3)) >>> 0;
      const s1: number = (rotr(y, 17) ^ rotr(y, 19) ^ (y >>> 10)) >>> 0;
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }
    let a: number = h[0];
    let b: number = h[1];
    let c: number = h[2];
    let d: number = h[3];
    let e: number = h[4];
    let f: number = h[5];
    let g: number = h[6];
    let hh: number = h[7];
    for (let i: number = 0; i < 64; i++) {
      const s1: number = (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) >>> 0;
      const ch: number = ((e & f) ^ ((~e) & g)) >>> 0;
      const t1: number = (hh + s1 + ch + SHA_K[i] + w[i]) >>> 0;
      const s0: number = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) >>> 0;
      const maj: number = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
      const t2: number = (s0 + maj) >>> 0;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) >>> 0;
    }
    h[0] = (h[0] + a) >>> 0;
    h[1] = (h[1] + b) >>> 0;
    h[2] = (h[2] + c) >>> 0;
    h[3] = (h[3] + d) >>> 0;
    h[4] = (h[4] + e) >>> 0;
    h[5] = (h[5] + f) >>> 0;
    h[6] = (h[6] + g) >>> 0;
    h[7] = (h[7] + hh) >>> 0;
  }
  const out: Uint8Array = new Uint8Array(32);
  for (let i: number = 0; i < 8; i++) {
    out[i * 4] = (h[i] >>> 24) & 0xff;
    out[i * 4 + 1] = (h[i] >>> 16) & 0xff;
    out[i * 4 + 2] = (h[i] >>> 8) & 0xff;
    out[i * 4 + 3] = h[i] & 0xff;
  }
  return out;
}

/**
 * 字符串 → UTF-8 字节（纯 JS 实现：不依赖 @ohos.buffer，避免真机与 Node 行为差异；
 * 代理对按 4 字节编码，孤立代理按 U+FFFD 替换）
 */
function utf8Bytes(s: string): Uint8Array {
  const out: number[] = [];
  for (let i: number = 0; i < s.length; i++) {
    const c: number = s.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
      const lo: number = s.charCodeAt(i + 1);
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        const cp: number = 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00);
        out.push(0xF0 | ((cp >> 18) & 0x3F));
        out.push(0x80 | ((cp >> 12) & 0x3F));
        out.push(0x80 | ((cp >> 6) & 0x3F));
        out.push(0x80 | (cp & 0x3F));
        i++;
        continue;
      }
    }
    if (c >= 0xD800 && c <= 0xDFFF) {
      // 孤立代理 → U+FFFD
      out.push(0xEF, 0xBF, 0xBD);
    } else if (c < 0x80) {
      out.push(c);
    } else if (c < 0x800) {
      out.push(0xC0 | (c >> 6));
      out.push(0x80 | (c & 0x3F));
    } else {
      out.push(0xE0 | (c >> 12));
      out.push(0x80 | ((c >> 6) & 0x3F));
      out.push(0x80 | (c & 0x3F));
    }
  }
  return new Uint8Array(out);
}

/** UTF-8 字节 → 字符串（纯 JS 实现；非法字节按 U+FFFD） */
function utf8Text(bytes: Uint8Array): string {
  const codes: number[] = [];
  let i: number = 0;
  while (i < bytes.length) {
    const c: number = bytes[i];
    let cp: number = 0;
    let n: number = 1;
    if (c < 0x80) {
      cp = c;
      n = 1;
    } else if ((c & 0xE0) === 0xC0) {
      cp = c & 0x1F;
      n = 2;
    } else if ((c & 0xF0) === 0xE0) {
      cp = c & 0x0F;
      n = 3;
    } else if ((c & 0xF8) === 0xF0) {
      cp = c & 0x07;
      n = 4;
    } else {
      codes.push(0xFFFD);
      i++;
      continue;
    }
    if (i + n > bytes.length) {
      codes.push(0xFFFD);
      i++;
      continue;
    }
    for (let k: number = 1; k < n; k++) {
      cp = (cp << 6) | (bytes[i + k] & 0x3F);
    }
    i += n;
    if (cp > 0xFFFF) {
      const v: number = cp - 0x10000;
      codes.push(0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF));
    } else {
      codes.push(cp);
    }
  }
  // 分块拼接（避免超长参数导致 fromCharCode 异常）
  let out: string = '';
  const CHUNK: number = 4096;
  for (let s: number = 0; s < codes.length; s += CHUNK) {
    const part: number[] = codes.slice(s, s + CHUNK);
    out += String.fromCharCode(...part);
  }
  return out;
}

/** 拼接两个字节数组 */
function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out: Uint8Array = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

/** 密码派生密钥：SHA-256(盐 + '|' + 密码) → 32 字节 */
function deriveKey(password: string): Uint8Array {
  return sha256(utf8Bytes(KEY_SALT + '|' + password));
}

/** 计数器模式密钥流：ks 块 = SHA-256(key || u32be(counter)) */
function keyStream(key: Uint8Array, len: number): Uint8Array {
  const out: Uint8Array = new Uint8Array(len);
  const block: Uint8Array = new Uint8Array(36);
  block.set(key, 0);
  let counter: number = 0;
  let i: number = 0;
  while (i < len) {
    block[32] = (counter >>> 24) & 0xff;
    block[33] = (counter >>> 16) & 0xff;
    block[34] = (counter >>> 8) & 0xff;
    block[35] = counter & 0xff;
    const digest: Uint8Array = sha256(block);
    const n: number = Math.min(32, len - i);
    out.set(digest.subarray(0, n), i);
    i += n;
    counter++;
  }
  return out;
}

/** XOR 加解密（同构） */
function xorBytes(data: Uint8Array, ks: Uint8Array): Uint8Array {
  const out: Uint8Array = new Uint8Array(data.length);
  for (let i: number = 0; i < data.length; i++) {
    out[i] = (data[i] ^ ks[i]) & 0xff;
  }
  return out;
}

/** 真机算法自检用：字符串 SHA-256 的十六进制（'abc' 期望值 ba7816bf8f01cfea…） */
export function sha256Hex(text: string): string {
  const d: Uint8Array = sha256(utf8Bytes(text));
  let s: string = '';
  for (let i: number = 0; i < d.length; i++) {
    const h: string = d[i].toString(16);
    s += h.length === 1 ? '0' + h : h;
  }
  return s;
}

/** 嗅探：是否为本 App 的 .xnd 加密备份（导入时区分加密备份与旧版明文 txt） */
export function isEncryptedBackup(bytes: Uint8Array): boolean {
  if (bytes.length < HEADER_LEN) {
    return false;
  }
  for (let i: number = 0; i < MAGIC_LEN; i++) {
    if (bytes[i] !== BACKUP_MAGIC_TEXT.charCodeAt(i)) {
      return false;
    }
  }
  return true;
}

/** 加密备份：JSON 文本 → .xnd 容器字节（magic + 长度 + tag + 密文） */
export function encryptBackup(json: string, password: string): Uint8Array {
  const pt: Uint8Array = utf8Bytes(json);
  const key: Uint8Array = deriveKey(password);
  const ct: Uint8Array = xorBytes(pt, keyStream(key, pt.length));
  const tag: Uint8Array = sha256(concat(key, pt)).subarray(0, TAG_LEN);
  const out: Uint8Array = new Uint8Array(HEADER_LEN + ct.length);
  for (let i: number = 0; i < MAGIC_LEN; i++) {
    out[i] = BACKUP_MAGIC_TEXT.charCodeAt(i);
  }
  out[8] = pt.length & 0xff;
  out[9] = (pt.length >>> 8) & 0xff;
  out[10] = (pt.length >>> 16) & 0xff;
  out[11] = (pt.length >>> 24) & 0xff;
  out.set(tag, MAGIC_LEN + LEN_LEN);
  out.set(ct, HEADER_LEN);
  return out;
}

/**
 * 解密备份：.xnd 容器字节 → JSON 文本。
 * 密码错误：tag 校验失败抛异常（调用方提示「密码错误」）；magic 不符同样抛异常。
 */
export function decryptBackup(bytes: Uint8Array, password: string): string {
  if (!isEncryptedBackup(bytes)) {
    throw new Error('not an xnd backup container');
  }
  const ptLen: number = (bytes[8] | (bytes[9] << 8) | (bytes[10] << 16) | ((bytes[11] << 24) >>> 0)) >>> 0;
  if (bytes.length < HEADER_LEN + ptLen) {
    throw new Error('wrong password or corrupted file');
  }
  const tag: Uint8Array = bytes.slice(MAGIC_LEN + LEN_LEN, HEADER_LEN);
  const ct: Uint8Array = bytes.slice(HEADER_LEN, HEADER_LEN + ptLen);
  const key: Uint8Array = deriveKey(password);
  const pt: Uint8Array = xorBytes(ct, keyStream(key, ptLen));
  const calc: Uint8Array = sha256(concat(key, pt)).subarray(0, TAG_LEN);
  let ok: boolean = true;
  for (let i: number = 0; i < TAG_LEN; i++) {
    if (tag[i] !== calc[i]) {
      ok = false;
      break;
    }
  }
  if (!ok) {
    throw new Error('wrong password or corrupted file');
  }
  return utf8Text(pt);
}
