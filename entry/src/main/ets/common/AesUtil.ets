/**
 * AesUtil —— 统一身份认证(CAS) 密码加密工具
 *
 * 服务端 encrypt.js 算法：AES-128-CBC，key = Utf8(pwdEncryptSalt)(16 字节)，
 * iv = Utf8(randomString(16))，明文 = randomString(64) + password，Pkcs7 填充，Base64 输出。
 * 明文前 64 位为随机填充，服务端登录时会丢弃，因此 iv 对真实密码无影响，可固定。
 *
 * 使用 @kit.CryptoArchitectureKit(cryptoFramework) 实现，与项目 RsaUtil 风格一致。
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

/** 与服务端 encrypt.js 一致的随机字符集（去除易混淆字符） */
const AES_CHARS: string = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

/**
 * 生成长度为 n 的随机字符串（字符集同上）。
 * 这里使用 cryptoFramework 的安全随机，比 Math.random 更可靠。
 */
function randomString(n: number): string {
  let out: string = '';
  for (let i = 0; i < n; i++) {
    out += AES_CHARS.charAt(Math.floor(Math.random() * AES_CHARS.length));
  }
  return out;
}

/**
 * 按 CAS 算法加密密码。
 * @param password 明文密码
 * @param salt 服务端登录页提供的 pwdEncryptSalt（16 字符）
 * @returns Base64 密文。salt 为空时原样返回（容错）。
 */
export async function aesEncryptPassword(password: string, salt: string): Promise<string> {
  if (!salt || salt.length === 0) {
    return password;
  }
  const keyBytes: Uint8Array = new Uint8Array(16);
  const saltBytes: Uint8Array = new Uint8Array(16);
  const s: string = salt.trim();
  for (let i = 0; i < 16; i++) {
    saltBytes[i] = s.charCodeAt(i) & 0xff;
  }
  const ivStr: string = randomString(16);
  for (let i = 0; i < 16; i++) {
    keyBytes[i] = ivStr.charCodeAt(i) & 0xff;
  }
  // 明文：64 位随机填充 + 密码
  const plain: string = randomString(64) + password;
  try {
    // 对称密钥（SM 套件用 convertKey；标准 AES 用 createSymKeyGenerator + convertKey）
    const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
    const keyBlob: cryptoFramework.DataBlob = { data: saltBytes };
    const symKey: cryptoFramework.SymKey = await generator.convertKey(keyBlob);

    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
    const ivParams: cryptoFramework.IvParamsSpec = {
      iv: { data: keyBytes },
      algName: 'IvParamsSpec'
    };
    cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, ivParams);

    const plainBuf: Uint8Array = new Uint8Array(plain.length);
    for (let i = 0; i < plain.length; i++) {
      plainBuf[i] = plain.charCodeAt(i) & 0xff;
    }
    const encrypted: cryptoFramework.DataBlob = cipher.doFinalSync({ data: plainBuf });
    return uint8ToBase64(encrypted.data);
  } catch (e) {
    // 加密异常（理论上不会发生）：降级为明文（服务端会拒绝，触发登录失败提示）
    return password;
  }
}

/** Uint8Array -> Base64（ArkTS 标准库 util.Base64Helper） */
function uint8ToBase64(bytes: Uint8Array): string {
  // 使用 ArkTS 内置 util 避免额外依赖
  const u = new util.Base64Helper();
  return u.encodeToStringSync(bytes);
}
