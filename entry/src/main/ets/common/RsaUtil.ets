/**
 * RSA 工具：正方教务系统登录密码加密
 *
 * 正方 zftal-ui v5 登录时，密码采用 RSA（PKCS#1 v1.5）加密后再传给服务端：
 *  - 公钥由 /xtgl/login_getPublicKey.html 下发，返回 { modulus, exponent }（均为 base64）；
 *  - 用该公钥对明文密码加密，结果 base64 后放入登录表单的 mm 字段。
 *
 * 这里直接用 HarmonyOS CryptoKit（@kit.CryptoArchitectureKit）完成，无需第三方 JS 库。
 * CryptoKit 的 convertKey 接收 DER 编码的 X.509 公钥（SubjectPublicKeyInfo），
 * 因此本文件把 modulus + exponent 组装成标准的 SPKI DER 再导入。
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

export class RsaUtil {
  /**
   * 用正方下发的 RSA 公钥加密密码。
   * @param password    明文密码
   * @param modulusB64  base64 编码的 modulus（N）
   * @param exponentB64 base64 编码的 exponent（e，通常为 65537 -> "AQAB"）
   * @returns base64 编码的密文，可直接放入登录表单的 mm 字段
   */
  static async encryptPassword(password: string, modulusB64: string, exponentB64: string): Promise<string> {
    const base64: util.Base64Helper = new util.Base64Helper();
    let modulus: Uint8Array = RsaUtil.stripLeadingZero(await base64.decode(modulusB64));
    let exponent: Uint8Array = RsaUtil.stripLeadingZero(await base64.decode(exponentB64));

    const bits: number = modulus.length * 8;
    let sizeTag: string = 'RSA1024';
    if (bits > 2048) {
      sizeTag = 'RSA3072';
    } else if (bits > 1024) {
      sizeTag = 'RSA2048';
    }

    const spki: Uint8Array = RsaUtil.buildSpki(modulus, exponent);
    const keyBlob: cryptoFramework.DataBlob = { data: spki };
    const generator: cryptoFramework.AsyKeyGenerator = cryptoFramework.createAsyKeyGenerator(sizeTag);
    const keyPair: cryptoFramework.KeyPair = await generator.convertKey(keyBlob, null);

    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('RSA|PKCS1');
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, keyPair.pubKey, null);
    const encoder: util.TextEncoder = new util.TextEncoder();
    const pwdBytes: Uint8Array = encoder.encode(password);
    const encrypted: cryptoFramework.DataBlob = await cipher.doFinal({ data: pwdBytes });
    return base64.encodeToString(encrypted.data);
  }

  /** 去掉大数前面多余的 0x00 符号字节（DER 正数补齐），保留至少一个字节 */
  private static stripLeadingZero(data: Uint8Array): Uint8Array {
    let start: number = 0;
    while (start < data.length - 1 && data[start] === 0) {
      start++;
    }
    if (start === 0) {
      return data;
    }
    const out: Uint8Array = new Uint8Array(data.length - start);
    for (let i = 0; i < out.length; i++) {
      out[i] = data[start + i];
    }
    return out;
  }

  /** 把 modulus + exponent 组装为 X.509 SubjectPublicKeyInfo 的 DER 字节 */
  private static buildSpki(modulus: Uint8Array, exponent: Uint8Array): Uint8Array {
    // AlgorithmIdentifier: RSA (1.2.840.113549.1.1.1) + NULL
    const algId: Uint8Array = new Uint8Array(
      [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]);
    const rsaPub: Uint8Array = RsaUtil.tlv(0x30, RsaUtil.concat(RsaUtil.derInteger(modulus), RsaUtil.derInteger(exponent)));
    const bitString: Uint8Array = RsaUtil.tlv(0x03, RsaUtil.prependZero(rsaPub));
    return RsaUtil.tlv(0x30, RsaUtil.concat(algId, bitString));
  }

  /** DER INTEGER：去掉前导 0 后，若最高位为 1 则补一个 0x00 符号字节 */
  private static derInteger(src: Uint8Array): Uint8Array {
    let start: number = 0;
    while (start < src.length - 1 && src[start] === 0) {
      start++;
    }
    const needSign: boolean = (src[start] & 0x80) !== 0;
    const content: Uint8Array = new Uint8Array(src.length - start + (needSign ? 1 : 0));
    let idx: number = 0;
    if (needSign) {
      content[0] = 0;
      idx = 1;
    }
    for (let i = start; i < src.length; i++) {
      content[idx] = src[i];
      idx++;
    }
    return RsaUtil.tlv(0x02, content);
  }

  /** DER TLV 包装：tag + 长度 + 内容 */
  private static tlv(tag: number, content: Uint8Array): Uint8Array {
    const lenBytes: Uint8Array = RsaUtil.lengthBytes(content.length);
    const out: Uint8Array = new Uint8Array(1 + lenBytes.length + content.length);
    out[0] = tag;
    out.set(lenBytes, 1);
    out.set(content, 1 + lenBytes.length);
    return out;
  }

  /** DER 长度编码（支持多字节） */
  private static lengthBytes(len: number): Uint8Array {
    if (len < 0x80) {
      return new Uint8Array([len]);
    }
    const tmp: number[] = [];
    let n: number = len;
    while (n > 0) {
      tmp.push(n % 256);
      n = Math.floor(n / 256);
    }
    const big: number[] = [];
    for (let i = tmp.length - 1; i >= 0; i--) {
      big.push(tmp[i]);
    }
    const arr: Uint8Array = new Uint8Array(1 + big.length);
    arr[0] = 0x80 | big.length;
    for (let i = 0; i < big.length; i++) {
      arr[1 + i] = big[i];
    }
    return arr;
  }

  private static concat(a: Uint8Array, b: Uint8Array): Uint8Array {
    const out: Uint8Array = new Uint8Array(a.length + b.length);
    out.set(a, 0);
    out.set(b, a.length);
    return out;
  }

  private static prependZero(a: Uint8Array): Uint8Array {
    const out: Uint8Array = new Uint8Array(a.length + 1);
    out[0] = 0; // BIT STRING 未使用位数
    out.set(a, 1);
    return out;
  }
}
