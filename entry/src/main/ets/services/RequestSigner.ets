/**
 * RSA-SHA256 请求签名工具
 * 使用 PKCS#8 PEM 私钥对请求内容进行签名
 * 适配 ArkTS 严格模式
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';

export class RequestSigner {
  /**
   * 使用 RSA-SHA256 对内容签名
   * @param content  待签名字符串，如 "appKey=xxx&body=xxx&nonce=xxx&timestamp=xxx"
   * @param privateKeyPem  PKCS#8 PEM 格式私钥
   * @returns Base64 编码的签名
   */
  static async signRsaSha256(content: string, privateKeyPem: string): Promise<string> {
    try {
      // 1. 创建 RSA 密钥生成器并从 PEM 恢复私钥
      //    真机实测: `RSA` + convertKey(der) 在部分设备会报 401 参数错误
      //    使用 `RSA2048|PRIMES_2` + convertPemKey 兼容性更稳定
      const rsaGenerator = cryptoFramework.createAsyKeyGenerator('RSA2048|PRIMES_2');
      const normalizedPem = privateKeyPem.replace(/\r\n/g, '\n').trim();
      const keyPair = await rsaGenerator.convertPemKey(null, normalizedPem);
      const priKey = keyPair.priKey;

      // 2. 创建签名实例 (SHA256withRSA, PKCS1 填充)
      const signer = cryptoFramework.createSign('RSA|PKCS1|SHA256');
      await signer.init(priKey);

      // 3. 将待签名内容转为 DataBlob
      // 注意：不能使用 `.buffer` 直接包裹，避免带入底层池化缓冲区的无关字节
      const contentBytes = buffer.from(content, 'utf-8');
      const contentData = new Uint8Array(Array.from(contentBytes.values()));
      const contentBlob: cryptoFramework.DataBlob = {
        data: contentData
      };

      // 4. 签名
      const signResult = await signer.sign(contentBlob);

      // 5. 将签名结果转为 Base64
      return buffer.from(signResult.data).toString('base64');
    } catch (error) {
      console.error('[RequestSigner] RSA-SHA256 sign failed:', JSON.stringify(error));
      throw new Error(`[RequestSigner] Sign failed: ${JSON.stringify(error)}`);
    }
  }
}
