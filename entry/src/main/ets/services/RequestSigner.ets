/**
 * RSA-SHA256 请求签名工具
 * 使用 PKCS#8 PEM 私钥对请求内容进行签名
 * 适配 ArkTS 严格模式
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer, util } from '@kit.ArkTS';

export class RequestSigner {
  /**
   * 使用 RSA-SHA256 对内容签名
   * @param content  待签名字符串，如 "appKey=xxx&body=xxx&nonce=xxx&timestamp=xxx"
   * @param privateKeyPem  PKCS#8 PEM 格式私钥
   * @returns Base64 编码的签名
   */
  static async signRsaSha256(content: string, privateKeyPem: string): Promise<string> {
    try {
      // 1. 解析 PEM → DER (去掉头尾 + base64 decode)
      const pemBody = privateKeyPem
        .replace(/-----BEGIN PRIVATE KEY-----/, '')
        .replace(/-----END PRIVATE KEY-----/, '')
        .replace(/[\r\n\s]/g, '');

      const base64Helper = new util.Base64Helper();
      const derBytes = base64Helper.decodeSync(pemBody);

      // 2. 构造 DataBlob
      const keyBlob: cryptoFramework.DataBlob = { data: derBytes };

      // 3. 创建 RSA 密钥生成器并恢复私钥
      const rsaGenerator = cryptoFramework.createAsyKeyGenerator('RSA');
      const keyPair = await rsaGenerator.convertKey(null, keyBlob);
      const priKey = keyPair.priKey;

      // 4. 创建签名实例 (SHA256withRSA, PKCS1 填充)
      const signer = cryptoFramework.createSign('RSA|PKCS1|SHA256');
      await signer.init(priKey);

      // 5. 将待签名内容转为 DataBlob
      const contentBlob: cryptoFramework.DataBlob = {
        data: new Uint8Array(buffer.from(content, 'utf-8').buffer)
      };

      // 6. 签名
      const signResult = await signer.sign(contentBlob);

      // 7. 将签名结果转为 Base64
      return base64Helper.encodeToStringSync(signResult.data);
    } catch (error) {
      console.error('[RequestSigner] RSA-SHA256 sign failed:', JSON.stringify(error));
      throw new Error(`[RequestSigner] Sign failed: ${JSON.stringify(error)}`);
    }
  }
}
