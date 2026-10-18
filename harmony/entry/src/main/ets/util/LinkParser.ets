/**
 * 订阅链接解析
 *
 * 移植自 Android: network/SubscriptionParser.kt
 * 支持 vless / vmess / trojan / hysteria2(hy2) / anytls / tuic / naive /
 * wireguard / ss / socks(4/5) / http(s)，并兼容整段 Base64 订阅。
 */
import { Node, NodeType } from '../model/Models';
import { decodeBase64Compat, hashId, safeDecodeURIComponent } from './Utils';
import { RuntimeLog } from './Utils';

const SUPPORTED_SCHEMES: string[] = [
  'vless', 'vmess', 'trojan', 'hysteria2', 'hy2', 'anytls', 'tuic',
  'naive', 'naive+https', 'wireguard', 'ss', 'socks', 'socks5',
  'socks4', 'socks4a', 'http', 'https'
];

const LOG_TAG: string = 'LinkParser';

/** 手工 URI 解析结果（避免平台 URL 实现对自定义 scheme 的差异） */
export class UriParts {
  scheme: string = '';
  username: string = '';
  password: string = '';
  host: string = '';
  port: number = -1;
  path: string = '';
  query: string = '';
  fragment: string = '';
  hasUserInfo: boolean = false;
}

export function parseUri(link: string): UriParts | null {
  const parts: UriParts = new UriParts();
  const schemeEnd: number = link.indexOf('://');
  if (schemeEnd <= 0) {
    return null;
  }
  parts.scheme = link.substring(0, schemeEnd).toLowerCase();
  let rest: string = link.substring(schemeEnd + 3);

  const hashIndex: number = rest.indexOf('#');
  if (hashIndex >= 0) {
    parts.fragment = safeDecodeURIComponent(rest.substring(hashIndex + 1));
    rest = rest.substring(0, hashIndex);
  }
  const queryIndex: number = rest.indexOf('?');
  if (queryIndex >= 0) {
    parts.query = rest.substring(queryIndex + 1);
    rest = rest.substring(0, queryIndex);
  }

  // authority 截止到第一个 '/'（path 之前）
  let authority: string = rest;
  const slashIndex: number = rest.indexOf('/');
  if (slashIndex >= 0) {
    authority = rest.substring(0, slashIndex);
    parts.path = rest.substring(slashIndex);
  }

  const atIndex: number = authority.lastIndexOf('@');
  if (atIndex >= 0) {
    const userInfo: string = authority.substring(0, atIndex);
    authority = authority.substring(atIndex + 1);
    parts.hasUserInfo = true;
    const colon: number = userInfo.indexOf(':');
    if (colon >= 0) {
      parts.username = safeDecodeURIComponent(userInfo.substring(0, colon));
      parts.password = safeDecodeURIComponent(userInfo.substring(colon + 1));
    } else {
      parts.username = safeDecodeURIComponent(userInfo);
    }
  }

  if (authority.startsWith('[')) {
    const close: number = authority.indexOf(']');
    if (close > 0) {
      parts.host = authority.substring(1, close);
      const portPart: string = authority.substring(close + 1);
      if (portPart.startsWith(':')) {
        parts.port = toPort(portPart.substring(1));
      }
    } else {
      parts.host = authority;
    }
  } else {
    const colon: number = authority.lastIndexOf(':');
    if (colon > 0) {
      parts.host = authority.substring(0, colon);
      parts.port = toPort(authority.substring(colon + 1));
    } else {
      parts.host = authority;
    }
  }
  return parts;
}

function toPort(value: string): number {
  const parsed: number = parseInt(value, 10);
  return isNaN(parsed) ? -1 : parsed;
}

/** 读取查询参数（首个匹配值，自动 URL 解码） */
export function queryParam(uri: UriParts, names: string[]): string {
  if (uri.query.length === 0) {
    return '';
  }
  const pairs: string[] = uri.query.split('&');
  for (const name of names) {
    for (const pair of pairs) {
      const eq: number = pair.indexOf('=');
      const key: string = safeDecodeURIComponent(eq >= 0 ? pair.substring(0, eq) : pair);
      if (key === name) {
        return eq >= 0 ? safeDecodeURIComponent(pair.substring(eq + 1)) : '';
      }
    }
  }
  return '';
}

export function queryParamEnabled(uri: UriParts, names: string[]): boolean {
  const value: string = queryParam(uri, names);
  return value === '1' || value.toLowerCase() === 'true';
}

interface VmessJson {
  v?: string;
  ps?: string;
  add?: string;
  port?: string;
  id?: string;
  aid?: string;
  scy?: string;
  net?: string;
  type?: string;
  host?: string;
  path?: string;
  tls?: string;
  sni?: string;
  alpn?: string;
  fp?: string;
}

export class LinkParser {
  /** 是否包含受支持的节点链接 */
  static containsSupportedNodeLink(value: string): boolean {
    const lower: string = value.toLowerCase();
    for (const scheme of SUPPORTED_SCHEMES) {
      if (lower.indexOf(`${scheme}://`) >= 0) {
        return true;
      }
    }
    return false;
  }

  /** 解析整段订阅文本（自动处理 Base64 包装） */
  static parseSubscription(content: string): Node[] {
    const normalized: string = content.trim();
    let finalContent: string = normalized;
    if (!LinkParser.containsSupportedNodeLink(normalized)) {
      try {
        const decoded: string = decodeBase64Compat(normalized);
        if (LinkParser.containsSupportedNodeLink(decoded)) {
          finalContent = decoded;
        }
      } catch (e) {
        RuntimeLog.warn(LOG_TAG, '订阅内容不是有效 Base64，按原始文本解析');
      }
    }
    const lines: string[] = finalContent.split(/\r?\n/);
    const nodes: Node[] = [];
    for (const rawLine of lines) {
      const line: string = rawLine.trim();
      if (line.length === 0) {
        continue;
      }
      const node: Node | null = LinkParser.parseNodeLink(line);
      if (node !== null) {
        nodes.push(node);
      }
    }
    RuntimeLog.info(LOG_TAG, `订阅解析完成，共 ${nodes.length} 个节点`);
    return nodes;
  }

  /** 解析单条节点链接 */
  static parseNodeLink(link: string): Node | null {
    try {
      const lower: string = link.toLowerCase();
      if (lower.startsWith('vless://')) {
        return LinkParser.buildSimple(link, NodeType.VLESS, 80, 'VLESS Node');
      }
      if (lower.startsWith('vmess://')) {
        return LinkParser.parseVmess(link);
      }
      if (lower.startsWith('trojan://')) {
        return LinkParser.buildSimple(link, NodeType.TROJAN, 443, 'Trojan Node');
      }
      if (lower.startsWith('hysteria2://') || lower.startsWith('hy2://')) {
        return LinkParser.parseHysteria2(link);
      }
      if (lower.startsWith('anytls://')) {
        return LinkParser.buildSimple(link, NodeType.ANYTLS, 443, 'AnyTLS Node');
      }
      if (lower.startsWith('tuic://')) {
        return LinkParser.buildSimple(link, NodeType.TUIC, 443, 'TUIC Node');
      }
      if (lower.startsWith('naive://') || lower.startsWith('naive+https://')) {
        return LinkParser.buildSimple(link, NodeType.NAIVE, 443, 'Naive Node');
      }
      if (lower.startsWith('wireguard://')) {
        return LinkParser.buildSimple(link, NodeType.WIREGUARD, 51820, 'WireGuard Node');
      }
      if (lower.startsWith('ss://')) {
        return LinkParser.parseShadowsocks(link);
      }
      if (lower.startsWith('socks://') || lower.startsWith('socks5://') ||
        lower.startsWith('socks4://') || lower.startsWith('socks4a://')) {
        return LinkParser.buildSimple(link, NodeType.SOCKS, 1080, 'Socks Node');
      }
      if (lower.startsWith('http://') || lower.startsWith('https://')) {
        return LinkParser.buildSimple(link, NodeType.HTTP, lower.startsWith('https://') ? 443 : 80, 'HTTP Proxy');
      }
      return null;
    } catch (e) {
      RuntimeLog.error(LOG_TAG, `节点链接解析失败: ${JSON.stringify(e)}`);
      return null;
    }
  }

  private static buildSimple(link: string, type: NodeType, defaultPort: number, defaultName: string): Node | null {
    const uri: UriParts | null = parseUri(link);
    if (uri === null || uri.host.length === 0) {
      return null;
    }
    const node: Node = new Node();
    node.id = hashId(link);
    node.name = uri.fragment.length > 0 ? uri.fragment : defaultName;
    node.type = type;
    node.server = uri.host;
    node.port = uri.port === -1 ? defaultPort : uri.port;
    node.rawLink = link;
    return node;
  }

  private static parseVmess(link: string): Node | null {
    const base64Content: string = link.substring('vmess://'.length);
    const jsonStr: string = decodeBase64Compat(base64Content);
    const config: VmessJson = JSON.parse(jsonStr) as VmessJson;
    const node: Node = new Node();
    node.id = hashId(link);
    node.name = config.ps !== undefined && config.ps.length > 0 ? config.ps : 'VMess Node';
    node.type = NodeType.VMESS;
    node.server = config.add !== undefined ? config.add : '';
    const portValue: number = config.port !== undefined ? parseInt(config.port, 10) : 443;
    node.port = isNaN(portValue) ? 443 : portValue;
    node.rawLink = link;
    if (node.server.length === 0) {
      return null;
    }
    return node;
  }

  private static parseHysteria2(link: string): Node | null {
    const normalized: string = link.replace(/^hy2:\/\//i, 'hysteria2://');
    const uri: UriParts | null = parseUri(normalized);
    if (uri === null) {
      return null;
    }
    const node: Node = new Node();
    node.id = hashId(link);
    node.name = uri.fragment.length > 0 ? uri.fragment : 'Hysteria2 Node';
    node.type = NodeType.HYSTERIA2;
    node.server = uri.host;
    node.port = uri.port === -1 ? 443 : uri.port;
    node.rawLink = link;
    return node.server.length > 0 ? node : null;
  }

  private static parseShadowsocks(link: string): Node | null {
    const uri: UriParts | null = parseUri(link);
    if (uri === null) {
      return null;
    }
    let server: string = uri.host;
    let port: number = uri.port;
    if (server.length === 0) {
      // 形如 ss://base64(method:password@host:port)#name
      const body: string = link.substring('ss://'.length);
      const fragmentIndex: number = body.indexOf('#');
      const base64Part: string = fragmentIndex >= 0 ? body.substring(0, fragmentIndex) : body;
      const decoded: string = decodeBase64Compat(base64Part);
      const hostPort: string = decoded.indexOf('@') >= 0 ? decoded.substring(decoded.indexOf('@') + 1) : decoded;
      const colon: number = hostPort.lastIndexOf(':');
      server = colon > 0 ? hostPort.substring(0, colon) : hostPort;
      port = colon > 0 ? toPort(hostPort.substring(colon + 1)) : 443;
    }
    if (server.length === 0) {
      return null;
    }
    const node: Node = new Node();
    node.id = hashId(link);
    node.name = uri.fragment.length > 0 ? uri.fragment : 'Shadowsocks Node';
    node.type = NodeType.SHADOWSOCKS;
    node.server = server;
    node.port = port === -1 ? 443 : port;
    node.rawLink = link;
    return node;
  }

  /** 去重：按 rawLink 保留首次出现的节点 */
  static deduplicate(nodes: Node[]): Node[] {
    const seen: Set<string> = new Set<string>();
    const result: Node[] = [];
    for (const node of nodes) {
      if (seen.has(node.rawLink)) {
        continue;
      }
      seen.add(node.rawLink);
      result.push(node);
    }
    return result;
  }
}
