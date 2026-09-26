/**
 * 备份文件加密工具（BackupCrypto）—— 专属加密容器 v1（扩展名 .xjbackup）
 *
 * 容器布局：
 *   [8B magic "XJAUBKV1"][16B IV][AES-256-CBC 密文（PKCS7）]
 * - 明文 = 备份 JSON 文本（UTF-8）
 * - 密钥：SHA256("xjau-helper-backup-v1|" + 用户密码)，32 字节（AES-256）
 * - 该格式为本 App 专属：其他软件无法打开，必须在 App 内输入密码解密导入（用户要求）
 * - 密码错误：CBC 解密出乱码 → PKCS7 填充校验失败抛异常（调用方提示「密码错误或文件损坏」）
 *
 * 同步 API（initSync/doFinalSync/digestSync/generateRandomSync）与 AesUtil 同风格。
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';

const BACKUP_MAGIC_TEXT: string = 'XJAUBKV1';
const KEY_SALT: string = 'xjau-helper-backup-v1';
const MAGIC_LEN: number = 8;
const IV_LEN: number = 16;

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

/** 密码派生密钥：SHA256(盐 + '|' + 密码) → 32 字节 */
function deriveKey(password: string): Uint8Array {
  const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
  md.updateSync({ data: utf8Bytes(KEY_SALT + '|' + password) });
  return md.digestSync().data;
}

/** 嗅探：是否为本 App 的加密备份容器（导入时区分加密备份与旧版明文 txt） */
export function isEncryptedBackup(bytes: Uint8Array): boolean {
  if (bytes.length < MAGIC_LEN + IV_LEN + 16) {
    return false;
  }
  for (let i: number = 0; i < MAGIC_LEN; i++) {
    if (bytes[i] !== BACKUP_MAGIC_TEXT.charCodeAt(i)) {
      return false;
    }
  }
  return true;
}

/** 加密备份：JSON 文本 → 容器字节（magic + IV + 密文），直接写入 .xjbackup 文件 */
export function encryptBackup(json: string, password: string): Uint8Array {
  const key: Uint8Array = deriveKey(password);
  const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
  const symKey: cryptoFramework.SymKey = generator.convertKeySync({ data: key });
  const iv: Uint8Array = cryptoFramework.createRandom().generateRandomSync(IV_LEN).data;
  const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
  const ivParams: cryptoFramework.IvParamsSpec = {
    iv: { data: iv },
    algName: 'IvParamsSpec'
  };
  cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, ivParams);
  const enc: Uint8Array = cipher.doFinalSync({ data: utf8Bytes(json) }).data;
  const out: Uint8Array = new Uint8Array(MAGIC_LEN + IV_LEN + enc.length);
  for (let i: number = 0; i < MAGIC_LEN; i++) {
    out[i] = BACKUP_MAGIC_TEXT.charCodeAt(i);
  }
  out.set(iv, MAGIC_LEN);
  out.set(enc, MAGIC_LEN + IV_LEN);
  return out;
}

/**
 * 解密备份：容器字节 → JSON 文本。
 * 密码错误：PKCS7 校验失败抛异常；magic 不符同样抛异常。
 */
export function decryptBackup(bytes: Uint8Array, password: string): string {
  if (!isEncryptedBackup(bytes)) {
    throw new Error('not an encrypted backup container');
  }
  const key: Uint8Array = deriveKey(password);
  const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
  const symKey: cryptoFramework.SymKey = generator.convertKeySync({ data: key });
  const iv: Uint8Array = bytes.slice(MAGIC_LEN, MAGIC_LEN + IV_LEN);
  const ct: Uint8Array = bytes.slice(MAGIC_LEN + IV_LEN);
  const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
  const ivParams: cryptoFramework.IvParamsSpec = {
    iv: { data: iv },
    algName: 'IvParamsSpec'
  };
  cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, ivParams);
  return utf8Text(cipher.doFinalSync({ data: ct }).data);
}
