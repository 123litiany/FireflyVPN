/**
 * HTTP 客户端（OkHttp/Retrofit → @ohos.net.http）
 */
import http from '@ohos.net.http';
import { AppConfig } from '../common/AppConfig';
import { RuntimeLog } from '../util/Utils';

const TAG: string = 'HttpClient';

export class HttpResult {
  code: number = 0;
  body: string = '';
  headers: string = '';
}

export class HttpClient {
  static async get(url: string, userAgent?: string, timeoutMs?: number): Promise<HttpResult> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const header: Record<string, string> = {
        'User-Agent': userAgent !== undefined && userAgent.length > 0 ? userAgent : AppConfig.USER_AGENT,
        'Accept': '*/*'
      };
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: timeoutMs !== undefined ? timeoutMs : AppConfig.NODE_REQUEST_TIMEOUT_MS,
        readTimeout: timeoutMs !== undefined ? timeoutMs : AppConfig.NODE_REQUEST_TIMEOUT_MS,
        usingCache: false
      };
      const response: http.HttpResponse = await request.request(url, options);
      const result: HttpResult = new HttpResult();
      result.code = response.responseCode;
      result.body = typeof response.result === 'string' ? response.result : '';
      result.headers = JSON.stringify(response.header);
      return result;
    } finally {
      request.destroy();
    }
  }

  /** 下载字节内容并计时，用于测速 */
  static async downloadBytes(url: string, timeoutMs: number): Promise<Uint8Array> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': AppConfig.USER_AGENT, 'Accept': '*/*' },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: timeoutMs,
        usingCache: false
      };
      const response: http.HttpResponse = await request.request(url, options);
      if (response.responseCode !== 200 || !(response.result instanceof ArrayBuffer)) {
        throw new Error(`测速请求失败: HTTP ${response.responseCode}`);
      }
      return new Uint8Array(response.result as ArrayBuffer);
    } finally {
      request.destroy();
    }
  }

  static async fetchText(url: string, userAgent: string, timeoutMs: number): Promise<string> {
    RuntimeLog.debug(TAG, `GET ${url}`);
    const result: HttpResult = await HttpClient.get(url, userAgent, timeoutMs);
    if (result.code < 200 || result.code >= 300) {
      throw new Error(`HTTP ${result.code}`);
    }
    return result.body;
  }
}
