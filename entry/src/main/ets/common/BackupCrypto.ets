/**
 * 备份文件加密工具（BackupCrypto）—— 标准加密 zip（STORED + PKWARE ZipCrypto）
 *
 * 产出为**标准 zip 压缩包**：任何解压软件（7-Zip / WinRAR / Windows 资源管理器）
 * 打开时输入设置密码即可解出 backup.json——与常规加密压缩包体验一致。
 *
 * 技术说明：@ohos.zlib 的 Options 不支持 zip 密码（官方与社区均已确认），
 * 故按 PKWARE APPNOTE 手写 zip 结构：
 *   - 单文件条目 backup.json，压缩方法 STORED（不二次压缩，备份 JSON 本身不大）
 *   - general purpose bit 0 = 1（加密标志），传统 ZipCrypto 加密（12 字节加密头 + 数据流）
 *   - CRC32 使用 IEEE 标准表（0xEDB88320），同时用于 ZipCrypto 密钥更新与数据校验
 * 安全提示：ZipCrypto 是 zip 传统加密（强度有限，防普通打开足够）；备份不含账号与登录 Cookie。
 *
 * 密码错误表现：解密出的 12 字节头末字节与 CRC 高字节不匹配（1/256 漏检）+ 数据 CRC32 校验
 * 必然失败 → 抛异常，调用方提示「密码错误或文件损坏」。
 */
import { util, buffer } from '@kit.ArkTS';

const ENTRY_NAME: string = 'backup.json';
const PWD_VERIFY_SALT: string = 'xjau-helper-backup-v1';
const ZIP_CRYPTO_HEADER_LEN: number = 12;

/** IEEE CRC32 反射表（0xEDB88320），懒加载一次 */
let crcTable: Uint32Array | null = null;

function crcTableGet(): Uint32Array {
  if (crcTable !== null) {
    return crcTable;
  }
  const table: Uint32Array = new Uint32Array(256);
  for (let n: number = 0; n < 256; n++) {
    let c: number = n;
    for (let k: number = 0; k < 8; k++) {
      if ((c & 1) !== 0) {
        c = 0xEDB88320 ^ (c >>> 1);
      } else {
        c = c >>> 1;
      }
    }
    table[n] = c >>> 0;
  }
  crcTable = table;
  return table;
}

/** 单字节 CRC32 增量更新（无符号） */
function crc32Update(crc: number, byte: number): number {
  return (crcTableGet()[(crc ^ byte) & 0xff] ^ (crc >>> 8)) >>> 0;
}

/** 整段数据 CRC32 */
function crc32All(data: Uint8Array): number {
  let crc: number = 0xFFFFFFFF;
  for (let i: number = 0; i < data.length; i++) {
    crc = crc32Update(crc, data[i]);
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

/** 字符串 → UTF-8 字节（Buffer.from 默认 utf-8；JSON 含中文课程名等多字节字符） */
function utf8Bytes(s: string): Uint8Array {
  const b: buffer.Buffer = buffer.from(s);
  // Buffer 类型声明无 byteLength 属性（编译器 10505001），用 length 等价
  return new Uint8Array(b.buffer, b.byteOffset, b.length);
}

/** UTF-8 字节 → 字符串 */
function utf8Text(bytes: Uint8Array): string {
  const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  return decoder.decodeToString(bytes);
}

/** ZipCrypto 密钥组（PKWARE APPNOTE 初始值） */
class ZipKeys {
  k0: number;
  k1: number;
  k2: number;
  private table: Uint32Array;

  constructor(password: string, table: Uint32Array) {
    this.k0 = 0x12345678;
    this.k1 = 0x23456789;
    this.k2 = 0x34567890;
    this.table = table;
    const pwd: Uint8Array = utf8Bytes(password);
    for (let i: number = 0; i < pwd.length; i++) {
      this.update(pwd[i]);
    }
  }

  /** 单字节更新密钥组 */
  update(byte: number): void {
    this.k0 = (this.table[(this.k0 ^ byte) & 0xff] ^ (this.k0 >>> 8)) >>> 0;
    this.k1 = ((this.k1 + (this.k0 & 0xff)) >>> 0);
    // 乘法必须 imul（k1×134775813 超出 Number 精确整数范围）
    this.k1 = (Math.imul(this.k1, 134775813) + 1) >>> 0;
    this.k2 = (this.table[(this.k2 ^ ((this.k1 >>> 24) & 0xff)) & 0xff] ^ (this.k2 >>> 8)) >>> 0;
  }

  /** keystream 当前字节 */
  streamByte(): number {
    const temp: number = (this.k2 | 2) >>> 0;
    return ((Math.imul(temp, temp ^ 1)) >>> 8) & 0xff;
  }
}

/** 伪随机字节（加密头前 11 字节用；DPS 随机即可，非安全边界） */
function randByte(): number {
  return Math.floor(Math.random() * 256) & 0xff;
}

/** 小端写入辅助 */
class ByteWriter {
  private buf: number[] = [];

  u8(v: number): void {
    this.buf.push(v & 0xff);
  }

  u16(v: number): void {
    this.buf.push(v & 0xff, (v >>> 8) & 0xff);
  }

  u32(v: number): void {
    this.buf.push(v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff);
  }

  bytes(d: Uint8Array): void {
    for (let i: number = 0; i < d.length; i++) {
      this.buf.push(d[i]);
    }
  }

  text(s: string): void {
    this.bytes(utf8Bytes(s));
  }

  toBytes(): Uint8Array {
    return new Uint8Array(this.buf);
  }
}

/** 小端读取辅助（只读 backup.json 单条目所需字段） */
class ByteReader {
  private d: Uint8Array;
  private pos: number = 0;

  constructor(data: Uint8Array) {
    this.d = data;
  }

  u8(): number {
    return this.d[this.pos++] & 0xff;
  }

  u16(): number {
    const v: number = (this.d[this.pos] & 0xff) | ((this.d[this.pos + 1] & 0xff) << 8);
    this.pos += 2;
    return v;
  }

  u32(): number {
    const v: number = ((this.d[this.pos] & 0xff)
      | ((this.d[this.pos + 1] & 0xff) << 8)
      | ((this.d[this.pos + 2] & 0xff) << 16)
      | ((this.d[this.pos + 3] & 0xff) << 24)) >>> 0;
    this.pos += 4;
    return v;
  }

  bytes(n: number): Uint8Array {
    const out: Uint8Array = this.d.slice(this.pos, this.pos + n);
    this.pos += n;
    return out;
  }
}

/**
 * 嗅探：是否为加密 zip 备份（PK 头 + general purpose bit0 = 1）。
 * 导入分流：加密 zip 走密码；旧版明文 txt 走文本解析。
 */
export function isEncryptedBackup(bytes: Uint8Array): boolean {
  if (bytes.length < 4) {
    return false;
  }
  const isZip: boolean = bytes[0] === 0x50 && bytes[1] === 0x4B && bytes[2] === 0x03 && bytes[3] === 0x04;
  if (!isZip || bytes.length < 8) {
    return false;
  }
  // local file header 偏移 6 的 general purpose bit flag 低位置 1 = 加密
  return (bytes[6] & 0x01) === 0x01;
}

/**
 * 加密备份：JSON 文本 → 标准加密 zip 字节（STORED + ZipCrypto，单条目 backup.json）。
 * 输出直接写入 .zip 文件，解压软件输密码即可打开。
 */
export function encryptBackup(json: string, password: string): Uint8Array {
  const plain: Uint8Array = utf8Bytes(json);
  const crc: number = crc32All(plain);

  // DOS 时间（时间字段同时作为 ZipCrypto 头校验字节来源之一，此处用 CRC 高字节校验，时间随意）
  const d: Date = new Date();
  const dosTime: number = ((d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1)) & 0xffff;
  const dosDate: number = (((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate()) & 0xffff;

  const keys: ZipKeys = new ZipKeys(password, crcTableGet());
  const w: ByteWriter = new ByteWriter();

  // ── local file header ──
  w.u32(0x04034B50);
  w.u16(20);            // version needed
  w.u16(0x0001);        // general purpose flag: bit0 = 加密
  w.u16(0);             // method: STORED
  w.u16(dosTime);
  w.u16(dosDate);
  w.u32(crc);
  const encLen: number = ZIP_CRYPTO_HEADER_LEN + plain.length;
  w.u32(encLen);        // compressed size
  w.u32(plain.length);  // uncompressed size
  w.u16(ENTRY_NAME.length);
  w.u16(0);             // extra len
  w.text(ENTRY_NAME);

  // ── 加密数据：12 字节加密头（11 随机 + CRC 高字节校验）+ 数据，同一 keystream 连续加密 ──
  const header: Uint8Array = new Uint8Array(ZIP_CRYPTO_HEADER_LEN);
  for (let i: number = 0; i < ZIP_CRYPTO_HEADER_LEN - 1; i++) {
    header[i] = randByte();
  }
  header[ZIP_CRYPTO_HEADER_LEN - 1] = (crc >>> 24) & 0xff;
  for (let i: number = 0; i < ZIP_CRYPTO_HEADER_LEN; i++) {
    const p: number = header[i];
    const c: number = (p ^ keys.streamByte()) & 0xff;
    keys.update(p);
    w.u8(c);
  }
  for (let i: number = 0; i < plain.length; i++) {
    const p: number = plain[i];
    const c: number = (p ^ keys.streamByte()) & 0xff;
    keys.update(p);
    w.u8(c);
  }

  const localSize: number = w.toBytes().length;

  // ── central directory ──
  w.u32(0x02014B50);
  w.u16(20);            // version made by
  w.u16(20);            // version needed
  w.u16(0x0001);        // flag: 加密
  w.u16(0);             // method STORED
  w.u16(dosTime);
  w.u16(dosDate);
  w.u32(crc);
  w.u32(encLen);
  w.u32(plain.length);
  w.u16(ENTRY_NAME.length);
  w.u16(0);             // extra len
  w.u16(0);             // comment len
  w.u16(0);             // disk number start
  w.u16(0);             // internal attrs
  w.u32(0);             // external attrs
  w.u32(0);             // local header offset
  w.text(ENTRY_NAME);

  // ── EOCD ──
  const cdSize: number = w.toBytes().length - localSize;
  w.u32(0x06054B50);
  w.u16(0);             // disk
  w.u16(0);             // cd start disk
  w.u16(1);             // entries this disk
  w.u16(1);             // total entries
  w.u32(cdSize);
  w.u32(localSize);     // cd offset
  w.u16(0);             // comment len

  return w.toBytes();
}

/**
 * 解密备份：标准加密 zip 字节 → JSON 文本。
 * 密码错误：加密头校验字节不匹配（1/256 漏检）+ 数据 CRC32 必然失败 → 抛异常。
 */
export function decryptBackup(zipBytes: Uint8Array, password: string): string {
  const r: ByteReader = new ByteReader(zipBytes);
  if (r.u32() !== 0x04034B50) {
    throw new Error('not a zip backup');
  }
  r.u16();              // version needed
  const flags: number = r.u16();
  const method: number = r.u16();
  if ((flags & 0x01) !== 0x01 || method !== 0) {
    throw new Error('unsupported zip entry (not encrypted STORED)');
  }
  r.u16();              // time
  r.u16();              // date
  const crc: number = r.u32();
  const csize: number = r.u32();
  const usize: number = r.u32();
  const nameLen: number = r.u16();
  r.u16();              // extra len
  const name: string = utf8Text(r.bytes(nameLen));
  if (name !== ENTRY_NAME || csize !== ZIP_CRYPTO_HEADER_LEN + usize || zipBytes.length < 30 + nameLen + csize) {
    throw new Error('unexpected zip entry');
  }

  const enc: Uint8Array = r.bytes(csize);
  const keys: ZipKeys = new ZipKeys(password, crcTableGet());
  const plain: Uint8Array = new Uint8Array(usize);
  let verified: boolean = true;
  for (let i: number = 0; i < csize; i++) {
    const p: number = (enc[i] ^ keys.streamByte()) & 0xff;
    keys.update(p);
    if (i < ZIP_CRYPTO_HEADER_LEN) {
      // 加密头：末字节应为 CRC 高字节（快速密码校验，1/256 漏检由 CRC 全量校验兜底）
      if (i === ZIP_CRYPTO_HEADER_LEN - 1 && p !== ((crc >>> 24) & 0xff)) {
        verified = false;
      }
    } else {
      plain[i - ZIP_CRYPTO_HEADER_LEN] = p;
    }
  }
  if (!verified || crc32All(plain) !== crc) {
    throw new Error('wrong password or corrupted file');
  }
  return utf8Text(plain);
}
